import ColonyCore
import Foundation

package actor ColonyRunEventEmitter {
    private let runID: ColonyRunID
    private let attemptID: ColonyRunAttemptID
    private let continuation: AsyncThrowingStream<ColonyRun.Event, Error>.Continuation
    private var nextEventIndex: UInt64 = 0
    private var isFinished = false

    package init(
        runID: ColonyRunID,
        attemptID: ColonyRunAttemptID,
        continuation: AsyncThrowingStream<ColonyRun.Event, Error>.Continuation
    ) {
        self.runID = runID
        self.attemptID = attemptID
        self.continuation = continuation
    }

    package func emit(
        _ kind: ColonyRun.EventKind,
        metadata: [String: String] = [:],
        stepIndex: Int? = nil,
        taskOrdinal: Int? = nil
    ) {
        guard isFinished == false else { return }
        let event = ColonyRun.Event(
            id: ColonyRun.EventID(
                runID: runID,
                attemptID: attemptID,
                eventIndex: nextEventIndex,
                stepIndex: stepIndex,
                taskOrdinal: taskOrdinal
            ),
            kind: kind,
            metadata: metadata
        )
        nextEventIndex += 1
        continuation.yield(event)
    }

    package func finish(throwing error: Error? = nil) {
        guard isFinished == false else { return }
        isFinished = true
        if let error {
            continuation.finish(throwing: error)
        } else {
            continuation.finish()
        }
    }
}

