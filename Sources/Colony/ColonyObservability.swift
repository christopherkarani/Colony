import Foundation
import ColonyCore

/// Type-safe observability event name with autocomplete for standard events.
public struct ColonyEventName: Hashable, Codable, Sendable,
                                ExpressibleByStringLiteral,
                                CustomStringConvertible {
    public let rawValue: String
    public init(_ rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { self.init(value) }
    public var description: String { rawValue }
}

extension ColonyEventName {
    public static let runStarted: ColonyEventName = "run.started"
    public static let runFinished: ColonyEventName = "run.finished"
    public static let runInterrupted: ColonyEventName = "run.interrupted"
    public static let runResumed: ColonyEventName = "run.resumed"
    public static let runCancelled: ColonyEventName = "run.cancelled"
    public static let toolInvoked: ColonyEventName = "tool.invoked"
    public static let toolApprovalRequired: ColonyEventName = "tool.approval_required"
    public static let toolApprovalDecided: ColonyEventName = "tool.approval_decided"
    public static let modelRequestSent: ColonyEventName = "model.request_sent"
    public static let modelResponseReceived: ColonyEventName = "model.response_received"
    public static let compactionTriggered: ColonyEventName = "compaction.triggered"
    public static let checkpointCreated: ColonyEventName = "checkpoint.created"
}

public struct ColonyObservabilityEvent: Codable, Sendable, Equatable {
    public let name: ColonyEventName
    public let timestamp: Date
    public let runID: UUID?
    public let sessionID: ColonyHarnessSessionID?
    public let threadID: ColonyThreadID?
    public let attributes: [String: String]

    public init(
        name: ColonyEventName,
        timestamp: Date,
        runID: UUID? = nil,
        sessionID: ColonyHarnessSessionID? = nil,
        threadID: ColonyThreadID? = nil,
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

package actor ColonyInMemoryObservabilitySink: ColonyObservabilitySink {
    private var eventsStorage: [ColonyObservabilityEvent] = []

    package init() {}

    package func emit(_ event: ColonyObservabilityEvent) async {
        eventsStorage.append(event)
    }

    package func events() -> [ColonyObservabilityEvent] {
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

    public func emitHarnessEnvelope(_ envelope: ColonyHarness.EventEnvelope, threadID: ColonyThreadID) async {
        var attributes: [String: String] = [
            "event_type": envelope.eventType.rawValue,
            "sequence": String(envelope.sequence),
            "protocol_version": envelope.protocolVersion.rawValue,
        ]

        for (key, value) in flatten(payload: envelope.payload) {
            attributes[key] = value
        }

        let event = ColonyObservabilityEvent(
            name: ColonyEventName("colony.harness.\(envelope.eventType.rawValue)"),
            timestamp: envelope.timestamp,
            runID: envelope.runID,
            sessionID: envelope.sessionID,
            threadID: threadID,
            attributes: attributes
        )

        await emit(event)
    }

    private func flatten(payload: ColonyHarness.EventPayload) -> [String: String] {
        switch payload {
        case .assistantDelta(let payload):
            return ["delta": payload.delta]
        case .toolRequest(let payload):
            return [
                "tool_call_id": payload.toolCallID.rawValue,
                "tool_name": payload.toolName,
                "arguments_json": payload.argumentsJSON,
            ]
        case .toolResult(let payload):
            return [
                "tool_call_id": payload.toolCallID.rawValue,
                "tool_name": payload.toolName,
                "success": payload.success ? "true" : "false",
            ]
        case .toolDenied(let payload):
            return [
                "tool_call_id": payload.toolCallID.rawValue,
                "tool_name": payload.toolName,
                "reason": payload.reason,
            ]
        case .none:
            return [:]
        }
    }
}
