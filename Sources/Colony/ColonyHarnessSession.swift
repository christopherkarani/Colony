import Foundation
@_spi(ColonyInternal) import Swarm
import ColonyCore

/// Errors that can occur during harness session operations.
public enum HarnessError: Error, Sendable {
    /// A run is already active and a new one cannot be started.
    case runAlreadyActive
    /// No interrupted run to resume.
    case noInterruptedRun
    /// Failed to persist run state.
    case runStatePersistenceFailed(String)
}

@available(*, deprecated, renamed: "HarnessError")
public typealias ColonyHarnessSessionError = HarnessError

/// A harness session for controlling Colony runs from external clients.
///
/// `ColonyHarnessSession` provides a high-level API for starting, stopping,
/// and resuming Colony runs. It handles event streaming, state persistence,
/// and observability emission.
public actor ColonyHarnessSession {
    /// The unique identifier for this session.
    public let sessionID: ColonyHarnessSessionID

    /// The current lifecycle state of the session.
    public var lifecycleState: ColonyHarnessLifecycleState {
        lifecycleStateStorage
    }

    /// Creates a new harness session with the given runtime.
    ///
    /// - Parameters:
    ///   - runtime: The Colony runtime to control.
    ///   - sessionID: Optional session ID. Generated if nil.
    ///   - runStateStore: Optional store for run state persistence.
    ///   - observabilityEmitter: Optional emitter for observability events.
    /// - Returns: A new harness session.
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

    /// Returns a stream of harness events.
    ///
    /// Multiple subscribers can receive events from the same session.
    ///
    /// - Returns: An async stream of event envelopes.
    public func stream() -> AsyncThrowingStream<ColonyHarnessEventEnvelope, Error> {
        let subscriberID = UUID()
        var subscriberContinuation: AsyncThrowingStream<ColonyHarnessEventEnvelope, Error>.Continuation?
        let stream = AsyncThrowingStream<ColonyHarnessEventEnvelope, Error> { continuation in
            subscriberContinuation = continuation
        }
        if let continuation = subscriberContinuation {
            subscribers[subscriberID] = continuation
            continuation.onTermination = { _ in
                Task { await self.removeSubscriber(id: subscriberID) }
            }
        }
        return stream
    }

    /// Starts a new run with the given input.
    ///
    /// - Parameter input: The user message to start the run with.
    /// - Throws: `HarnessError.runAlreadyActive` if a run is already in progress.
    public func start(input: String) async throws {
        guard activeAttemptID == nil else {
            throw HarnessError.runAlreadyActive
        }

        interruptionQueue.removeAll(keepingCapacity: false)
        stopRequested = false
        lifecycleStateStorage = .running

        let handle = await runtime.sendUserMessage(input)
        let runID = handle.runID

        await emit(
            runID: runID,
            eventType: .runStarted,
            payload: .none
        )

        beginAttemptMonitoring(handle: handle, runID: runID)
    }

    /// Returns the first pending interruption if any.
    ///
    /// - Returns: The first interruption, or nil if the queue is empty.
    public func interrupted() -> ColonyHarnessInterruption? {
        interruptionQueue.first
    }

    /// Returns all pending interruptions.
    ///
    /// - Returns: Array of pending interruptions.
    public func pendingInterruptions() -> [ColonyHarnessInterruption] {
        interruptionQueue
    }

    /// Resumes from an interruption with the given decision.
    ///
    /// - Parameter decision: The tool approval decision.
    /// - Throws: If no interrupted run exists or a run is already active.
    public func resume(decision: ColonyToolApprovalDecision) async throws {
        guard activeAttemptID == nil else {
            throw HarnessError.runAlreadyActive
        }
        guard interruptionQueue.isEmpty == false else {
            throw HarnessError.noInterruptedRun
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
        let runID = handle.runID

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

    /// Stops the current run and clears the session state.
    public func stop() async {
        stopRequested = true
        lifecycleStateStorage = .stopped
        interruptionQueue.removeAll(keepingCapacity: false)
        let cancelledRunID = activeRunID
        activeOutcomeTask?.cancel()
        eventPumpTask?.cancel()
        outcomeMonitorTask?.cancel()
        activeAttemptID = nil
        activeRunID = nil
        activeOutcomeTask = nil
        eventPumpTask = nil
        outcomeMonitorTask = nil

        if let cancelledRunID {
            await emit(runID: cancelledRunID, eventType: .runCancelled, payload: .none)
        }
    }

    private let runtime: ColonyRuntime
    private let runStateStore: ColonyDurableRunStateStore?
    private let observabilityEmitter: ColonyObservabilityEmitter?

    private var lifecycleStateStorage: ColonyHarnessLifecycleState = .idle
    private var interruptionQueue: [ColonyHarnessInterruption] = []
    private var stopRequested: Bool = false

    private var activeAttemptID: ColonyRunAttemptID?
    private var activeRunID: ColonyRunID?
    private var activeOutcomeTask: Task<ColonyRun.Outcome, Error>?
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

    private func beginAttemptMonitoring(handle: ColonyRun.Handle, runID: ColonyRunID) {
        activeAttemptID = handle.attemptID
        activeRunID = runID
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
                self.lifecycleStateStorage = self.stopRequested ? .stopped : .idle
            }
        }
    }

    private func processRuntimeEvent(_ event: ColonyRun.Event, runID: ColonyRunID) async {
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

    private func processOutcome(_ outcome: ColonyRun.Outcome, runID: ColonyRunID) async {
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
            switch interruption.payload {
            case .toolApprovalRequired(let toolCalls):
                let queuedInterruption = ColonyHarnessInterruption(
                    runID: runID,
                    interruptID: interruption.interruptID,
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

    private func emit(runID: ColonyRunID, eventType: ColonyHarnessEventType, payload: ColonyHarnessEventPayload) async {
        sequenceCounter += 1
        let envelope = ColonyHarnessEventEnvelope(
            protocolVersion: .v1,
            eventType: eventType,
            sequence: sequenceCounter,
            timestamp: Date(),
            runID: runID.hiveRunID.rawValue,
            sessionID: sessionID,
            payload: payload
        )

        for continuation in subscribers.values {
            continuation.yield(envelope)
        }

        if let runStateStore {
            do {
                try await runStateStore.appendEvent(envelope, threadID: runtime.threadID)
            } catch {
                let rendered = String(reflecting: error)
                let persistenceError = HarnessError.runStatePersistenceFailed(rendered)
                for continuation in subscribers.values {
                    continuation.finish(throwing: persistenceError)
                }
                subscribers.removeAll()
                stopRequested = true
                lifecycleStateStorage = .stopped
                activeOutcomeTask?.cancel()
                eventPumpTask?.cancel()
                outcomeMonitorTask?.cancel()
                activeAttemptID = nil
                activeRunID = nil
                activeOutcomeTask = nil
                eventPumpTask = nil
                outcomeMonitorTask = nil
                return
            }
        }

        if let observabilityEmitter {
            await observabilityEmitter.emitHarnessEnvelope(envelope, threadID: runtime.threadID)
        }
    }

    private func completeAttempt(attemptID: ColonyRunAttemptID) async {
        guard activeAttemptID == attemptID else {
            return
        }

        activeAttemptID = nil
        activeRunID = nil
        activeOutcomeTask = nil
        eventPumpTask?.cancel()
        outcomeMonitorTask?.cancel()
        eventPumpTask = nil
        outcomeMonitorTask = nil
    }

    private func removeSubscriber(id: UUID) async {
        subscribers.removeValue(forKey: id)
    }
}
