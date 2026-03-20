import Foundation
import HiveCore

public enum ColonyRunCheckpointPolicy: Sendable, Equatable {
    case disabled
    case everyStep
    case every(steps: Int)
    case onInterrupt
}

public enum ColonyRunStreamingMode: Sendable, Equatable {
    case events
    case values
    case updates
    case combined
}

public struct ColonyRunOptions: Sendable, Equatable {
    public let maxSteps: Int
    public let maxConcurrentTasks: Int
    public let checkpointPolicy: ColonyRunCheckpointPolicy
    public let debugPayloads: Bool
    public let deterministicTokenStreaming: Bool
    public let eventBufferCapacity: Int
    public let streamingMode: ColonyRunStreamingMode

    public init(
        maxSteps: Int = 100,
        maxConcurrentTasks: Int = 8,
        checkpointPolicy: ColonyRunCheckpointPolicy = .disabled,
        debugPayloads: Bool = false,
        deterministicTokenStreaming: Bool = false,
        eventBufferCapacity: Int = 4096,
        streamingMode: ColonyRunStreamingMode = .events
    ) {
        self.maxSteps = maxSteps
        self.maxConcurrentTasks = maxConcurrentTasks
        self.checkpointPolicy = checkpointPolicy
        self.debugPayloads = debugPayloads
        self.deterministicTokenStreaming = deterministicTokenStreaming
        self.eventBufferCapacity = eventBufferCapacity
        self.streamingMode = streamingMode
    }
}

public struct ColonyTranscript: Sendable, Equatable {
    public let messages: [ColonyChatMessage]
    public let finalAnswer: String?
    public let todos: [ColonyTodo]

    public init(
        messages: [ColonyChatMessage] = [],
        finalAnswer: String? = nil,
        todos: [ColonyTodo] = []
    ) {
        self.messages = messages
        self.finalAnswer = finalAnswer
        self.todos = todos
    }
}

public struct ColonyRunInterruption: Sendable, Equatable {
    public let interruptID: ColonyInterruptID
    public let toolCalls: [ColonyToolCall]
    public let checkpointID: ColonyCheckpointID

    public init(
        interruptID: ColonyInterruptID,
        toolCalls: [ColonyToolCall],
        checkpointID: ColonyCheckpointID
    ) {
        self.interruptID = interruptID
        self.toolCalls = toolCalls
        self.checkpointID = checkpointID
    }
}

public enum ColonyRunOutcome: Sendable, Equatable {
    case finished(transcript: ColonyTranscript, checkpointID: ColonyCheckpointID?)
    case interrupted(ColonyRunInterruption)
    case cancelled(transcript: ColonyTranscript, checkpointID: ColonyCheckpointID?)
    case outOfSteps(maxSteps: Int, transcript: ColonyTranscript, checkpointID: ColonyCheckpointID?)
}

public struct ColonyRunStartRequest: Sendable, Equatable {
    public var input: String
    public var optionsOverride: ColonyRunOptions?

    public init(
        input: String,
        optionsOverride: ColonyRunOptions? = nil
    ) {
        self.input = input
        self.optionsOverride = optionsOverride
    }

    package init(
        input: String,
        optionsOverride: HiveRunOptions? = nil
    ) {
        self.init(
            input: input,
            optionsOverride: optionsOverride.map {
                ColonyRunOptions(
                    maxSteps: $0.maxSteps,
                    maxConcurrentTasks: $0.maxConcurrentTasks,
                    checkpointPolicy: mapCheckpointPolicy($0.checkpointPolicy),
                    debugPayloads: $0.debugPayloads,
                    deterministicTokenStreaming: $0.deterministicTokenStreaming,
                    eventBufferCapacity: $0.eventBufferCapacity,
                    streamingMode: mapStreamingMode($0.streamingMode)
                )
            }
        )
    }
}

public struct ColonyRunResumeRequest: Sendable, Equatable {
    public var interruptID: ColonyInterruptID
    public var decision: ColonyToolApprovalDecision
    public var optionsOverride: ColonyRunOptions?

    public init(
        interruptID: ColonyInterruptID,
        decision: ColonyToolApprovalDecision,
        optionsOverride: ColonyRunOptions? = nil
    ) {
        self.interruptID = interruptID
        self.decision = decision
        self.optionsOverride = optionsOverride
    }

    package init(
        interruptID: HiveInterruptID,
        decision: ColonyToolApprovalDecision,
        optionsOverride: HiveRunOptions? = nil
    ) {
        self.init(
            interruptID: ColonyInterruptID(interruptID.rawValue),
            decision: decision,
            optionsOverride: optionsOverride.map {
                ColonyRunOptions(
                    maxSteps: $0.maxSteps,
                    maxConcurrentTasks: $0.maxConcurrentTasks,
                    checkpointPolicy: mapCheckpointPolicy($0.checkpointPolicy),
                    debugPayloads: $0.debugPayloads,
                    deterministicTokenStreaming: $0.deterministicTokenStreaming,
                    eventBufferCapacity: $0.eventBufferCapacity,
                    streamingMode: mapStreamingMode($0.streamingMode)
                )
            }
        )
    }
}

private func mapCheckpointPolicy(_ policy: HiveCheckpointPolicy) -> ColonyRunCheckpointPolicy {
    switch policy {
    case .disabled:
        return .disabled
    case .everyStep:
        return .everyStep
    case .every(let steps):
        return .every(steps: steps)
    case .onInterrupt:
        return .onInterrupt
    }
}

private func mapStreamingMode(_ mode: HiveStreamingMode) -> ColonyRunStreamingMode {
    switch mode {
    case .events:
        return .events
    case .values:
        return .values
    case .updates:
        return .updates
    case .combined:
        return .combined
    }
}

public struct ColonyRunHandle: Sendable {
    public let runID: UUID
    public let attemptID: UUID
    public let outcome: Task<ColonyRunOutcome, Error>

    public init(
        runID: UUID,
        attemptID: UUID,
        outcome: Task<ColonyRunOutcome, Error>
    ) {
        self.runID = runID
        self.attemptID = attemptID
        self.outcome = outcome
    }
}

public enum ColonyCheckpointConfiguration: Sendable, Equatable {
    case inMemory
    case durable(URL)
}
