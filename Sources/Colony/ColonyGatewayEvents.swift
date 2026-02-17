import Foundation

public enum ColonyRuntimeEventKind: String, Codable, Sendable, Equatable {
    case runStarted = "run_started"
    case toolDispatched = "tool_dispatched"
    case toolResult = "tool_result"
    case runInterrupted = "run_interrupted"
    case runCompleted = "run_completed"
    case subagentStarted = "subagent_started"
    case subagentCompleted = "subagent_completed"
}

public struct ColonyRuntimeToolDispatchedPayload: Codable, Sendable, Equatable {
    public var toolCallID: String
    public var toolName: String
    public var argumentsJSON: String?

    public init(toolCallID: String, toolName: String, argumentsJSON: String? = nil) {
        self.toolCallID = toolCallID
        self.toolName = toolName
        self.argumentsJSON = argumentsJSON
    }
}

public struct ColonyRuntimeToolResultPayload: Codable, Sendable, Equatable {
    public var toolCallID: String
    public var toolName: String
    public var result: ColonyToolResultEnvelope

    public init(toolCallID: String, toolName: String, result: ColonyToolResultEnvelope) {
        self.toolCallID = toolCallID
        self.toolName = toolName
        self.result = result
    }
}

public struct ColonyRuntimeInterruptionPayload: Codable, Sendable, Equatable {
    public var reason: ColonyInterruptionReason
    public var classification: ColonyFailureClassification
    public var interruptID: String?

    public init(
        reason: ColonyInterruptionReason,
        classification: ColonyFailureClassification,
        interruptID: String? = nil
    ) {
        self.reason = reason
        self.classification = classification
        self.interruptID = interruptID
    }
}

public struct ColonyRuntimeCompletionPayload: Codable, Sendable, Equatable {
    public var status: String
    public var finalAnswer: String?

    public init(status: String, finalAnswer: String? = nil) {
        self.status = status
        self.finalAnswer = finalAnswer
    }
}

public struct ColonyRuntimeSubagentPayload: Codable, Sendable, Equatable {
    public var subagentID: String
    public var childRunID: UUID
    public var state: ColonySubagentLifecycleState

    public init(
        subagentID: String,
        childRunID: UUID,
        state: ColonySubagentLifecycleState
    ) {
        self.subagentID = subagentID
        self.childRunID = childRunID
        self.state = state
    }
}

public enum ColonyRuntimeEventPayload: Codable, Sendable, Equatable {
    case none
    case toolDispatched(ColonyRuntimeToolDispatchedPayload)
    case toolResult(ColonyRuntimeToolResultPayload)
    case interruption(ColonyRuntimeInterruptionPayload)
    case completion(ColonyRuntimeCompletionPayload)
    case subagent(ColonyRuntimeSubagentPayload)

    private enum CodingKeys: String, CodingKey {
        case kind
        case data
    }

    private enum Kind: String, Codable {
        case none
        case toolDispatched = "tool_dispatched"
        case toolResult = "tool_result"
        case interruption
        case completion
        case subagent
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .kind)
        switch kind {
        case .none:
            self = .none
        case .toolDispatched:
            self = .toolDispatched(try container.decode(ColonyRuntimeToolDispatchedPayload.self, forKey: .data))
        case .toolResult:
            self = .toolResult(try container.decode(ColonyRuntimeToolResultPayload.self, forKey: .data))
        case .interruption:
            self = .interruption(try container.decode(ColonyRuntimeInterruptionPayload.self, forKey: .data))
        case .completion:
            self = .completion(try container.decode(ColonyRuntimeCompletionPayload.self, forKey: .data))
        case .subagent:
            self = .subagent(try container.decode(ColonyRuntimeSubagentPayload.self, forKey: .data))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .none:
            try container.encode(Kind.none, forKey: .kind)
        case .toolDispatched(let payload):
            try container.encode(Kind.toolDispatched, forKey: .kind)
            try container.encode(payload, forKey: .data)
        case .toolResult(let payload):
            try container.encode(Kind.toolResult, forKey: .kind)
            try container.encode(payload, forKey: .data)
        case .interruption(let payload):
            try container.encode(Kind.interruption, forKey: .kind)
            try container.encode(payload, forKey: .data)
        case .completion(let payload):
            try container.encode(Kind.completion, forKey: .kind)
            try container.encode(payload, forKey: .data)
        case .subagent(let payload):
            try container.encode(Kind.subagent, forKey: .kind)
            try container.encode(payload, forKey: .data)
        }
    }
}

public struct ColonyRuntimeEvent: Codable, Sendable, Equatable {
    public var sequence: Int
    public var timestamp: Date
    public var kind: ColonyRuntimeEventKind
    public var runID: UUID
    public var sessionID: ColonyRuntimeSessionID
    public var agentID: String
    public var subagentID: String?
    public var correlationChain: [String]
    public var payload: ColonyRuntimeEventPayload

    public init(
        sequence: Int,
        timestamp: Date,
        kind: ColonyRuntimeEventKind,
        runID: UUID,
        sessionID: ColonyRuntimeSessionID,
        agentID: String,
        subagentID: String? = nil,
        correlationChain: [String] = [],
        payload: ColonyRuntimeEventPayload = .none
    ) {
        self.sequence = sequence
        self.timestamp = timestamp
        self.kind = kind
        self.runID = runID
        self.sessionID = sessionID
        self.agentID = agentID
        self.subagentID = subagentID
        self.correlationChain = correlationChain
        self.payload = payload
    }
}

public actor ColonyRuntimeEventBus {
    private let maxRetainedEvents: Int
    private var sequence: Int = 0
    private var subscribers: [UUID: AsyncStream<ColonyRuntimeEvent>.Continuation] = [:]
    private var history: [ColonyRuntimeEvent] = []

    public init(maxRetainedEvents: Int = 2_000) {
        self.maxRetainedEvents = max(1, maxRetainedEvents)
    }

    public func subscribe(bufferingLimit: Int = 256) -> AsyncStream<ColonyRuntimeEvent> {
        let subscriberID = UUID()
        let stream = AsyncStream<ColonyRuntimeEvent>(bufferingPolicy: .bufferingNewest(max(1, bufferingLimit))) { continuation in
            subscribers[subscriberID] = continuation
            continuation.onTermination = { _ in
                Task { await self.removeSubscriber(subscriberID) }
            }
        }
        return stream
    }

    public func emit(
        kind: ColonyRuntimeEventKind,
        runID: UUID,
        sessionID: ColonyRuntimeSessionID,
        agentID: String,
        subagentID: String? = nil,
        correlationChain: [String] = [],
        payload: ColonyRuntimeEventPayload = .none
    ) -> ColonyRuntimeEvent {
        sequence += 1
        let event = ColonyRuntimeEvent(
            sequence: sequence,
            timestamp: Date(),
            kind: kind,
            runID: runID,
            sessionID: sessionID,
            agentID: agentID,
            subagentID: subagentID,
            correlationChain: correlationChain,
            payload: payload
        )

        history.append(event)
        if history.count > maxRetainedEvents {
            history.removeFirst(history.count - maxRetainedEvents)
        }

        for continuation in subscribers.values {
            continuation.yield(event)
        }
        return event
    }

    public func recent(limit: Int = 200) -> [ColonyRuntimeEvent] {
        guard limit > 0 else { return [] }
        return Array(history.suffix(limit))
    }

    private func removeSubscriber(_ id: UUID) {
        subscribers.removeValue(forKey: id)
    }
}