package actor ColonyRuntimeEngine {
    private let threadID: ColonyThreadID
    private let context: ColonyContext
    private let environment: SwarmExecutionEnvironment
    private let checkpointStore: any ColonyCheckpointStore

    private var latestSnapshot = ColonyStoreSnapshot()
    private var pendingInterruptID: ColonyInterruptID?

    package init(
        threadID: ColonyThreadID,
        context: ColonyContext,
        environment: SwarmExecutionEnvironment,
        checkpointStore: any ColonyCheckpointStore
    ) {
        self.threadID = threadID
        self.context = context
        self.environment = environment
        self.checkpointStore = checkpointStore
    }

    package func start(input: String, options: ColonyRun.Options) -> ColonyRun.Handle {
        let runID = ColonyRunID.generate()
        let attemptID = ColonyRunAttemptID.generate()
        let startingSnapshot = latestSnapshot
        return makeHandle(runID: runID, attemptID: attemptID) { emitter in
            try await self.execute(
                runID: runID,
                attemptID: attemptID,
                initialInput: input,
                resume: nil,
                startingSnapshot: startingSnapshot,
                startingStepIndex: 0,
                emitter: emitter,
                options: options
            )
        }
    }

    package func resume(
        interruptID: ColonyInterruptID,
        decision: ColonyToolApprovalDecision,
        options: ColonyRun.Options
    ) async -> ColonyRun.Handle {
        let attemptID = ColonyRunAttemptID.generate()
        do {
            let checkpoint = try await takeResumeCheckpoint(interruptID: interruptID)
            let runID = checkpoint.runID
            return makeHandle(runID: runID, attemptID: attemptID) { emitter in
                try await self.execute(
                    runID: runID,
                    attemptID: attemptID,
                    initialInput: nil,
                    resume: SwarmRunResume(
                        interruptID: SwarmInterruptID(interruptID.rawValue),
                        payload: .toolApproval(decision: decision)
                    ),
                    startingSnapshot: checkpoint.store,
                    startingStepIndex: checkpoint.stepIndex,
                    emitter: emitter,
                    options: options
                )
            }
        } catch let error as SwarmRuntimeError {
            let failureRunID = ColonyRunID.generate()
            return makeHandle(runID: failureRunID, attemptID: attemptID) { _ in
                throw error
            }
        } catch {
            let failureRunID = ColonyRunID.generate()
            return makeHandle(runID: failureRunID, attemptID: attemptID) { _ in
                throw SwarmRuntimeError.noInterruptToResume
            }
        }
    }

    private func takeResumeCheckpoint(interruptID: ColonyInterruptID) async throws -> ColonyCheckpointSnapshot {
        guard let currentPendingInterruptID = pendingInterruptID else {
            throw SwarmRuntimeError.noInterruptToResume
        }
        guard currentPendingInterruptID == interruptID else {
            throw SwarmRuntimeError.resumeInterruptMismatch(expected: currentPendingInterruptID, found: interruptID)
        }
        guard let checkpoint = try await checkpointStore.loadByInterruptID(threadID: threadID, interruptID: interruptID) else {
            throw SwarmRuntimeError.noInterruptToResume
        }
        pendingInterruptID = nil
        return checkpoint
    }

    private func execute(
        runID: ColonyRunID,
        attemptID: ColonyRunAttemptID,
        initialInput: String?,
        resume: SwarmRunResume<ColonyResumePayload>?,
        startingSnapshot: ColonyStoreSnapshot,
        startingStepIndex: Int,
        emitter: ColonyRunEventEmitter,
        options: ColonyRun.Options
    ) async throws -> ColonyRun.Outcome {
        var snapshot = startingSnapshot
        var stepIndex = startingStepIndex
        var resumePayload = resume

        await emitter.emit(.runStarted(threadID: threadID))
        if let resume {
            await emitter.emit(.runResumed(interruptID: ColonyInterruptID(resume.interruptID.rawValue)))
        }

        if let initialInput {
            let writes = try ColonyAgent.inputWrites(
                initialInput,
                inputContext: SwarmInputContext(
                    runID: SwarmRunID(UUID(uuidString: runID.rawValue) ?? UUID()),
                    stepIndex: stepIndex
                )
            )
            try apply(writes: writes, to: &snapshot, emitter: emitter)
        }

        while stepIndex < options.maxSteps {
            try Task.checkCancellation()
            await emitter.emit(.stepStarted(stepIndex: stepIndex, frontierCount: 1), stepIndex: stepIndex)

            let runContext = SwarmExecutionRun<ColonyResumePayload>(
                runID: SwarmRunID(UUID(uuidString: runID.rawValue) ?? UUID()),
                attemptID: attemptID,
                threadID: SwarmThreadID(threadID.rawValue),
                taskID: SwarmTaskID("run:\(runID.rawValue):step:\(stepIndex):main"),
                stepIndex: stepIndex,
                resume: resumePayload
            )

            let isResumingPendingToolDecision = resumePayload != nil && snapshot.pendingToolCalls.isEmpty == false

            if isResumingPendingToolDecision == false {
                let preModelOutput = try await ColonyAgent.preModel(
                    makeInput(snapshot: snapshot, run: runContext, emitter: emitter, stepIndex: stepIndex)
                )
                try apply(writes: preModelOutput.writes, to: &snapshot, emitter: emitter)

                let modelOutput = try await ColonyAgent.model(
                    makeInput(snapshot: snapshot, run: runContext, emitter: emitter, stepIndex: stepIndex)
                )
                try apply(writes: modelOutput.writes, to: &snapshot, emitter: emitter)

                if ColonyAgent.routeAfterModel(SwarmStoreView(snapshot: snapshot)) == .end {
                    let checkpointID = try await maybeCheckpoint(
                        snapshot: snapshot,
                        runID: runID,
                        attemptID: attemptID,
                        stepIndex: stepIndex,
                        options: options,
                        interrupted: false,
                        emitter: emitter
                    )
                    await emitter.emit(.runFinished)
                    await emitter.emit(.stepFinished(stepIndex: stepIndex, nextFrontierCount: 0), stepIndex: stepIndex)
                    await emitter.finish()
                    latestSnapshot = snapshot
                    return .finished(output: .fullStore(.init(snapshot)), checkpointID: checkpointID)
                }
            }

            let toolsOutput = try await ColonyAgent.tools(makeInput(snapshot: snapshot, run: runContext, emitter: emitter, stepIndex: stepIndex))
            try apply(writes: toolsOutput.writes, to: &snapshot, emitter: emitter)

            if let interrupt = toolsOutput.interrupt {
                let interruptID = ColonyInterruptID.generate(prefix: "interrupt")
                let checkpoint = ColonyCheckpointSnapshot(
                    threadID: threadID,
                    runID: runID,
                    attemptID: attemptID,
                    stepIndex: stepIndex,
                    interruptID: interruptID,
                    store: snapshot
                )
                try await checkpointStore.save(checkpoint)
                latestSnapshot = snapshot
                pendingInterruptID = interruptID
                await emitter.emit(.checkpointSaved(checkpointID: checkpoint.id), stepIndex: stepIndex)
                await emitter.emit(.runInterrupted(interruptID: interruptID), stepIndex: stepIndex)
                await emitter.emit(.stepFinished(stepIndex: stepIndex, nextFrontierCount: 0), stepIndex: stepIndex)
                await emitter.finish()
                return .interrupted(
                    ColonyRun.Interruption(
                        interruptID: interruptID,
                        payload: interrupt.payload,
                        checkpointID: checkpoint.id
                    )
                )
            }

            let taskResults = try await executeSpawnedTasks(
                toolsOutput.spawn,
                snapshot: snapshot,
                runContext: runContext,
                attemptID: attemptID,
                stepIndex: stepIndex,
                emitter: emitter,
                maxConcurrentTasks: options.maxConcurrentTasks
            )
            for taskResult in taskResults {
                try apply(writes: taskResult.writes, to: &snapshot, emitter: emitter)
                await emitter.emit(
                    .taskFinished(nodeID: ColonyNodeID("toolExecute"), taskID: taskResult.taskID.rawValue),
                    stepIndex: stepIndex,
                    taskOrdinal: taskResult.ordinal
                )
            }

            resumePayload = nil
            let checkpointID = try await maybeCheckpoint(
                snapshot: snapshot,
                runID: runID,
                attemptID: attemptID,
                stepIndex: stepIndex,
                options: options,
                interrupted: false,
                emitter: emitter
            )
            _ = checkpointID
            await emitter.emit(.stepFinished(stepIndex: stepIndex, nextFrontierCount: 1), stepIndex: stepIndex)
            stepIndex += 1
        }

        let checkpointID = try await maybeCheckpoint(
            snapshot: snapshot,
            runID: runID,
            attemptID: attemptID,
            stepIndex: stepIndex,
            options: options,
            interrupted: false,
            emitter: emitter
        )
        await emitter.finish()
        latestSnapshot = snapshot
        return .outOfSteps(
            maxSteps: options.maxSteps,
            output: .fullStore(.init(snapshot)),
            checkpointID: checkpointID
        )
    }

    private func makeInput(
        snapshot: ColonyStoreSnapshot,
        run: SwarmExecutionRun<ColonyResumePayload>,
        emitter: ColonyRunEventEmitter,
        stepIndex: Int
    ) -> SwarmGraphInput<ColonySchema> {
        SwarmGraphInput(
            store: SwarmStoreView(snapshot: snapshot),
            context: context,
            run: run,
            environment: environment,
            streamEmitter: { kind, metadata in
                Task { await emitter.emit(kind, metadata: metadata, stepIndex: stepIndex) }
            }
        )
    }

    private func executeSpawnedTasks(
        _ seeds: [SwarmTaskSeed<ColonySchema>],
        snapshot: ColonyStoreSnapshot,
        runContext: SwarmExecutionRun<ColonyResumePayload>,
        attemptID: ColonyRunAttemptID,
        stepIndex: Int,
        emitter: ColonyRunEventEmitter,
        maxConcurrentTasks: Int
    ) async throws -> [CompletedToolTask] {
        guard seeds.isEmpty == false else { return [] }

        let concurrencyLimit = max(1, maxConcurrentTasks)
        var scheduled = 0
        var nextOrdinal = 0
        var results: [CompletedToolTask] = []
        results.reserveCapacity(seeds.count)

        return try await withThrowingTaskGroup(of: CompletedToolTask.self) { group in
            while nextOrdinal < seeds.count && scheduled < concurrencyLimit {
                let ordinal = nextOrdinal
                let seed = seeds[ordinal]
                let taskID = SwarmTaskID("run:\(runContext.runID.rawValue.uuidString):step:\(stepIndex):tool:\(ordinal)")
                await emitter.emit(
                    .taskStarted(nodeID: ColonyNodeID("toolExecute"), taskID: taskID.rawValue),
                    stepIndex: stepIndex,
                    taskOrdinal: ordinal
                )

                group.addTask {
                    let taskRun = SwarmExecutionRun<ColonyResumePayload>(
                        runID: runContext.runID,
                        attemptID: attemptID,
                        threadID: SwarmThreadID(self.threadID.rawValue),
                        taskID: taskID,
                        stepIndex: stepIndex,
                        resume: nil
                    )

                    let taskOutput = try await ColonyAgent.toolExecute(
                        SwarmGraphInput(
                            store: SwarmStoreView(snapshot: snapshot, local: seed.local),
                            context: self.context,
                            run: taskRun,
                            environment: self.environment,
                            streamEmitter: { kind, metadata in
                                Task {
                                    await emitter.emit(
                                        kind,
                                        metadata: metadata,
                                        stepIndex: stepIndex,
                                        taskOrdinal: ordinal
                                    )
                                }
                            }
                        )
                    )

                    return CompletedToolTask(
                        ordinal: ordinal,
                        taskID: taskID,
                        writes: taskOutput.writes
                    )
                }
                nextOrdinal += 1
                scheduled += 1
            }

            while let completed = try await group.next() {
                results.append(completed)
                scheduled -= 1

                if nextOrdinal < seeds.count {
                    let ordinal = nextOrdinal
                    let seed = seeds[ordinal]
                    let taskID = SwarmTaskID("run:\(runContext.runID.rawValue.uuidString):step:\(stepIndex):tool:\(ordinal)")
                    await emitter.emit(
                        .taskStarted(nodeID: ColonyNodeID("toolExecute"), taskID: taskID.rawValue),
                        stepIndex: stepIndex,
                        taskOrdinal: ordinal
                    )

                    group.addTask {
                        let taskRun = SwarmExecutionRun<ColonyResumePayload>(
                            runID: runContext.runID,
                            attemptID: attemptID,
                            threadID: SwarmThreadID(self.threadID.rawValue),
                            taskID: taskID,
                            stepIndex: stepIndex,
                            resume: nil
                        )

                        let taskOutput = try await ColonyAgent.toolExecute(
                            SwarmGraphInput(
                                store: SwarmStoreView(snapshot: snapshot, local: seed.local),
                                context: self.context,
                                run: taskRun,
                                environment: self.environment,
                                streamEmitter: { kind, metadata in
                                    Task {
                                        await emitter.emit(
                                            kind,
                                            metadata: metadata,
                                            stepIndex: stepIndex,
                                            taskOrdinal: ordinal
                                        )
                                    }
                                }
                            )
                        )

                        return CompletedToolTask(
                            ordinal: ordinal,
                            taskID: taskID,
                            writes: taskOutput.writes
                        )
                    }
                    nextOrdinal += 1
                    scheduled += 1
                }
            }

            return results.sorted { $0.ordinal < $1.ordinal }
        }
    }

    private func apply(
        writes: [SwarmAnyWrite<ColonySchema>],
        to snapshot: inout ColonyStoreSnapshot,
        emitter: ColonyRunEventEmitter
    ) throws {
        for write in writes {
            switch write.channelID.rawValue {
            case ColonySchema.Channels.messages.id.rawValue:
                guard let messages = write.value() as? [SwarmChatMessage] else {
                    throw ColonyStoreError.typeMismatch(channelID: write.channelID)
                }
                snapshot.messages = try ColonyMessages.reduceMessages(left: snapshot.messages, right: messages)
            case ColonySchema.Channels.llmInputMessages.id.rawValue:
                snapshot.llmInputMessages = write.value() as? [SwarmChatMessage]
            case ColonySchema.Channels.pendingToolCalls.id.rawValue:
                guard let calls = write.value() as? [SwarmToolCall] else {
                    throw ColonyStoreError.typeMismatch(channelID: write.channelID)
                }
                snapshot.pendingToolCalls = calls
            case ColonySchema.Channels.finalAnswer.id.rawValue:
                snapshot.finalAnswer = write.value() as? String
            case ColonySchema.Channels.todos.id.rawValue:
                guard let todos = write.value() as? [ColonyTodo] else {
                    throw ColonyStoreError.typeMismatch(channelID: write.channelID)
                }
                snapshot.todos = todos
            case ColonySchema.Channels.currentToolCall.id.rawValue:
                guard let toolCall = write.value() as? SwarmToolCall else {
                    throw ColonyStoreError.typeMismatch(channelID: write.channelID)
                }
                snapshot.currentToolCall = toolCall
            default:
                throw ColonyStoreError.missingChannel(write.channelID)
            }

            Task {
                await emitter.emit(
                    .writeApplied(channelID: write.channelID, payloadHash: payloadHash(for: write.value()))
                )
            }
        }
    }

    private func maybeCheckpoint(
        snapshot: ColonyStoreSnapshot,
        runID: ColonyRunID,
        attemptID: ColonyRunAttemptID,
        stepIndex: Int,
        options: ColonyRun.Options,
        interrupted: Bool,
        emitter: ColonyRunEventEmitter
    ) async throws -> ColonyCheckpointID? {
        let shouldSave: Bool
        switch options.checkpointPolicy {
        case .disabled:
            shouldSave = interrupted
        case .everyStep:
            shouldSave = true
        case .every(let steps):
            shouldSave = steps > 0 && stepIndex % steps == 0
        case .onInterrupt:
            shouldSave = interrupted
        }

        guard shouldSave else {
            return nil
        }

        let checkpoint = ColonyCheckpointSnapshot(
            threadID: threadID,
            runID: runID,
            attemptID: attemptID,
            stepIndex: stepIndex,
            store: snapshot
        )
        try await checkpointStore.save(checkpoint)
        await emitter.emit(.checkpointSaved(checkpointID: checkpoint.id), stepIndex: stepIndex)
        return checkpoint.id
    }

    private func payloadHash(for value: Any) -> String {
        if let encodable = value as? any Encodable,
           let data = try? JSONEncoder().encode(AnyEncodable(encodable))
        {
            return String(data.hashValue)
        }
        return String(String(describing: value).hashValue)
    }

    private func makeHandle(
        runID: ColonyRunID,
        attemptID: ColonyRunAttemptID,
        operation: @escaping @Sendable (ColonyRunEventEmitter) async throws -> ColonyRun.Outcome
    ) -> ColonyRun.Handle {
        var continuationStorage: AsyncThrowingStream<ColonyRun.Event, Error>.Continuation!
        let events = AsyncThrowingStream<ColonyRun.Event, Error> { continuation in
            continuationStorage = continuation
        }

        let outcome = Task {
            let emitter = ColonyRunEventEmitter(
                runID: runID,
                attemptID: attemptID,
                continuation: continuationStorage
            )
            do {
                let result = try await operation(emitter)
                await emitter.finish()
                return result
            } catch {
                await emitter.finish(throwing: error)
                throw error
            }
        }

        return ColonyRun.Handle(
            runID: runID,
            attemptID: attemptID,
            events: events,
            outcome: outcome
        )
    }
}

private struct CompletedToolTask: Sendable {
    let ordinal: Int
    let taskID: SwarmTaskID
    let writes: [SwarmAnyWrite<ColonySchema>]
}

private struct AnyEncodable: Encodable {
    private let encodeImpl: (Encoder) throws -> Void

    init(_ value: some Encodable) {
        encodeImpl = value.encode(to:)
    }

    func encode(to encoder: Encoder) throws {
        try encodeImpl(encoder)
    }
}
