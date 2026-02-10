import Foundation
import HiveCore
import ColonyCore

public struct ColonyObservabilityEvent: Codable, Sendable, Equatable {
    public let name: String
    public let timestamp: Date
    public let runID: UUID?
    public let sessionID: String?
    public let threadID: String?
    public let attributes: [String: String]

    public init(
        name: String,
        timestamp: Date,
        runID: UUID? = nil,
        sessionID: String? = nil,
        threadID: String? = nil,
        attributes: [String: String] = [:]
    ) {
        self.name = name
        self.timestamp = timestamp
        self.runID = runID
        self.sessionID = sessionID
        self.threadID = threadID
        self.attributes = attributes
    }
}

public protocol ColonyObservabilitySink: Sendable {
    func emit(_ event: ColonyObservabilityEvent) async
}

public actor ColonyInMemoryObservabilitySink: ColonyObservabilitySink {
    private var eventsStorage: [ColonyObservabilityEvent] = []

    public init() {}

    public func emit(_ event: ColonyObservabilityEvent) async {
        eventsStorage.append(event)
    }

    public func events() -> [ColonyObservabilityEvent] {
        eventsStorage
    }
}

public actor ColonyObservabilityEmitter {
    private let redactionPolicy: ColonyRedactionPolicy
    private let sinks: [any ColonyObservabilitySink]

    public init(
        sinks: [any ColonyObservabilitySink],
        redactionPolicy: ColonyRedactionPolicy = ColonyRedactionPolicy()
    ) {
        self.sinks = sinks
        self.redactionPolicy = redactionPolicy
    }

    public func emit(_ event: ColonyObservabilityEvent) async {
        let redacted = ColonyObservabilityEvent(
            name: event.name,
            timestamp: event.timestamp,
            runID: event.runID,
            sessionID: event.sessionID,
            threadID: event.threadID,
            attributes: redactionPolicy.redact(values: event.attributes)
        )

        for sink in sinks {
            await sink.emit(redacted)
        }
    }

    public func emitHarnessEnvelope(_ envelope: ColonyHarnessEventEnvelope, threadID: HiveThreadID) async {
        var attributes: [String: String] = [
            "event_type": envelope.eventType.rawValue,
            "sequence": String(envelope.sequence),
            "protocol_version": envelope.protocolVersion.rawValue,
        ]

        for (key, value) in flatten(payload: envelope.payload) {
            attributes[key] = value
        }

        let event = ColonyObservabilityEvent(
            name: "colony.harness.\(envelope.eventType.rawValue)",
            timestamp: envelope.timestamp,
            runID: envelope.runID,
            sessionID: envelope.sessionID.rawValue,
            threadID: threadID.rawValue,
            attributes: attributes
        )

        await emit(event)
    }

    private func flatten(payload: ColonyHarnessEventPayload) -> [String: String] {
        switch payload {
        case .assistantDelta(let payload):
            return ["delta": payload.delta]
        case .toolRequest(let payload):
            return [
                "tool_call_id": payload.toolCallID,
                "tool_name": payload.toolName,
                "arguments_json": payload.argumentsJSON,
            ]
        case .toolResult(let payload):
            return [
                "tool_call_id": payload.toolCallID,
                "tool_name": payload.toolName,
                "success": payload.success ? "true" : "false",
            ]
        case .toolDenied(let payload):
            return [
                "tool_call_id": payload.toolCallID,
                "tool_name": payload.toolName,
                "reason": payload.reason,
            ]
        case .none:
            return [:]
        }
    }
}
