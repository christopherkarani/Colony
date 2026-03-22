import Foundation
import HiveCore

// MARK: - ColonyRun Namespace

/// Namespace for runtime-related types including run outcomes, handles, and configuration.
public enum ColonyRun {}

// MARK: - CheckpointPolicy

extension ColonyRun {
    /// Policy for when checkpoints are created during a run.
    public enum CheckpointPolicy: Sendable, Equatable {
        /// No checkpointing
        case disabled
        /// Checkpoint after every superstep (expensive but safe)
        case everyStep
        /// Checkpoint every N supersteps
        case every(steps: Int)
        /// Checkpoint only when an interrupt occurs
        case onInterrupt
    }
}

// MARK: - StreamingMode

extension ColonyRun {
    /// Mode for streaming responses from the runtime.
    public enum StreamingMode: Sendable, Equatable {
        case events    /// Stream SSE events
        case values    /// Stream individual values
        case updates   /// Stream updates
        case combined  /// Combined streaming
    }
}

// MARK: - Options

extension ColonyRun {
    /// Runtime options for a single run.
    public struct Options: Sendable, Equatable {
        public let maxSteps: Int
        public let maxConcurrentTasks: Int
        public let checkpointPolicy: CheckpointPolicy
        public let debugPayloads: Bool
        public let deterministicTokenStreaming: Bool
        public let eventBufferCapacity: Int
        public let streamingMode: StreamingMode

        public init(
            maxSteps: Int = 100,
            maxConcurrentTasks: Int = 8,
            checkpointPolicy: CheckpointPolicy = .disabled,
            debugPayloads: Bool = false,
            deterministicTokenStreaming: Bool = false,
            eventBufferCapacity: Int = 4096,
            streamingMode: StreamingMode = .events
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
}

// MARK: - Transcript

extension ColonyRun {
    /// The complete transcript of a run including messages and todos.
    public struct Transcript: Sendable, Equatable {
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
}

// MARK: - Interruption

extension ColonyRun {
    /// Represents an interrupt during agent execution (e.g., tool approval required).
    public struct Interruption: Sendable, Equatable {
        /// Unique identifier for this interrupt, used to resume
        public let interruptID: ColonyInterruptID
        /// The tool calls awaiting approval
        public let toolCalls: [ColonyTool.Call]
        /// Checkpoint ID for resuming from this interrupt
        public let checkpointID: ColonyCheckpointID

        public init(
            interruptID: ColonyInterruptID,
            toolCalls: [ColonyTool.Call],
            checkpointID: ColonyCheckpointID
        ) {
            self.interruptID = interruptID
            self.toolCalls = toolCalls
            self.checkpointID = checkpointID
        }
    }
}

// MARK: - Outcome

extension ColonyRun {
    /// The final outcome of a run.
    public enum Outcome: Sendable, Equatable {
        /// Run completed successfully with transcript
        case finished(transcript: Transcript, checkpointID: ColonyCheckpointID?)
        /// Run was interrupted (e.g., tool approval required)
        case interrupted(Interruption)
        /// Run was cancelled
        case cancelled(transcript: Transcript, checkpointID: ColonyCheckpointID?)
        /// Run hit max steps limit
        case outOfSteps(maxSteps: Int, transcript: Transcript, checkpointID: ColonyCheckpointID?)
    }
}

// MARK: - StartRequest

extension ColonyRun {
    /// Request to start a new run.
    public struct StartRequest: Sendable, Equatable {
        public var input: String
        public var optionsOverride: Options?

        public init(
            input: String,
            optionsOverride: Options? = nil
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
                    Options(
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
}

// MARK: - ResumeRequest

extension ColonyRun {
    /// Request to resume a run after an interrupt.
    public struct ResumeRequest: Sendable, Equatable {
        public var interruptID: ColonyInterruptID
        public var decision: ColonyToolApproval.Decision
        public var optionsOverride: Options?

        public init(
            interruptID: ColonyInterruptID,
            decision: ColonyToolApproval.Decision,
            optionsOverride: Options? = nil
        ) {
            self.interruptID = interruptID
            self.decision = decision
            self.optionsOverride = optionsOverride
        }

        package init(
            interruptID: HiveInterruptID,
            decision: ColonyToolApproval.Decision,
            optionsOverride: HiveRunOptions? = nil
        ) {
            self.init(
                interruptID: ColonyInterruptID(interruptID.rawValue),
                decision: decision,
                optionsOverride: optionsOverride.map {
                    Options(
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
}

// MARK: - Handle

extension ColonyRun {
    /// Handle for an in-progress run, returned immediately when sending a message.
    ///
    /// Await `outcome` to get the final result:
    /// ```swift
    /// let handle = await agent.send("Hello")
    /// let outcome = try await handle.outcome.value
    /// ```
    public struct Handle: Sendable {
        public let runID: ColonyRunID
        public let attemptID: ColonyAttemptID
        public let outcome: Task<Outcome, Error>

        public init(
            runID: ColonyRunID,
            attemptID: ColonyAttemptID,
            outcome: Task<Outcome, Error>
        ) {
            self.runID = runID
            self.attemptID = attemptID
            self.outcome = outcome
        }
    }
}

// MARK: - CheckpointConfiguration

extension ColonyRun {
    /// Configuration for checkpoint storage.
    public enum CheckpointConfiguration: Sendable, Equatable {
        /// In-memory checkpoints (lost on restart)
        case inMemory
        /// Durable checkpoints at URL (persist across restarts)
        case durable(URL)
    }
}

// MARK: - Private Mapping Helpers

private func mapCheckpointPolicy(_ policy: HiveCheckpointPolicy) -> ColonyRun.CheckpointPolicy {
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

private func mapStreamingMode(_ mode: HiveStreamingMode) -> ColonyRun.StreamingMode {
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

