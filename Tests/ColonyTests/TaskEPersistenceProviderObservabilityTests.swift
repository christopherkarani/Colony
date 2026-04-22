import Foundation
import Dispatch
import Testing
@_spi(ColonyInternal) import Swarm
@testable import Colony

private enum TaskETestError: Error {
    case scriptedFailure(String)
}

private actor RequestCounter {
    private var count: Int = 0

    func increment() {
        count += 1
    }

    func value() -> Int {
        count
    }
}

private final class AlwaysFailModelClient: SwarmModelClient, @unchecked Sendable {
    private let counter = RequestCounter()
    private let message: String

    init(message: String) {
        self.message = message
    }

    func complete(_ request: SwarmChatRequest) async throws -> SwarmChatResponse {
        await counter.increment()
        throw TaskETestError.scriptedFailure(message)
    }

    func snapshotRequestCount() async -> Int {
        await counter.value()
    }

    func stream(_ request: SwarmChatRequest) -> AsyncThrowingStream<SwarmChatStreamChunk, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    _ = try await complete(request)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}

private final class FixedModelClient: SwarmModelClient, @unchecked Sendable {
    private let counter = RequestCounter()
    private let content: String
    private let token: String?

    init(content: String, token: String? = nil) {
        self.content = content
        self.token = token
    }

    func complete(_ request: SwarmChatRequest) async throws -> SwarmChatResponse {
        await counter.increment()
        return SwarmChatResponse(message: SwarmChatMessage(id: UUID().uuidString, role: .assistant, content: content))
    }

    func snapshotRequestCount() async -> Int {
        await counter.value()
    }

    func stream(_ request: SwarmChatRequest) -> AsyncThrowingStream<SwarmChatStreamChunk, Error> {
        return AsyncThrowingStream { continuation in
            Task {
                await self.counter.increment()
                if let token {
                    continuation.yield(.token(token))
                }
                continuation.yield(.final(SwarmChatResponse(message: SwarmChatMessage(id: UUID().uuidString, role: .assistant, content: self.content))))
                continuation.finish()
            }
        }
    }
}

private final class DelayedFixedModelClient: SwarmModelClient, @unchecked Sendable {
    private let counter = RequestCounter()
    private let content: String
    private let delayNanoseconds: UInt64

    init(content: String, delayNanoseconds: UInt64) {
        self.content = content
        self.delayNanoseconds = delayNanoseconds
    }

    func complete(_ request: SwarmChatRequest) async throws -> SwarmChatResponse {
        await counter.increment()
        try await Task.sleep(nanoseconds: delayNanoseconds)
        return SwarmChatResponse(message: SwarmChatMessage(id: UUID().uuidString, role: .assistant, content: content))
    }

    func snapshotRequestCount() async -> Int {
        await counter.value()
    }

    func stream(_ request: SwarmChatRequest) -> AsyncThrowingStream<SwarmChatStreamChunk, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let response = try await self.complete(request)
                    continuation.yield(.final(response))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}

private final class CancellationModelClient: SwarmModelClient, @unchecked Sendable {
    private let counter = RequestCounter()

    func complete(_ request: SwarmChatRequest) async throws -> SwarmChatResponse {
        await counter.increment()
        throw CancellationError()
    }

    func snapshotRequestCount() async -> Int {
        await counter.value()
    }

    func stream(_ request: SwarmChatRequest) -> AsyncThrowingStream<SwarmChatStreamChunk, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish(throwing: CancellationError())
        }
    }
}

private struct TestColonyModelClientBridge: ColonyModelClient, Sendable {
    let client: SwarmAnyModelClient

    init(_ client: some SwarmModelClient) {
        self.client = SwarmAnyModelClient(client)
    }

    func generate(_ request: ColonyInferenceRequest) async throws -> ColonyInferenceResponse {
        ColonyInferenceResponse(try await client.complete(request.hiveChatRequest))
    }

