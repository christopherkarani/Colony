import Foundation

// ColonyHarnessSessionID is now a typealias defined in ColonyID.swift
// via ColonyHarnessSessionID (ColonyID<ColonyIDDomain.HarnessSession>).

/// Namespace for harness protocol types.
public enum ColonyHarness {}

// MARK: - Lifecycle State

extension ColonyHarness {
    /// Session lifecycle state exposed by the harness API.
    public enum LifecycleState: String, Codable, Sendable {
        case idle
        case running
        case interrupted
        case stopped
    }
}

// MARK: - Protocol Version

extension ColonyHarness {
    /// Version of the harness protocol envelope.
    public enum ProtocolVersion: String, Codable, Sendable {
        case v1
    }
}

// MARK: - Event Type

extension ColonyHarness {
    /// Event type emitted by a harness session stream.
    public enum EventType: String, Codable, Sendable {
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
}

// MARK: - Payload Types

extension ColonyHarness {
    public struct AssistantDeltaPayload: Codable, Equatable, Sendable {
        public let delta: String

        public init(delta: String) {
            self.delta = delta
        }
    }

    public struct ToolRequestPayload: Codable, Equatable, Sendable {
        public let toolCallID: ColonyToolCallID
        public let toolName: String
        public let argumentsJSON: String

        public init(toolCallID: ColonyToolCallID, toolName: String, argumentsJSON: String) {
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

    public struct ToolResultPayload: Codable, Equatable, Sendable {
        public let toolCallID: ColonyToolCallID
        public let toolName: String
        public let success: Bool

        public init(toolCallID: ColonyToolCallID, toolName: String, success: Bool) {
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

    public struct ToolDeniedPayload: Codable, Equatable, Sendable {
        public let toolCallID: ColonyToolCallID
        public let toolName: String
        public let reason: String

        public init(toolCallID: ColonyToolCallID, toolName: String, reason: String) {
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
}

// MARK: - Event Payload

extension ColonyHarness {
    /// Versioned payload for a harness event envelope.
    public enum EventPayload: Codable, Equatable, Sendable {
        case assistantDelta(AssistantDeltaPayload)
        case toolRequest(ToolRequestPayload)
        case toolResult(ToolResultPayload)
        case toolDenied(ToolDeniedPayload)
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
                let payload = try container.decode(AssistantDeltaPayload.self, forKey: .data)
                self = .assistantDelta(payload)
            case .toolRequest:
                let payload = try container.decode(ToolRequestPayload.self, forKey: .data)
                self = .toolRequest(payload)
            case .toolResult:
                let payload = try container.decode(ToolResultPayload.self, forKey: .data)
                self = .toolResult(payload)
            case .toolDenied:
                let payload = try container.decode(ToolDeniedPayload.self, forKey: .data)
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
}

// MARK: - Event Envelope

extension ColonyHarness {
    /// Stable, versioned envelope for harness stream events.
    public struct EventEnvelope: Codable, Equatable, Sendable {
        public let protocolVersion: ProtocolVersion
        public let eventType: EventType
        public let sequence: Int
        public let timestamp: Date
        public let runID: UUID
        public let sessionID: ColonyHarnessSessionID
        public let payload: EventPayload

        public init(
            protocolVersion: ProtocolVersion,
            eventType: EventType,
            sequence: Int,
            timestamp: Date,
            runID: UUID,
            sessionID: ColonyHarnessSessionID,
            payload: EventPayload
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
}

// MARK: - Interruption

extension ColonyHarness {
    /// Pending interruption surfaced through the harness session API.
    public struct Interruption: Sendable {
        public let runID: UUID
        public let interruptID: ColonyInterruptID
        public let toolCalls: [ColonyTool.Call]

        public init(runID: UUID, interruptID: ColonyInterruptID, toolCalls: [ColonyTool.Call]) {
            self.runID = runID
            self.interruptID = interruptID
            self.toolCalls = toolCalls
        }
    }
}

