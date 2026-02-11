import Foundation
import Dispatch
import Testing
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

private final class AlwaysFailModelClient: HiveModelClient, @unchecked Sendable {
    private let counter = RequestCounter()
    private let message: String

    init(message: String) {
        self.message = message
    }

    func complete(_ request: HiveChatRequest) async throws -> HiveChatResponse {
        await counter.increment()
        throw TaskETestError.scriptedFailure(message)
    }

    func snapshotRequestCount() async -> Int {
        await counter.value()
    }

    func stream(_ request: HiveChatRequest) -> AsyncThrowingStream<HiveChatStreamChunk, Error> {
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

private final class FixedModelClient: HiveModelClient, @unchecked Sendable {
    private let counter = RequestCounter()
    private let content: String
    private let token: String?

    init(content: String, token: String? = nil) {
        self.content = content
        self.token = token
    }

    func complete(_ request: HiveChatRequest) async throws -> HiveChatResponse {
        await counter.increment()
        return HiveChatResponse(message: HiveChatMessage(id: UUID().uuidString, role: .assistant, content: content))
    }

    func snapshotRequestCount() async -> Int {
        await counter.value()
    }

    func stream(_ request: HiveChatRequest) -> AsyncThrowingStream<HiveChatStreamChunk, Error> {
        return AsyncThrowingStream { continuation in
            Task {
                await self.counter.increment()
                if let token {
                    continuation.yield(.token(token))
                }
                continuation.yield(.final(HiveChatResponse(message: HiveChatMessage(id: UUID().uuidString, role: .assistant, content: self.content))))
                continuation.finish()
            }
        }
    }
}

private final class InterruptingOnceModelClient: HiveModelClient, @unchecked Sendable {
    func complete(_ request: HiveChatRequest) async throws -> HiveChatResponse {
        try await streamFinal(request)
    }

    func stream(_ request: HiveChatRequest) -> AsyncThrowingStream<HiveChatStreamChunk, Error> {
        AsyncThrowingStream { continuation in
            let call = HiveToolCall(
                id: "approval-1",
                name: "write_file",
                argumentsJSON: #"{"path":"/checkpoint.md","content":"checkpoint"}"#
            )
            continuation.yield(
                .final(
                    HiveChatResponse(
                        message: HiveChatMessage(
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

private func temporaryDirectory(_ suffix: String) throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("colony-task-e-tests", isDirectory: true)
        .appendingPathComponent(suffix + "-" + UUID().uuidString.lowercased(), isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private func makeCheckpoint(stepIndex: Int, threadID: HiveThreadID, runID: HiveRunID, id: String) -> HiveCheckpoint<ColonySchema> {
    HiveCheckpoint(
        id: HiveCheckpointID(id),
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

    let threadID = HiveThreadID("thread-task-e-checkpoint")
    let runID = HiveRunID(UUID(uuidString: "D39A7E4F-3355-43AF-AC72-3097F7706E57")!)

    let store = try ColonyDurableCheckpointStore<ColonySchema>(baseURL: directory)
    try await store.save(makeCheckpoint(stepIndex: 1, threadID: threadID, runID: runID, id: "cp-1"))
    try await store.save(makeCheckpoint(stepIndex: 2, threadID: threadID, runID: runID, id: "cp-2"))

    let reopened = try ColonyDurableCheckpointStore<ColonySchema>(baseURL: directory)
    let latest = try await reopened.loadLatest(threadID: threadID)
    #expect(latest?.id == HiveCheckpointID("cp-2"))

    let summaries = try await reopened.listCheckpoints(threadID: threadID, limit: nil)
    #expect(summaries.count == 2)
    #expect(summaries.first?.id == HiveCheckpointID("cp-2"))

    let loaded = try await reopened.loadCheckpoint(threadID: threadID, id: HiveCheckpointID("cp-1"))
    #expect(loaded?.stepIndex == 1)
}

@Test("Task E durable checkpoint store integrates with factory runtime checkpointing")
func taskE_durableCheckpointStoreIntegratesWithFactory() async throws {
    let directory = try temporaryDirectory("factory-checkpoints")
    defer { try? FileManager.default.removeItem(at: directory) }

    let threadID = HiveThreadID("thread-task-e-factory-checkpoint")
    let runtime = try ColonyAgentFactory().makeRuntime(
        threadID: threadID,
        modelName: "checkpoint-runtime",
        model: AnyHiveModelClient(InterruptingOnceModelClient()),
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

    let store = try ColonyDurableCheckpointStore<ColonySchema>(baseURL: directory)
    let latest = try await store.loadLatest(threadID: threadID)
    #expect(latest != nil)
}

@Test("Task E durable run-state store persists events and restart lookup")
func taskE_durableRunStateStorePersistsAndRestarts() async throws {
    let directory = try temporaryDirectory("run-state")
    defer { try? FileManager.default.removeItem(at: directory) }

    let store = try ColonyDurableRunStateStore(baseURL: directory)
    let runID = UUID(uuidString: "66A4FF14-ED12-4282-B90C-4D261C3E182A")!
    let sessionID = ColonyHarnessSessionID(rawValue: "session-task-e")
    let threadID = HiveThreadID("thread-task-e-run")
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
    #expect(latestInterrupted?.runID == runID)
}

@Test("Task E artifact store applies retention and redaction")
func taskE_artifactStoreRetentionAndRedaction() async throws {
    let directory = try temporaryDirectory("artifacts")
    defer { try? FileManager.default.removeItem(at: directory) }

    let store = try ColonyArtifactStore(
        baseURL: directory,
        retentionPolicy: ColonyArtifactRetentionPolicy(maxArtifacts: 2, maxAge: nil)
    )

    let threadID = HiveThreadID("thread-task-e-artifact")
    let runID = HiveRunID(UUID(uuidString: "6511EC8B-1CA8-4D0E-83A4-7537CA6E76C8")!)
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

    let firstContent = try await store.readContent(id: first.id)
    #expect(firstContent == nil)

    let thirdContent = try await store.readContent(id: third.id)
    #expect(thirdContent == "safe-3")

    let secondRecord = records.first { $0.id == second.id }
    #expect(secondRecord?.redacted == true)
    #expect(secondRecord?.metadata["token"] == "[REDACTED]")

    let secondContent = try await store.readContent(id: second.id)
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
                client: AnyHiveModelClient(providerA),
                priority: 0,
                maxRequestsPerMinute: 10,
                usdPer1KTokens: 0.001
            ),
            ColonyProviderRouter.Provider(
                id: "secondary",
                client: AnyHiveModelClient(providerB),
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

    let request = HiveChatRequest(
        model: "router-model",
        messages: [HiveChatMessage(id: "m1", role: .user, content: "hello")],
        tools: []
    )

    let routedClient = router.route(request, hints: nil)
    let first = try await routedClient.complete(request)
    #expect(first.message.content == "ok-from-b")
    #expect(await providerA.snapshotRequestCount() == 2)
    #expect(await providerB.snapshotRequestCount() == 1)

    // Second request should hit secondary provider rate ceiling and degrade.
    let second = try await routedClient.complete(request)
    #expect(second.message.content == "degraded")

    let expensiveProvider = FixedModelClient(content: "expensive")
    let costCappedRouter = ColonyProviderRouter(
        providers: [
            ColonyProviderRouter.Provider(
                id: "expensive",
                client: AnyHiveModelClient(expensiveProvider),
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

    let costClient = costCappedRouter.route(request, hints: nil)
    let degraded = try await costClient.complete(request)
    #expect(degraded.message.content == "budget-exhausted")
    #expect(await expensiveProvider.snapshotRequestCount() == 0)
}

@Test("Task E observability emitter redacts sensitive payloads and harness writes durable run state")
func taskE_observabilityRedactionAndHarnessIntegration() async throws {
    let temp = try temporaryDirectory("obs")
    defer { try? FileManager.default.removeItem(at: temp) }

    let runtime = try ColonyAgentFactory().makeRuntime(
        threadID: HiveThreadID("thread-task-e-observability"),
        modelName: "streaming-test-model",
        model: AnyHiveModelClient(FixedModelClient(content: "done", token: "api_key=top_secret")),
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
    #expect(latestState?.threadID == "thread-task-e-observability")
    #expect(latestState?.phase == .finished)
    #expect(latestState != nil)
    if let latestState {
        let persistedEvents = try await runStateStore.loadEvents(runID: latestState.runID)
        #expect(persistedEvents.map(\.eventType).contains(.runStarted))
        #expect(persistedEvents.map(\.eventType).contains(.runFinished))
    }

    await session.stop()
    consume.cancel()
}
