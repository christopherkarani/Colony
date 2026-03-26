@_spi(ColonyInternal) import Swarm
import ColonyCore

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

    public struct EventID: Sendable, Equatable {
        public let runID: ColonyRunID
        public let attemptID: ColonyRunAttemptID
        public let eventIndex: UInt64
        public let stepIndex: Int?
        public let taskOrdinal: Int?
    }

    public enum CancellationCause: String, Sendable, Codable, Equatable {
        case explicitRequest
        case checkpointPersistenceRace
        case executionObserved
    }

    public struct SnapshotValue: Sendable, Equatable {
        public let channelID: ColonyChannelID
        public let payloadHash: String
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
    }

    public struct ProjectedChannelValue: Sendable {
        public let channelID: ColonyChannelID
        public let value: any Sendable
    }

    public struct Store: Sendable {
        package let hiveStore: HiveGlobalStore<ColonySchema>

        package init(_ hiveStore: HiveGlobalStore<ColonySchema>) {
            self.hiveStore = hiveStore
        }

        package func get<Value: Sendable>(_ key: HiveChannelKey<ColonySchema, Value>) throws -> Value {
            try hiveStore.get(key)
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
        package let hiveHandle: HiveRunHandle<ColonySchema>

        public var runID: ColonyRunID {
            ColonyRunID(hiveRunID: hiveHandle.runID)
        }

        public var attemptID: ColonyRunAttemptID {
            ColonyRunAttemptID(hiveAttemptID: hiveHandle.attemptID)
        }

        public var events: AsyncThrowingStream<Event, Error> {
            AsyncThrowingStream { continuation in
                Task {
                    do {
                        for try await event in hiveHandle.events {
                            continuation.yield(Event(event))
                        }
                        continuation.finish()
                    } catch {
                        continuation.finish(throwing: error)
                    }
                }
            }
        }

        public var outcome: Task<Outcome, Error> {
            Task {
                try await Outcome(hiveHandle: hiveHandle)
            }
        }

        package init(wrapping hiveHandle: HiveRunHandle<ColonySchema>) {
            self.hiveHandle = hiveHandle
        }
    }
}

package extension ColonyRun.Options {
    init(_ hive: HiveRunOptions) {
        let checkpointPolicy: ColonyRun.CheckpointPolicy
        switch hive.checkpointPolicy {
        case .disabled:
            checkpointPolicy = .disabled
        case .everyStep:
            checkpointPolicy = .everyStep
        case .every(let steps):
            checkpointPolicy = .every(steps: steps)
        case .onInterrupt:
            checkpointPolicy = .onInterrupt
        }

        let streamingMode: ColonyRun.StreamingMode
        switch hive.streamingMode {
        case .events:
            streamingMode = .events
        case .values:
            streamingMode = .values
        case .updates:
            streamingMode = .updates
        case .combined:
            streamingMode = .combined
        }

        self.init(
            maxSteps: hive.maxSteps,
            maxConcurrentTasks: hive.maxConcurrentTasks,
            checkpointPolicy: checkpointPolicy,
            debugPayloads: hive.debugPayloads,
            deterministicTokenStreaming: hive.deterministicTokenStreaming,
            eventBufferCapacity: hive.eventBufferCapacity,
            streamingMode: streamingMode
        )
    }

    var hiveRunOptions: HiveRunOptions {
        let resolvedCheckpointPolicy: HiveCheckpointPolicy
        switch self.checkpointPolicy {
        case .disabled:
            resolvedCheckpointPolicy = .disabled
        case .everyStep:
            resolvedCheckpointPolicy = .everyStep
        case .every(let steps):
            resolvedCheckpointPolicy = .every(steps: steps)
        case .onInterrupt:
            resolvedCheckpointPolicy = .onInterrupt
        }

        let resolvedStreamingMode: HiveStreamingMode
        switch self.streamingMode {
        case .events:
            resolvedStreamingMode = .events
        case .values:
            resolvedStreamingMode = .values
        case .updates:
            resolvedStreamingMode = .updates
        case .combined:
            resolvedStreamingMode = .combined
        }

        return HiveRunOptions(
            maxSteps: maxSteps,
            maxConcurrentTasks: maxConcurrentTasks,
            checkpointPolicy: resolvedCheckpointPolicy,
            debugPayloads: debugPayloads,
            deterministicTokenStreaming: deterministicTokenStreaming,
            eventBufferCapacity: eventBufferCapacity,
            outputProjectionOverride: nil,
            streamingMode: resolvedStreamingMode
        )
    }
}

private extension ColonyRun.Event {
    init(_ hive: HiveEvent) {
        self.init(
            id: .init(
                runID: ColonyRunID(hiveRunID: hive.id.runID),
                attemptID: ColonyRunAttemptID(hiveAttemptID: hive.id.attemptID),
                eventIndex: hive.id.eventIndex,
                stepIndex: hive.id.stepIndex,
                taskOrdinal: hive.id.taskOrdinal
            ),
            kind: ColonyRun.EventKind(hive.kind),
            metadata: hive.metadata
        )
    }
}

private extension ColonyRun.SnapshotValue {
    init(_ hive: HiveSnapshotValue) {
        self.init(
            channelID: ColonyChannelID(hiveChannelID: hive.channelID),
            payloadHash: hive.payloadHash
        )
    }
}

