import Foundation
import HiveCore
import ColonyCore

package enum ColonyHarnessSessionError: Error, Sendable {
    case runAlreadyActive
    case noInterruptedRun
}

package actor ColonyHarnessSession {
    package let sessionID: ColonyHarnessSessionID

    package var lifecycleState: ColonyHarness.LifecycleState {
        lifecycleStateStorage
    }

    package static func create(
        runtime: ColonyRuntime,
        sessionID: ColonyHarnessSessionID = ColonyHarnessSessionID(rawValue: "session:" + UUID().uuidString.lowercased()),
        runStateStore: ColonyDurableRunStateStore? = nil,
        observabilityEmitter: ColonyObservabilityEmitter? = nil
    ) -> ColonyHarnessSession {
        ColonyHarnessSession(
            runtime: runtime,
            sessionID: sessionID,
            runStateStore: runStateStore,
            observabilityEmitter: observabilityEmitter
        )
    }

    package func stream() -> AsyncThrowingStream<ColonyHarness.EventEnvelope, Error> {
        let subscriberID = UUID()
        return AsyncThrowingStream { continuation in
            Task { await self.addSubscriber(id: subscriberID, continuation: continuation) }
            continuation.onTermination = { _ in
                Task { await self.removeSubscriber(id: subscriberID) }
            }
        }
    }

    package func start(input: String) async throws {
        guard activeAttemptID == nil else {
            throw ColonyHarnessSessionError.runAlreadyActive
        }

        interruptionQueue.removeAll(keepingCapacity: false)
        stopRequested = false
        lifecycleStateStorage = .running

        let handle = await runtime.sendUserMessageRaw(input)
        let runID = handle.runID.rawValue

        await emit(
            runID: runID,
            eventType: .runStarted,
            payload: .none
        )

        beginAttemptMonitoring(handle: handle, runID: runID)
    }

    package func interrupted() -> ColonyHarness.Interruption? {
        interruptionQueue.first
    }

    package func pendingInterruptions() -> [ColonyHarness.Interruption] {
        interruptionQueue
    }

    package func resume(decision: ColonyToolApproval.Decision) async throws {
        guard activeAttemptID == nil else {
            throw ColonyHarnessSessionError.runAlreadyActive
        }
        guard interruptionQueue.isEmpty == false else {
            throw ColonyHarnessSessionError.noInterruptedRun
        }
        let interruptedState = interruptionQueue.removeFirst()

        stopRequested = false
        lifecycleStateStorage = .running

        if decision == .rejected || decision == .cancelled {
            for call in interruptedState.toolCalls {
                await emit(
                    runID: interruptedState.runID,
                    eventType: .toolDenied,
                    payload: .toolDenied(
                        ColonyHarness.ToolDeniedPayload(
                            toolCallID: call.id,
                            toolName: call.name.rawValue,
                            reason: decision == .cancelled ? "cancelled" : "rejected"
                        )
                    )
                )
            }
        }

        let handle = await runtime.resumeToolApprovalRaw(
            interruptID: interruptedState.interruptID.hive,
            decision: decision
        )
        let runID = handle.runID.rawValue

        await emit(
            runID: runID,
            eventType: .runStarted,
            payload: .none
        )
        await emit(
            runID: runID,
            eventType: .runResumed,
            payload: .none
        )

        beginAttemptMonitoring(handle: handle, runID: runID)
    }

    package func stop() {
        stopRequested = true
        lifecycleStateStorage = .stopped
        interruptionQueue.removeAll(keepingCapacity: false)
        activeOutcomeTask?.cancel()
    }

    private let runtime: ColonyRuntime
    private let runStateStore: ColonyDurableRunStateStore?
    private let observabilityEmitter: ColonyObservabilityEmitter?

    private var lifecycleStateStorage: ColonyHarness.LifecycleState = .idle
    private var interruptionQueue: [ColonyHarness.Interruption] = []
    private var stopRequested: Bool = false

    private var activeAttemptID: HiveRunAttemptID?
    private var activeOutcomeTask: Task<HiveRunOutcome<ColonySchema>, Error>?
    private var eventPumpTask: Task<Void, Never>?
    private var outcomeMonitorTask: Task<Void, Never>?

    private var sequenceCounter: Int = 0
    private var subscribers: [UUID: AsyncThrowingStream<ColonyHarness.EventEnvelope, Error>.Continuation] = [:]

    private init(
        runtime: ColonyRuntime,
        sessionID: ColonyHarnessSessionID,
        runStateStore: ColonyDurableRunStateStore?,
        observabilityEmitter: ColonyObservabilityEmitter?
    ) {
        self.runtime = runtime
        self.sessionID = sessionID
        self.runStateStore = runStateStore
        self.observabilityEmitter = observabilityEmitter
    }

    private func beginAttemptMonitoring(handle: HiveRunHandle<ColonySchema>, runID: UUID) {
        activeAttemptID = handle.attemptID
        activeOutcomeTask = handle.outcome

        eventPumpTask?.cancel()
        outcomeMonitorTask?.cancel()

        let attemptID = handle.attemptID
        let events = handle.events

        eventPumpTask = Task {
            do {
                for try await event in events {
                    await self.processRuntimeEvent(event, runID: runID)
                }
            } catch {
                await self.completeAttempt(attemptID: attemptID)
            }
        }

        outcomeMonitorTask = Task {
            defer {
                Task { await self.completeAttempt(attemptID: attemptID) }
            }

            do {
                let outcome = try await handle.outcome.value
                await self.processOutcome(outcome, runID: runID)
            } catch {
                if self.stopRequested {
                    await self.emit(runID: runID, eventType: .runCancelled, payload: .none)
                }
                self.lifecycleStateStorage = self.stopRequested ? .stopped : .idle
            }
        }
    }

    private func processRuntimeEvent(_ event: HiveEvent, runID: UUID) async {
        switch event.kind {
        case .modelToken(let text):
            await emit(
                runID: runID,
                eventType: .assistantDelta,
                payload: .assistantDelta(ColonyHarness.AssistantDeltaPayload(delta: text))
            )

        case .toolInvocationFinished(let name, let success):
            guard let toolCallIDString = event.metadata["toolCallID"], toolCallIDString.isEmpty == false else {
                return
            }

            await emit(
                runID: runID,
                eventType: .toolResult,
                payload: .toolResult(
                    ColonyHarness.ToolResultPayload(
                        toolCallID: ColonyToolCallID(toolCallIDString),
                        toolName: name,
                        success: success
                    )
                )
            )

        default:
            break
        }
    }

    private func processOutcome(_ outcome: HiveRunOutcome<ColonySchema>, runID: UUID) async {
        switch outcome {
        case .finished:
            lifecycleStateStorage = stopRequested ? .stopped : .idle
            await emit(runID: runID, eventType: .runFinished, payload: .none)

        case .outOfSteps:
            lifecycleStateStorage = stopRequested ? .stopped : .idle
            await emit(runID: runID, eventType: .runFinished, payload: .none)

        case .cancelled:
            lifecycleStateStorage = .stopped
            await emit(runID: runID, eventType: .runCancelled, payload: .none)

        case .interrupted(let interruption):
            switch interruption.interrupt.payload {
            case .toolApprovalRequired(let toolCalls):
                let queuedInterruption = ColonyHarness.Interruption(
                    runID: runID,
                    interruptID: ColonyInterruptID(interruption.interrupt.id),
                    toolCalls: toolCalls
                )
                interruptionQueue.append(queuedInterruption)
                lifecycleStateStorage = .interrupted
                for toolCall in toolCalls {
                    await emit(
                        runID: runID,
                        eventType: .toolRequest,
                        payload: .toolRequest(
                            ColonyHarness.ToolRequestPayload(
                                toolCallID: toolCall.id,
                                toolName: toolCall.name.rawValue,
                                argumentsJSON: toolCall.argumentsJSON
                            )
                        )
                    )
                }
                await emit(runID: runID, eventType: .runInterrupted, payload: .none)
            }
        }
    }

    private func emit(runID: UUID, eventType: ColonyHarness.EventType, payload: ColonyHarness.EventPayload) async {
        sequenceCounter += 1
        let envelope = ColonyHarness.EventEnvelope(
            protocolVersion: .v1,
            eventType: eventType,
            sequence: sequenceCounter,
            timestamp: Date(),
            runID: runID,
            sessionID: sessionID,
            payload: payload
        )

        for continuation in subscribers.values {
            continuation.yield(envelope)
        }

        if let runStateStore {
            try? await runStateStore.appendEvent(envelope, threadID: runtime.threadID.hive)
        }

        if let observabilityEmitter {
            await observabilityEmitter.emitHarnessEnvelope(envelope, threadID: runtime.threadID)
        }
    }

    private func completeAttempt(attemptID: HiveRunAttemptID) async {
        guard activeAttemptID == attemptID else {
            return
        }

        activeAttemptID = nil
        activeOutcomeTask = nil
        eventPumpTask?.cancel()
        outcomeMonitorTask?.cancel()
        eventPumpTask = nil
        outcomeMonitorTask = nil
    }

    private func addSubscriber(
        id: UUID,
        continuation: AsyncThrowingStream<ColonyHarness.EventEnvelope, Error>.Continuation
    ) async {
        subscribers[id] = continuation
    }

    private func removeSubscriber(id: UUID) async {
        subscribers.removeValue(forKey: id)
    }
}
