import ColonyCore
import Foundation

package struct ColonyStoreSnapshot: Sendable, Codable, Equatable {
    package var messages: [SwarmChatMessage]
    package var llmInputMessages: [SwarmChatMessage]?
    package var pendingToolCalls: [SwarmToolCall]
    package var finalAnswer: String?
    package var todos: [ColonyTodo]
    package var currentToolCall: SwarmToolCall?

    package init(
        messages: [SwarmChatMessage] = [],
        llmInputMessages: [SwarmChatMessage]? = nil,
        pendingToolCalls: [SwarmToolCall] = [],
        finalAnswer: String? = nil,
        todos: [ColonyTodo] = [],
        currentToolCall: SwarmToolCall? = nil
    ) {
        self.messages = messages
        self.llmInputMessages = llmInputMessages
        self.pendingToolCalls = pendingToolCalls
        self.finalAnswer = finalAnswer
        self.todos = todos
        self.currentToolCall = currentToolCall
    }
}

public enum ColonyRun {
    public enum CheckpointPolicy: Sendable, Equatable {
        case disabled
        case everyStep
        case every(steps: Int)
        case onInterrupt
    }

    public enum StreamingMode: Sendable, Equatable {
        case events
        case values
        case updates
        case combined
    }

    public struct Options: Sendable, Equatable {
        public var maxSteps: Int
        public var maxConcurrentTasks: Int
        public var checkpointPolicy: CheckpointPolicy
        public var debugPayloads: Bool
        public var deterministicTokenStreaming: Bool
        public var eventBufferCapacity: Int
        public var streamingMode: StreamingMode

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

    public struct EventID: Sendable, Equatable {
        public let runID: ColonyRunID
        public let attemptID: ColonyRunAttemptID
        public let eventIndex: UInt64
        public let stepIndex: Int?
        public let taskOrdinal: Int?

        public init(
            runID: ColonyRunID,
            attemptID: ColonyRunAttemptID,
            eventIndex: UInt64,
            stepIndex: Int? = nil,
            taskOrdinal: Int? = nil
        ) {
            self.runID = runID
            self.attemptID = attemptID
            self.eventIndex = eventIndex
            self.stepIndex = stepIndex
            self.taskOrdinal = taskOrdinal
        }
    }

    public enum CancellationCause: String, Sendable, Codable, Equatable {
        case explicitRequest
        case checkpointPersistenceRace
        case executionObserved
    }

    public struct SnapshotValue: Sendable, Equatable {
        public let channelID: ColonyChannelID
        public let payloadHash: String

        public init(channelID: ColonyChannelID, payloadHash: String) {
            self.channelID = channelID
            self.payloadHash = payloadHash
        }
    }

    public enum EventKind: Sendable, Equatable {
        case runStarted(threadID: ColonyThreadID)
        case runFinished
        case runInterrupted(interruptID: ColonyInterruptID)
        case runResumed(interruptID: ColonyInterruptID)
        case runCancelled(cause: CancellationCause)
        case stepStarted(stepIndex: Int, frontierCount: Int)
        case stepFinished(stepIndex: Int, nextFrontierCount: Int)
        case taskStarted(nodeID: ColonyNodeID, taskID: String)
        case taskFinished(nodeID: ColonyNodeID, taskID: String)
        case taskFailed(nodeID: ColonyNodeID, taskID: String, errorDescription: String)
        case writeApplied(channelID: ColonyChannelID, payloadHash: String)
        case checkpointSaved(checkpointID: ColonyCheckpointID)
        case checkpointLoaded(checkpointID: ColonyCheckpointID)
        case storeSnapshot(channelValues: [SnapshotValue])
        case channelUpdates(channelValues: [SnapshotValue])
        case modelInvocationStarted(model: String)
        case modelToken(text: String)
        case modelInvocationFinished
        case toolInvocationStarted(name: String)
        case toolInvocationFinished(name: String, success: Bool)
        case streamBackpressure(droppedModelTokenEvents: Int, droppedDebugEvents: Int)
        case customDebug(name: String)
    }

    public struct Event: Sendable, Equatable {
        public let id: EventID
        public let kind: EventKind
        public let metadata: [String: String]