private extension ColonyRun.ProjectedChannelValue {
    init(_ hive: HiveProjectedChannelValue) {
        self.init(
            channelID: ColonyChannelID(hiveChannelID: hive.id),
            value: hive.value
        )
    }
}

private extension ColonyRun.Output {
    init(_ hive: HiveRunOutput<ColonySchema>) {
        switch hive {
        case .fullStore(let store):
            self = .fullStore(.init(store))
        case .channels(let values):
            self = .channels(values.map(ColonyRun.ProjectedChannelValue.init))
        }
    }
}

private extension ColonyRun.CancellationCause {
    init(_ hive: HiveRunCancellationCause) {
        self = ColonyRun.CancellationCause(rawValue: hive.rawValue) ?? .executionObserved
    }
}

private extension ColonyRun.EventKind {
    init(_ hive: HiveEventKind) {
        switch hive {
        case .runStarted(let threadID):
            self = .runStarted(threadID: ColonyThreadID(hiveThreadID: threadID))
        case .runFinished:
            self = .runFinished
        case .runInterrupted(let interruptID):
            self = .runInterrupted(interruptID: ColonyInterruptID(hiveInterruptID: interruptID))
        case .runResumed(let interruptID):
            self = .runResumed(interruptID: ColonyInterruptID(hiveInterruptID: interruptID))
        case .runCancelled(let cause):
            self = .runCancelled(cause: .init(cause))
        case .stepStarted(let stepIndex, let frontierCount):
            self = .stepStarted(stepIndex: stepIndex, frontierCount: frontierCount)
        case .stepFinished(let stepIndex, let nextFrontierCount):
            self = .stepFinished(stepIndex: stepIndex, nextFrontierCount: nextFrontierCount)
        case .taskStarted(let node, let taskID):
            self = .taskStarted(nodeID: ColonyNodeID(hiveNodeID: node), taskID: taskID.rawValue)
        case .taskFinished(let node, let taskID):
            self = .taskFinished(nodeID: ColonyNodeID(hiveNodeID: node), taskID: taskID.rawValue)
        case .taskFailed(let node, let taskID, let errorDescription):
            self = .taskFailed(nodeID: ColonyNodeID(hiveNodeID: node), taskID: taskID.rawValue, errorDescription: errorDescription)
        case .writeApplied(let channelID, let payloadHash):
            self = .writeApplied(channelID: ColonyChannelID(hiveChannelID: channelID), payloadHash: payloadHash)
        case .checkpointSaved(let checkpointID):
            self = .checkpointSaved(checkpointID: ColonyCheckpointID(hiveCheckpointID: checkpointID))
        case .checkpointLoaded(let checkpointID):
            self = .checkpointLoaded(checkpointID: ColonyCheckpointID(hiveCheckpointID: checkpointID))
        case .storeSnapshot(let channelValues):
            self = .storeSnapshot(channelValues: channelValues.map(ColonyRun.SnapshotValue.init))
        case .channelUpdates(let channelValues):
            self = .channelUpdates(channelValues: channelValues.map(ColonyRun.SnapshotValue.init))
        case .modelInvocationStarted(let model):
            self = .modelInvocationStarted(model: model)
        case .modelToken(let text):
            self = .modelToken(text: text)
        case .modelInvocationFinished:
            self = .modelInvocationFinished
        case .toolInvocationStarted(let name):
            self = .toolInvocationStarted(name: name)
        case .toolInvocationFinished(let name, let success):
            self = .toolInvocationFinished(name: name, success: success)
        case .streamBackpressure(let droppedModelTokenEvents, let droppedDebugEvents):
            self = .streamBackpressure(droppedModelTokenEvents: droppedModelTokenEvents, droppedDebugEvents: droppedDebugEvents)
        case .customDebug(let name):
            self = .customDebug(name: name)
        case .forkStarted, .forkCompleted, .forkFailed:
            self = .customDebug(name: "fork")
        }
    }
}

private extension ColonyRun.Outcome {
    init(hiveHandle: HiveRunHandle<ColonySchema>) async throws {
        let hiveOutcome = try await hiveHandle.outcome.value
        switch hiveOutcome {
        case .finished(let output, let checkpointID):
            self = .finished(
                output: ColonyRun.Output(output),
                checkpointID: checkpointID.map(ColonyCheckpointID.init(hiveCheckpointID:))
            )
        case .interrupted(let interruption):
            self = .interrupted(.init(
                interruptID: ColonyInterruptID(hiveInterruptID: interruption.interrupt.id),
                payload: interruption.interrupt.payload,
                checkpointID: ColonyCheckpointID(hiveCheckpointID: interruption.checkpointID)
            ))
        case .cancelled(let output, let checkpointID):
            self = .cancelled(
                output: ColonyRun.Output(output),
                checkpointID: checkpointID.map(ColonyCheckpointID.init(hiveCheckpointID:))
            )
        case .outOfSteps(let maxSteps, let output, let checkpointID):
            self = .outOfSteps(
                maxSteps: maxSteps,
                output: ColonyRun.Output(output),
                checkpointID: checkpointID.map(ColonyCheckpointID.init(hiveCheckpointID:))
            )
        }
    }
}
