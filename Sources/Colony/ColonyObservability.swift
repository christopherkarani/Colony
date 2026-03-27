import Foundation
import ColonyCore

/// An observability event emitted by Colony.
///
/// Events capture runtime behavior for monitoring, debugging, and analytics.
public struct ColonyObservabilityEvent: Codable, Sendable, Equatable {
    /// The event name.
    public let name: String

    /// When the event occurred.
    public let timestamp: Date

    /// The run this event belongs to, if any.
    public let runID: ColonyRunID?

    /// The session this event belongs to, if any.
    public let sessionID: ColonyHarnessSessionID?

    /// The thread this event belongs to, if any.
    public let threadID: ColonyThreadID?

    /// Additional event attributes.
    public let attributes: [String: String]

    /// Creates a new observability event.
    ///
    /// - Parameters:
    ///   - name: Event name.
    ///   - timestamp: Event timestamp.
    ///   - runID: Optional run ID.
    ///   - sessionID: Optional session ID.
    ///   - threadID: Optional thread ID.
    ///   - attributes: Additional attributes.
    public init(
        name: String,
        timestamp: Date,
        runID: ColonyRunID? = nil,
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

/// Protocol for observability event sinks.
///
/// Implement this protocol to receive Colony observability events
/// for external monitoring systems.
public protocol ColonyObservabilitySink: Sendable {
    /// Emits an observability event.
    ///
    /// - Parameter event: The event to emit.
    func emit(_ event: ColonyObservabilityEvent) async
}

/// An in-memory observability sink for testing and debugging.
///
/// This sink stores events in memory and provides a method to retrieve them.
public actor ColonyInMemoryObservabilitySink: ColonyObservabilitySink {
    private var eventsStorage: [ColonyObservabilityEvent] = []

    public init() {}

    public func emit(_ event: ColonyObservabilityEvent) async {
        eventsStorage.append(event)
    }

    /// Returns all stored events.
    ///
    /// - Returns: All observability events collected so far.
    public func events() -> [ColonyObservabilityEvent] {
        eventsStorage
    }
}

/// Emits observability events to configured sinks.
///
/// This actor handles event emission with automatic redaction
/// of sensitive information before forwarding to sinks.
public actor ColonyObservabilityEmitter {
    private let redactionPolicy: ColonyRedactionPolicy
    private let sinks: [any ColonyObservabilitySink]

    /// Creates a new observability emitter.
    ///
    /// - Parameters:
    ///   - sinks: Sinks to emit events to.
    ///   - redactionPolicy: Policy for redacting sensitive data.
    public init(
        sinks: [any ColonyObservabilitySink],
        redactionPolicy: ColonyRedactionPolicy = ColonyRedactionPolicy()
    ) {
        self.sinks = sinks
        self.redactionPolicy = redactionPolicy
    }

    /// Emits an event to all sinks with automatic redaction.
    ///
    /// - Parameter event: The event to emit.
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

    /// Emits a harness event envelope as an observability event.
    ///
    /// - Parameters:
    ///   - envelope: The harness event envelope.
    ///   - threadID: The thread ID for the event.
    public func emitHarnessEnvelope(_ envelope: ColonyHarnessEventEnvelope, threadID: ColonyThreadID) async {
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
            runID: ColonyRunID(rawValue: envelope.runID.uuidString),
            sessionID: envelope.sessionID,
            threadID: threadID,
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