    func stream(_ request: ColonyInferenceRequest) -> AsyncThrowingStream<ColonyInferenceStreamChunk, Error> {
        let stream = client.stream(request.hiveChatRequest)
        return AsyncThrowingStream { continuation in
            Task {
                do {
                    for try await chunk in stream {
                        switch chunk {
                        case .token(let text):
                            continuation.yield(.token(text))
                        case .final(let response):
                            continuation.yield(.final(ColonyInferenceResponse(response)))
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}

private final class InterruptingOnceModelClient: SwarmModelClient, @unchecked Sendable {
    func complete(_ request: SwarmChatRequest) async throws -> SwarmChatResponse {
        try await streamFinal(request)
    }

    func stream(_ request: SwarmChatRequest) -> AsyncThrowingStream<SwarmChatStreamChunk, Error> {
        AsyncThrowingStream { continuation in
            let call = SwarmToolCall(
                id: "approval-1",
                name: "write_file",
                argumentsJSON: #"{"path":"/checkpoint.md","content":"checkpoint"}"#
            )
            continuation.yield(
                .final(
                    SwarmChatResponse(
                        message: SwarmChatMessage(
                            id: "assistant-approval",
                            role: .assistant,
                            content: "needs approval",
                            toolCalls: [call]
                        )
                    )
                )
            )
            continuation.finish()
        }
    }
}

private final class InterruptThenFinishModelClient: SwarmModelClient, @unchecked Sendable {
    private let lock = NSLock()
    private var invocations = 0

    func complete(_ request: SwarmChatRequest) async throws -> SwarmChatResponse {
        nextResponse()
    }

    func stream(_ request: SwarmChatRequest) -> AsyncThrowingStream<SwarmChatStreamChunk, Error> {
        let response = nextResponse()
        return AsyncThrowingStream { continuation in
            continuation.yield(.final(response))
            continuation.finish()
        }
    }

    private func nextResponse() -> SwarmChatResponse {
        lock.lock()
        invocations += 1
        let invocation = invocations
        lock.unlock()

        if invocation == 1 {
            let call = SwarmToolCall(
                id: "approval-1",
                name: "write_file",
                argumentsJSON: #"{"path":"/checkpoint.md","content":"checkpoint"}"#
            )
            return SwarmChatResponse(
                message: SwarmChatMessage(
                    id: "assistant-interrupt",
                    role: .assistant,
                    content: "needs approval",
                    toolCalls: [call]
                )
            )
        }

        return SwarmChatResponse(
            message: SwarmChatMessage(
                id: "assistant-finished-\(invocation)",
                role: .assistant,
                content: "done"
            )
        )
    }
}

private func temporaryDirectory(_ suffix: String) throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("colony-task-e-tests", isDirectory: true)
        .appendingPathComponent(suffix + "-" + UUID().uuidString.lowercased(), isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private func makeCheckpoint(stepIndex: Int, threadID: SwarmThreadID, runID: SwarmRunID, id: String) -> ColonyCheckpointSnapshot {
    ColonyCheckpointSnapshot(
        id: SwarmCheckpointID(id),
        threadID: threadID,
        runID: runID,
        stepIndex: stepIndex,
        schemaVersion: "colony-v1",
        graphVersion: "graph-v1",
        globalDataByChannelID: [:],
        frontier: [],
        joinBarrierSeenByJoinID: [:],
        interruption: nil
    )
}

private func makeEnvelope(
    runID: UUID,
    sessionID: ColonyHarnessSessionID,
    sequence: Int,
    eventType: ColonyHarnessEventType,
    payload: ColonyHarnessEventPayload = .none,
    timestamp: Date
) -> ColonyHarnessEventEnvelope {
    ColonyHarnessEventEnvelope(
        protocolVersion: .v1,
        eventType: eventType,
        sequence: sequence,
        timestamp: timestamp,
        runID: runID,
        sessionID: sessionID,
        payload: payload
    )
}

private func waitUntil(
    timeoutNanoseconds: UInt64 = 2_000_000_000,
    pollNanoseconds: UInt64 = 10_000_000,
    _ condition: @escaping @Sendable () async -> Bool
) async -> Bool {
    let start = DispatchTime.now().uptimeNanoseconds
    while DispatchTime.now().uptimeNanoseconds - start < timeoutNanoseconds {
        if await condition() {
            return true
        }

        try? await Task.sleep(nanoseconds: pollNanoseconds)
    }

    return await condition()
}

@Test("Task E durable checkpoint store persists and supports query")
func taskE_durableCheckpointStorePersistsAndQueries() async throws {
    let directory = try temporaryDirectory("checkpoints")
    defer { try? FileManager.default.removeItem(at: directory) }

    let threadID = SwarmThreadID("thread-task-e-checkpoint")
    let runID = SwarmRunID(UUID(uuidString: "D39A7E4F-3355-43AF-AC72-3097F7706E57")!)

    let store = try ColonyDurableCheckpointStore(baseURL: directory)
    try await store.save(makeCheckpoint(stepIndex: 1, threadID: threadID, runID: runID, id: "cp-1"))
    try await store.save(makeCheckpoint(stepIndex: 2, threadID: threadID, runID: runID, id: "cp-2"))

    let reopened = try ColonyDurableCheckpointStore(baseURL: directory)
    let latest = try await reopened.loadLatest(threadID: ColonyThreadID(threadID.rawValue))
    #expect(latest?.id == SwarmCheckpointID("cp-2"))

    let summaries = try await reopened.listCheckpoints(threadID: ColonyThreadID(threadID.rawValue), limit: nil)
    #expect(summaries.count == 2)
    #expect(summaries.first?.id == SwarmCheckpointID("cp-2"))

    let loaded = try await reopened.loadCheckpoint(threadID: ColonyThreadID(threadID.rawValue), id: SwarmCheckpointID("cp-1"))
    #expect(loaded?.stepIndex == 1)
}

@Test("Task E durable checkpoint store integrates with factory runtime checkpointing")
func taskE_durableCheckpointStoreIntegratesWithFactory() async throws {
    let directory = try temporaryDirectory("factory-checkpoints")
    defer { try? FileManager.default.removeItem(at: directory) }

    let threadID = SwarmThreadID("thread-task-e-factory-checkpoint")
    let runtime = try ColonyAgentFactory().makeRuntime(
        threadID: threadID,
        modelName: "checkpoint-runtime",
        model: SwarmAnyModelClient(InterruptingOnceModelClient()),
        durableCheckpointDirectoryURL: directory,
        configure: { configuration in
            configuration.toolApprovalPolicy = .always
        }
    )

    let handle = await runtime.sendUserMessage("start")
    let outcome = try await handle.outcome.value

    guard case .interrupted = outcome else {
        #expect(Bool(false))
        return
    }

    let store = try ColonyDurableCheckpointStore(baseURL: directory)
    let latest = try await store.loadLatest(threadID: ColonyThreadID(threadID.rawValue))
    #expect(latest != nil)
}

@Test("Task E durable run-state store persists events and restart lookup")
func taskE_durableRunStateStorePersistsAndRestarts() async throws {
    let directory = try temporaryDirectory("run-state")
    defer { try? FileManager.default.removeItem(at: directory) }

    let store = try ColonyDurableRunStateStore(baseURL: directory)
    let runID = UUID(uuidString: "66A4FF14-ED12-4282-B90C-4D261C3E182A")!
    let sessionID = ColonyHarnessSessionID(rawValue: "session-task-e")
    let threadID = ColonyThreadID("thread-task-e-run")
    let timestamp = Date(timeIntervalSince1970: 1_700_000_111)

    try await store.appendEvent(
        makeEnvelope(
            runID: runID,
            sessionID: sessionID,
            sequence: 1,
            eventType: .runStarted,
            timestamp: timestamp
        ),
        threadID: threadID
    )

    try await store.appendEvent(
        makeEnvelope(
            runID: runID,
            sessionID: sessionID,
            sequence: 2,
            eventType: .runInterrupted,
            timestamp: timestamp.addingTimeInterval(1)
        ),
        threadID: threadID
    )

    let reopened = try ColonyDurableRunStateStore(baseURL: directory)
    let state = try await reopened.loadRunState(runID: runID)
    #expect(state?.phase == .interrupted)
    #expect(state?.lastEventSequence == 2)

    let events = try await reopened.loadEvents(runID: runID)
    #expect(events.map(\.eventType) == [.runStarted, .runInterrupted])

    let latestInterrupted = try await reopened.latestInterruptedRun(sessionID: sessionID)
    #expect(latestInterrupted?.runID.rawValue == runID.uuidString)
}

@Test("Task E durable run-state store clears interrupted lookup after resumed completion under the same run ID")
func taskE_durableRunStateStoreClearsInterruptedStateAfterResume() async throws {
    let temp = try temporaryDirectory("run-state-resume")
    defer { try? FileManager.default.removeItem(at: temp) }

    let sessionID = ColonyHarnessSessionID(rawValue: "session-task-e-resume")
    let runStateStore = try ColonyDurableRunStateStore(baseURL: temp.appendingPathComponent("run-state", isDirectory: true))

    let runtime = try ColonyAgentFactory().makeRuntime(
        threadID: SwarmThreadID("thread-task-e-resume"),
        modelName: "resume-test-model",
        model: SwarmAnyModelClient(InterruptThenFinishModelClient()),
        configure: { configuration in
            configuration.toolApprovalPolicy = .always
            configuration.capabilities = [.filesystem]
        }
    )

    let session = ColonyHarnessSession.create(
        runtime: runtime,
        sessionID: sessionID,
        runStateStore: runStateStore
    )
    let stream = await session.stream()
    let consume = Task {
        for try await _ in stream {}
    }

    try await session.start(input: "start")

    let interruptedObserved = await waitUntil {
        let current = try? await runStateStore.latestInterruptedRun(sessionID: sessionID)
        return current != nil
    }
    #expect(interruptedObserved)

    let interruptedState = try #require(try await runStateStore.latestInterruptedRun(sessionID: sessionID))

    try await session.resume(decision: .approved)

    let finishedObserved = await waitUntil {
        let current = try? await runStateStore.latestRunState(sessionID: sessionID)
        return current?.phase == .finished
    }
    #expect(finishedObserved)

    let latestState = try #require(try await runStateStore.latestRunState(sessionID: sessionID))
    #expect(latestState.runID == interruptedState.runID)
    #expect(try await runStateStore.latestInterruptedRun(sessionID: sessionID) == nil)

    await session.stop()
    consume.cancel()
}

@Test("Task E artifact store applies retention and redaction")
func taskE_artifactStoreRetentionAndRedaction() async throws {
    let directory = try temporaryDirectory("artifacts")
    defer { try? FileManager.default.removeItem(at: directory) }

    let store = try ColonyArtifactStore(
        baseURL: directory,
        retentionPolicy: ColonyArtifactRetentionPolicy(maxArtifacts: 2, maxAge: nil)
    )

    let threadID = ColonyThreadID("thread-task-e-artifact")
    let runID = ColonyRunID(rawValue: "6511EC8B-1CA8-4D0E-83A4-7537CA6E76C8")
    let base = Date(timeIntervalSince1970: 1_700_000_500)

    let first = try await store.put(
        threadID: threadID,
        runID: runID,
        kind: "log",
        content: "safe-1",
        metadata: ["scope": "old"],
        createdAt: base
    )

    let second = try await store.put(
        threadID: threadID,
        runID: runID,
        kind: "log",
        content: "token=value-2",
        metadata: ["token": "value-2"],
        createdAt: base.addingTimeInterval(1)
    )

    let third = try await store.put(
        threadID: threadID,
        runID: runID,
        kind: "log",
        content: "safe-3",
        metadata: ["scope": "internal"],
        createdAt: base.addingTimeInterval(2)
    )

    let records = try await store.list(threadID: threadID)
    #expect(records.count == 2)
    #expect(records.map(\.id).contains(first.id) == false)
    #expect(records.map(\.id).contains(second.id) == true)
    #expect(records.map(\.id).contains(third.id) == true)

    let firstContent = try await store.readContent(id: first.id.rawValue)
    #expect(firstContent == nil)

    let thirdContent = try await store.readContent(id: third.id.rawValue)
    #expect(thirdContent == "safe-3")

    let secondRecord = records.first { $0.id == second.id }
    #expect(secondRecord?.redacted == true)
    #expect(secondRecord?.metadata["token"] == "[REDACTED]")

    let secondContent = try await store.readContent(id: second.id.rawValue)
    #expect(secondContent == "token=[REDACTED]")
}

@Test("Task E provider router enforces retry, fallback, rate ceiling, and cost ceiling")
func taskE_providerRouterFallbackBudgetingAndCeilings() async throws {
    let providerA = AlwaysFailModelClient(message: "p1-down")
    let providerB = FixedModelClient(content: "ok-from-b")

    let router = ColonyProviderRouter(
        providers: [
            ColonyProviderRouter.Provider(
                id: "primary",
                client: TestColonyModelClientBridge(providerA),
                priority: 0,
                maxRequestsPerMinute: 10,
                usdPer1KTokens: 0.001
            ),
            ColonyProviderRouter.Provider(
                id: "secondary",
                client: TestColonyModelClientBridge(providerB),
                priority: 1,
                maxRequestsPerMinute: 1,
                usdPer1KTokens: 0.001
            ),
        ],
        policy: ColonyProviderRouter.Policy(
            maxAttemptsPerProvider: 2,
            initialBackoffNanoseconds: 1,
            maxBackoffNanoseconds: 1,
            globalMaxRequestsPerMinute: nil,
            costCeilingUSD: 10,
            estimatedOutputToInputRatio: 0,
            gracefulDegradation: .syntheticResponse("degraded")
        ),
        now: Date.init,
        sleep: { _ in }
    )

    let request = SwarmChatRequest(
        model: "router-model",
        messages: [SwarmChatMessage(id: "m1", role: .user, content: "hello")],
        tools: []
    )

    let routedRequest = ColonyInferenceRequest(request)
    let first = try await router.generate(routedRequest)
    #expect(first.message.content == "ok-from-b")
    #expect(await providerA.snapshotRequestCount() == 2)
    #expect(await providerB.snapshotRequestCount() == 1)

    // Second request should hit secondary provider rate ceiling and degrade.
    let second = try await router.generate(routedRequest)
    #expect(second.message.content == "degraded")

    let expensiveProvider = FixedModelClient(content: "expensive")
    let costCappedRouter = ColonyProviderRouter(
        providers: [
            ColonyProviderRouter.Provider(
                id: "expensive",
                client: TestColonyModelClientBridge(expensiveProvider),
                priority: 0,
                maxRequestsPerMinute: nil,
                usdPer1KTokens: 10
            ),
        ],
        policy: ColonyProviderRouter.Policy(
            maxAttemptsPerProvider: 1,
            initialBackoffNanoseconds: 1,
            maxBackoffNanoseconds: 1,
            globalMaxRequestsPerMinute: nil,
            costCeilingUSD: 0.00001,
            estimatedOutputToInputRatio: 1,
            gracefulDegradation: .syntheticResponse("budget-exhausted")
        ),
        now: Date.init,
        sleep: { _ in }
    )

    let degraded = try await costCappedRouter.generate(routedRequest)
    #expect(degraded.message.content == "budget-exhausted")
    #expect(await expensiveProvider.snapshotRequestCount() == 0)
}

@Test("Task E provider router enforces rate ceilings under concurrent requests")
func taskE_providerRouterConcurrentRateCeilingReservation() async throws {
    let provider = DelayedFixedModelClient(content: "ok", delayNanoseconds: 300_000_000)
    let router = ColonyProviderRouter(
        providers: [
            ColonyProviderRouter.Provider(
                id: "single",
                client: TestColonyModelClientBridge(provider),
                priority: 0,
                maxRequestsPerMinute: 1,
                usdPer1KTokens: nil
            ),
        ],
        policy: ColonyProviderRouter.Policy(
            maxAttemptsPerProvider: 1,
            initialBackoffNanoseconds: 1,
            maxBackoffNanoseconds: 1,
            globalMaxRequestsPerMinute: nil,
            costCeilingUSD: nil,
            estimatedOutputToInputRatio: 0,
            gracefulDegradation: .syntheticResponse("rate-limited")
        ),
        now: Date.init,
        sleep: { _ in }
    )

    let request = SwarmChatRequest(
        model: "router-model",
        messages: [SwarmChatMessage(id: "m1", role: .user, content: "hello")],
        tools: []
    )
    let routedRequest = ColonyInferenceRequest(request)

    async let first = router.generate(routedRequest)
    async let second = router.generate(routedRequest)
    let responses = try await [first, second]
    let responseContents = Set(responses.map { $0.message.content })

    #expect(responseContents.contains("ok"))
    #expect(responseContents.contains("rate-limited"))
    #expect(await provider.snapshotRequestCount() == 1)
}

@Test("Task E provider router propagates cancellation without falling through to lower-priority providers")
func taskE_providerRouterCancellationDoesNotFallThrough() async throws {
    let cancellableProvider = CancellationModelClient()
    let fallbackProvider = FixedModelClient(content: "fallback-should-not-run")

    let router = ColonyProviderRouter(
        providers: [
            ColonyProviderRouter.Provider(
                id: "cancel-first",
                client: TestColonyModelClientBridge(cancellableProvider),
                priority: 0,
                maxRequestsPerMinute: nil,
                usdPer1KTokens: nil
            ),
            ColonyProviderRouter.Provider(
                id: "fallback",
                client: TestColonyModelClientBridge(fallbackProvider),
                priority: 1,
                maxRequestsPerMinute: nil,
                usdPer1KTokens: nil
            ),
        ],
        policy: ColonyProviderRouter.Policy(
            maxAttemptsPerProvider: 2,
            initialBackoffNanoseconds: 1,
            maxBackoffNanoseconds: 1,
            globalMaxRequestsPerMinute: nil,
            costCeilingUSD: nil,
            estimatedOutputToInputRatio: 0,
            gracefulDegradation: .syntheticResponse("degraded")
        ),
        now: Date.init,
        sleep: { _ in }
    )

    let request = ColonyInferenceRequest(
        SwarmChatRequest(
            model: "router-model",
            messages: [SwarmChatMessage(id: "m1", role: .user, content: "hello")],
            tools: []
        )
    )

    do {
        _ = try await router.generate(request)
        Issue.record("Expected CancellationError to propagate, but request completed.")
    } catch is CancellationError {
        // expected
    } catch {
        Issue.record("Expected CancellationError, got \(String(describing: error)).")
    }

    #expect(await cancellableProvider.snapshotRequestCount() == 1)
    #expect(await fallbackProvider.snapshotRequestCount() == 0)
}

@Test("Task E durable run-state store rebuilds snapshot from event log when state file is missing")
func taskE_durableRunStateRebuildsMissingSnapshot() async throws {
    let directory = try temporaryDirectory("run-state-rebuild")
    defer { try? FileManager.default.removeItem(at: directory) }

    let store = try ColonyDurableRunStateStore(baseURL: directory)
    let runID = UUID()
    let sessionID = ColonyHarnessSessionID(rawValue: "session-rebuild")
    let threadID = ColonyThreadID("thread-rebuild")
    let timestamp = Date()

    try await store.appendEvent(
        makeEnvelope(
            runID: runID,
            sessionID: sessionID,
            sequence: 1,
            eventType: .runStarted,
            timestamp: timestamp
        ),
        threadID: threadID
    )
    try await store.appendEvent(
        makeEnvelope(
            runID: runID,
            sessionID: sessionID,
            sequence: 2,
            eventType: .runInterrupted,
            timestamp: timestamp.addingTimeInterval(1)
        ),
        threadID: threadID
    )

    let stateURL = directory
        .appendingPathComponent("runs", isDirectory: true)
        .appendingPathComponent("run-\(runID.uuidString.lowercased())", isDirectory: true)
        .appendingPathComponent("state.json", isDirectory: false)
    try FileManager.default.removeItem(at: stateURL)

    let rebuilt = try await store.loadRunState(runID: runID)
    #expect(rebuilt != nil)
    #expect(rebuilt?.phase == .interrupted)
    #expect(rebuilt?.lastEventSequence == 2)
}

@Test("Task E observability emitter redacts sensitive payloads and harness writes durable run state")
func taskE_observabilityRedactionAndHarnessIntegration() async throws {
    let temp = try temporaryDirectory("obs")
    defer { try? FileManager.default.removeItem(at: temp) }

    let runtime = try ColonyAgentFactory().makeRuntime(
        threadID: SwarmThreadID("thread-task-e-observability"),
        modelName: "streaming-test-model",
        model: SwarmAnyModelClient(FixedModelClient(content: "done", token: "api_key=top_secret")),
        configure: { configuration in
            configuration.toolApprovalPolicy = .never
        }
    )

    let runStateStore = try ColonyDurableRunStateStore(baseURL: temp.appendingPathComponent("run-state", isDirectory: true))
    let sink = ColonyInMemoryObservabilitySink()
    let emitter = ColonyObservabilityEmitter(sinks: [sink])

    let session = ColonyHarnessSession.create(
        runtime: runtime,
        sessionID: ColonyHarnessSessionID(rawValue: "session-observability-task-e"),
        runStateStore: runStateStore,
        observabilityEmitter: emitter
    )

    let stream = await session.stream()
    let consume = Task {
        for try await _ in stream {}
    }

    try await session.start(input: "hello")

    let finishedObserved = await waitUntil {
        let current = try? await runStateStore.latestRunState(
            sessionID: ColonyHarnessSessionID(rawValue: "session-observability-task-e")
        )
        if let current {
            return current.phase == .finished
        }
        return false
    }
    #expect(finishedObserved)

    let events = await sink.events()
    #expect(
        events
            .flatMap(\.attributes.values)
            .allSatisfy { value in
                value.contains("top_secret") == false && value.contains("api_key=top_secret") == false
            }
    )
    #expect(
        events
            .filter { $0.name == "colony.harness.assistant_delta" }
            .allSatisfy { $0.attributes["delta"] == "[REDACTED]" }
    )

    let latestState = try await runStateStore.latestRunState(sessionID: ColonyHarnessSessionID(rawValue: "session-observability-task-e"))
    #expect(latestState?.threadID == ColonyThreadID("thread-task-e-observability"))
    #expect(latestState?.phase == .finished)
    #expect(latestState != nil)
    if let latestState {
        let persistedEvents = try await runStateStore.loadEvents(runID: latestState.runID.hiveRunID.rawValue)
        #expect(persistedEvents.map(\.eventType).contains(.runStarted))
        #expect(persistedEvents.map(\.eventType).contains(.runFinished))
    }

    await session.stop()
    consume.cancel()
}