        public init(id: EventID, kind: EventKind, metadata: [String: String] = [:]) {
            self.id = id
            self.kind = kind
            self.metadata = metadata
        }
    }

    public struct ProjectedChannelValue: Sendable {
        public let channelID: ColonyChannelID
        public let value: any Sendable

        public init(channelID: ColonyChannelID, value: any Sendable) {
            self.channelID = channelID
            self.value = value
        }
    }

    public struct Store: Sendable {
        private let snapshot: ColonyStoreSnapshot

        package init(_ snapshot: ColonyStoreSnapshot) {
            self.snapshot = snapshot
        }

        package func get<Value: Sendable>(_ key: ColonySchema.ChannelKey<Value>) throws -> Value {
            switch key.id.rawValue {
            case ColonySchema.Channels.messages.id.rawValue:
                return try cast(snapshot.messages, for: key)
            case ColonySchema.Channels.llmInputMessages.id.rawValue:
                return try cast(snapshot.llmInputMessages, for: key)
            case ColonySchema.Channels.pendingToolCalls.id.rawValue:
                return try cast(snapshot.pendingToolCalls, for: key)
            case ColonySchema.Channels.finalAnswer.id.rawValue:
                return try cast(snapshot.finalAnswer, for: key)
            case ColonySchema.Channels.todos.id.rawValue:
                return try cast(snapshot.todos, for: key)
            case ColonySchema.Channels.currentToolCall.id.rawValue:
                return try cast(snapshot.currentToolCall ?? SwarmToolCall(id: "", name: "", argumentsJSON: "{}"), for: key)
            default:
                throw ColonyStoreError.missingChannel(key.id)
            }
        }

        private func cast<Value: Sendable>(
            _ value: some Sendable,
            for key: ColonySchema.ChannelKey<Value>
        ) throws -> Value {
            guard let typed = value as? Value else {
                throw ColonyStoreError.typeMismatch(channelID: key.id)
            }
            return typed
        }
    }

    public enum Output: Sendable {
        case fullStore(Store)
        case channels([ProjectedChannelValue])
    }

    public struct Interruption: Sendable {
        public let interruptID: ColonyInterruptID
        public let payload: ColonyInterruptPayload
        public let checkpointID: ColonyCheckpointID

        public init(
            interruptID: ColonyInterruptID,
            payload: ColonyInterruptPayload,
            checkpointID: ColonyCheckpointID
        ) {
            self.interruptID = interruptID
            self.payload = payload
            self.checkpointID = checkpointID
        }
    }

    public enum Outcome: Sendable {
        case finished(output: Output, checkpointID: ColonyCheckpointID?)
        case interrupted(Interruption)
        case cancelled(output: Output, checkpointID: ColonyCheckpointID?)
        case outOfSteps(maxSteps: Int, output: Output, checkpointID: ColonyCheckpointID?)

        public var isFinished: Bool {
            if case .finished = self { return true }
            return false
        }

        public var isInterrupted: Bool {
            if case .interrupted = self { return true }
            return false
        }
    }

    public struct Handle: Sendable {
        public struct OutcomeFuture: Sendable {
            private let task: Task<Outcome, Error>

            fileprivate init(task: Task<Outcome, Error>) {
                self.task = task
            }

            public var value: Outcome {
                get async throws {
                    try await task.value
                }
            }

            package func cancel() {
                task.cancel()
            }
        }

        public let runID: ColonyRunID
        public let attemptID: ColonyRunAttemptID
        public let events: AsyncThrowingStream<Event, Error>

        private let outcomeTask: Task<Outcome, Error>

        public var outcome: OutcomeFuture {
            OutcomeFuture(task: outcomeTask)
        }

        package init(
            runID: ColonyRunID,
            attemptID: ColonyRunAttemptID,
            events: AsyncThrowingStream<Event, Error>,
            outcome: Task<Outcome, Error>
        ) {
            self.runID = runID
            self.attemptID = attemptID
            self.events = events
            self.outcomeTask = outcome
        }
    }
}

enum ColonyStoreError: Error, Sendable, Equatable {
    case missingChannel(ColonyChannelID)
    case typeMismatch(channelID: ColonyChannelID)
}
