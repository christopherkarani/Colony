import Foundation
import HiveCore

/// Stable identifier for a harness session.
public struct ColonyHarnessSessionID: Hashable, Codable, Sendable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}

/// Session lifecycle state exposed by the harness API.
public enum ColonyHarnessLifecycleState: String, Codable, Sendable {
    case idle
    case running
    case interrupted
    case stopped
}

/// Version of the harness protocol envelope.
public enum ColonyHarnessProtocolVersion: String, Codable, Sendable {
    case v1
}

/// Event type emitted by a harness session stream.
public enum ColonyHarnessEventType: String, Codable, Sendable {
    case runStarted = "run_started"
    case runFinished = "run_finished"
    case runInterrupted = "run_interrupted"
    case runResumed = "run_resumed"
    case runCancelled = "run_cancelled"

    case assistantDelta = "assistant_delta"
    case toolRequest = "tool_request"
    case toolResult = "tool_result"
    case toolDenied = "tool_denied"
}

/// Payload for assistant message delta events.
///
/// Contains incremental text chunks from the assistant's streaming response.
public struct ColonyHarnessAssistantDeltaPayload: Codable, Equatable, Sendable {
    /// The incremental text delta from the assistant.
    public let delta: String

    public init(delta: String) {
        self.delta = delta
    }
}

/// Payload for tool call request events.
///
/// Emitted when the agent requests execution of a tool, containing the tool
/// name and arguments for approval or execution.
public struct ColonyHarnessToolRequestPayload: Codable, Equatable, Sendable {
    /// Unique identifier for this tool call invocation.
    public let toolCallID: String
    /// Name of the tool being invoked.
    public let toolName: String
    /// JSON-encoded arguments passed to the tool.
    public let argumentsJSON: String

    public init(toolCallID: String, toolName: String, argumentsJSON: String) {
        self.toolCallID = toolCallID
        self.toolName = toolName
        self.argumentsJSON = argumentsJSON
    }

    private enum CodingKeys: String, CodingKey {
        case toolCallID = "tool_call_id"
        case toolName = "tool_name"
        case argumentsJSON = "arguments_json"
    }
}

/// Payload for tool execution result events.
///
/// Emitted after a tool call completes, indicating success or failure.
public struct ColonyHarnessToolResultPayload: Codable, Equatable, Sendable {
    /// Unique identifier for the tool call invocation.
    public let toolCallID: String
    /// Name of the tool that was executed.
    public let toolName: String
    /// Whether the tool executed successfully.
    public let success: Bool

    public init(toolCallID: String, toolName: String, success: Bool) {
        self.toolCallID = toolCallID
        self.toolName = toolName
        self.success = success
    }

    private enum CodingKeys: String, CodingKey {
        case toolCallID = "tool_call_id"
        case toolName = "tool_name"
        case success
    }
}

/// Payload for tool denial events.
///
/// Emitted when a tool call was denied by human approval.
public struct ColonyHarnessToolDeniedPayload: Codable, Equatable, Sendable {
    /// Unique identifier for the denied tool call.
    public let toolCallID: String
    /// Name of the tool that was denied.
    public let toolName: String
    /// Human-readable reason for the denial.
    public let reason: String

    public init(toolCallID: String, toolName: String, reason: String) {
        self.toolCallID = toolCallID
        self.toolName = toolName
        self.reason = reason
    }

    private enum CodingKeys: String, CodingKey {
        case toolCallID = "tool_call_id"
        case toolName = "tool_name"
        case reason
    }
}

/// Versioned payload for a harness event envelope.
public enum ColonyHarnessEventPayload: Codable, Equatable, Sendable {
    case assistantDelta(ColonyHarnessAssistantDeltaPayload)
    case toolRequest(ColonyHarnessToolRequestPayload)
    case toolResult(ColonyHarnessToolResultPayload)
    case toolDenied(ColonyHarnessToolDeniedPayload)
    case none

    private enum CodingKeys: String, CodingKey {
        case kind
        case data
    }

    private enum Kind: String, Codable {
        case assistantDelta = "assistant_delta"
        case toolRequest = "tool_request"
        case toolResult = "tool_result"
        case toolDenied = "tool_denied"
        case none
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .kind)

        switch kind {
        case .assistantDelta:
            let payload = try container.decode(ColonyHarnessAssistantDeltaPayload.self, forKey: .data)
            self = .assistantDelta(payload)
        case .toolRequest:
            let payload = try container.decode(ColonyHarnessToolRequestPayload.self, forKey: .data)
            self = .toolRequest(payload)
        case .toolResult:
            let payload = try container.decode(ColonyHarnessToolResultPayload.self, forKey: .data)
            self = .toolResult(payload)
        case .toolDenied:
            let payload = try container.decode(ColonyHarnessToolDeniedPayload.self, forKey: .data)
            self = .toolDenied(payload)
        case .none:
            self = .none
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .assistantDelta(let payload):
            try container.encode(Kind.assistantDelta, forKey: .kind)
            try container.encode(payload, forKey: .data)
        case .toolRequest(let payload):
            try container.encode(Kind.toolRequest, forKey: .kind)
            try container.encode(payload, forKey: .data)
        case .toolResult(let payload):
            try container.encode(Kind.toolResult, forKey: .kind)
            try container.encode(payload, forKey: .data)
        case .toolDenied(let payload):
            try container.encode(Kind.toolDenied, forKey: .kind)
            try container.encode(payload, forKey: .data)
        case .none:
            try container.encode(Kind.none, forKey: .kind)
        }
    }
}

/// Stable, versioned envelope for harness stream events.
public struct ColonyHarnessEventEnvelope: Codable, Equatable, Sendable {
    public let protocolVersion: ColonyHarnessProtocolVersion
    public let eventType: ColonyHarnessEventType
    public let sequence: Int
    public let timestamp: Date
    public let runID: UUID
    public let sessionID: ColonyHarnessSessionID
    public let payload: ColonyHarnessEventPayload

    public init(
        protocolVersion: ColonyHarnessProtocolVersion,
        eventType: ColonyHarnessEventType,
        sequence: Int,
        timestamp: Date,
        runID: UUID,
        sessionID: ColonyHarnessSessionID,
        payload: ColonyHarnessEventPayload
    ) {
        self.protocolVersion = protocolVersion
        self.eventType = eventType
        self.sequence = sequence
        self.timestamp = timestamp
        self.runID = runID
        self.sessionID = sessionID
        self.payload = payload
    }

    private enum CodingKeys: String, CodingKey {
        case protocolVersion = "protocol_version"
        case eventType = "event_type"
        case sequence
        case timestamp
        case runID = "run_id"
        case sessionID = "session_id"
        case payload
    }
}

/// Pending interruption surfaced through the harness session API.
public struct ColonyHarnessInterruption: Sendable {
    public let runID: UUID
    public let interruptID: HiveInterruptID
    public let toolCalls: [HiveToolCall]

    public init(runID: UUID, interruptID: HiveInterruptID, toolCalls: [HiveToolCall]) {
        self.runID = runID
        self.interruptID = interruptID
        self.toolCalls = toolCalls
    }
}
