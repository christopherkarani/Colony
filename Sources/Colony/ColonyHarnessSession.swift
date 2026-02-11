import Foundation
import HiveCore
import ColonyCore

public enum ColonyHarnessSessionError: Error, Sendable {
    case runAlreadyActive
    case noInterruptedRun
}

public actor ColonyHarnessSession {
    public let sessionID: ColonyHarnessSessionID

    public var lifecycleState: ColonyHarnessLifecycleState {
        lifecycleStateStorage
    }

    public static func create(
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

    public func stream() -> AsyncThrowingStream<ColonyHarnessEventEnvelope, Error> {
        let subscriberID = UUID()
        return AsyncThrowingStream { continuation in
            Task { await self.addSubscriber(id: subscriberID, continuation: continuation) }
            continuation.onTermination = { _ in
                Task { await self.removeSubscriber(id: subscriberID) }
            }
        }
    }

    public func start(input: String) async throws {
        guard activeAttemptID == nil else {
            throw ColonyHarnessSessionError.runAlreadyActive
        }

        interruptionQueue.removeAll(keepingCapacity: false)
        stopRequested = false
        lifecycleStateStorage = .running

        let handle = await runtime.sendUserMessage(input)
        let runID = handle.runID.rawValue

        await emit(
            runID: runID,
            eventType: .runStarted,
            payload: .none
        )

        beginAttemptMonitoring(handle: handle, runID: runID)
    }

    public func interrupted() -> ColonyHarnessInterruption? {
        interruptionQueue.first
    }

    public func pendingInterruptions() -> [ColonyHarnessInterruption] {
        interruptionQueue
    }

    public func resume(decision: ColonyToolApprovalDecision) async throws {
        guard activeAttemptID == nil else {
            throw ColonyHarnessSessionError.runAlreadyActive
        }
        guard interruptionQueue.isEmpty == false else {
            throw ColonyHarnessSessionError.noInterruptedRun
        }
        let interruptedState = interruptionQueue.removeFirst()

        stopRequested = false
        lifecycleStateStorage = .running

        if decision == .rejected {
            for call in interruptedState.toolCalls {
                await emit(
                    runID: interruptedState.runID,
                    eventType: .toolDenied,
                    payload: .toolDenied(
                        ColonyHarnessToolDeniedPayload(
                            toolCallID: call.id,
                            toolName: call.name,
                            reason: "rejected"
                        )
                    )
                )
            }
        }

        let handle = await runtime.resumeToolApproval(
            interruptID: interruptedState.interruptID,
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

    public func stop() {
        stopRequested = true
        lifecycleStateStorage = .stopped
        interruptionQueue.removeAll(keepingCapacity: false)
        activeOutcomeTask?.cancel()
    }

    private let runtime: ColonyRuntime
    private let runStateStore: ColonyDurableRunStateStore?
    private let observabilityEmitter: ColonyObservabilityEmitter?

    private var lifecycleStateStorage: ColonyHarnessLifecycleState = .idle
    private var interruptionQueue: [ColonyHarnessInterruption] = []
    private var stopRequested: Bool = false

    private var activeAttemptID: HiveRunAttemptID?
    private var activeOutcomeTask: Task<HiveRunOutcome<ColonySchema>, Error>?
    private var eventPumpTask: Task<Void, Never>?
    private var outcomeMonitorTask: Task<Void, Never>?

    private var sequenceCounter: Int = 0
    private var subscribers: [UUID: AsyncThrowingStream<ColonyHarnessEventEnvelope, Error>.Continuation] = [:]

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
                payload: .assistantDelta(ColonyHarnessAssistantDeltaPayload(delta: text))
            )

        case .toolInvocationFinished(let name, let success):
            guard let toolCallID = event.metadata["toolCallID"], toolCallID.isEmpty == false else {
                return
            }

            await emit(
                runID: runID,
                eventType: .toolResult,
                payload: .toolResult(
                    ColonyHarnessToolResultPayload(
                        toolCallID: toolCallID,
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
                let queuedInterruption = ColonyHarnessInterruption(
                    runID: runID,
                    interruptID: interruption.interrupt.id,
                    toolCalls: toolCalls
                )
                interruptionQueue.append(queuedInterruption)
                lifecycleStateStorage = .interrupted
                for toolCall in toolCalls {
                    await emit(
                        runID: runID,
                        eventType: .toolRequest,
                        payload: .toolRequest(
                            ColonyHarnessToolRequestPayload(
                                toolCallID: toolCall.id,
                                toolName: toolCall.name,
                                argumentsJSON: toolCall.argumentsJSON
                            )
                        )
                    )
                }
                await emit(runID: runID, eventType: .runInterrupted, payload: .none)
            }
        }
    }

    private func emit(runID: UUID, eventType: ColonyHarnessEventType, payload: ColonyHarnessEventPayload) async {
        sequenceCounter += 1
        let envelope = ColonyHarnessEventEnvelope(
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
            try? await runStateStore.appendEvent(envelope, threadID: runtime.threadID)
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
        continuation: AsyncThrowingStream<ColonyHarnessEventEnvelope, Error>.Continuation
    ) async {
        subscribers[id] = continuation
    }

    private func removeSubscriber(id: UUID) async {
        subscribers.removeValue(forKey: id)
    }
}
