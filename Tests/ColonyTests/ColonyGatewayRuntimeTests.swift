import Foundation
import Testing
@testable import Colony

private enum GatewayTestError: Error {
    case scripted(String)
}

private final class AlwaysFailGatewayModelClient: HiveModelClient, @unchecked Sendable {
    private let lock = NSLock()
    private var count: Int = 0
    private let message: String

    init(message: String) {
        self.message = message
    }

    func complete(_ request: HiveChatRequest) async throws -> HiveChatResponse {
        lock.lock()
        count += 1
        lock.unlock()
        throw GatewayTestError.scripted(message)
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

    func requestCount() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }
}

private final class FixedGatewayModelClient: HiveModelClient, @unchecked Sendable {
    private let content: String

    init(content: String) {
        self.content = content
    }

    func complete(_ request: HiveChatRequest) async throws -> HiveChatResponse {
        HiveChatResponse(
            message: HiveChatMessage(
                id: UUID().uuidString.lowercased(),
                role: .assistant,
                content: content
            )
        )
    }

    func stream(_ request: HiveChatRequest) -> AsyncThrowingStream<HiveChatStreamChunk, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(
                .final(
                    HiveChatResponse(
                        message: HiveChatMessage(
                            id: UUID().uuidString.lowercased(),
                            role: .assistant,
                            content: self.content
                        )
                    )
                )
            )
            continuation.finish()
        }
    }
}

private final class ToolThenDoneGatewayModelClient: HiveModelClient, @unchecked Sendable {
    private let lock = NSLock()
    private var invocationCount: Int = 0

    func complete(_ request: HiveChatRequest) async throws -> HiveChatResponse {
        try await streamFinal(request)
    }

    func stream(_ request: HiveChatRequest) -> AsyncThrowingStream<HiveChatStreamChunk, Error> {
        let response = nextResponse()
        return AsyncThrowingStream { continuation in
            continuation.yield(.final(response))
            continuation.finish()
        }
    }

    private func nextResponse() -> HiveChatResponse {
        let current: Int = {
            lock.lock()
            defer { lock.unlock() }
            invocationCount += 1
            return invocationCount
        }()

        if current == 1 {
            let call = HiveToolCall(
                id: "tool-1",
                name: ColonyBuiltInToolDefinitions.ls.name,
                argumentsJSON: #"{"path":"/"}"#
            )
            return HiveChatResponse(
                message: HiveChatMessage(
                    id: "assistant-1",
                    role: .assistant,
                    content: "running tool",
                    toolCalls: [call]
                )
            )
        }

        return HiveChatResponse(
            message: HiveChatMessage(
                id: "assistant-2",
                role: .assistant,
                content: "done"
            )
        )
    }
}

private final class RecordingShellBackend: ColonyShellBackend, @unchecked Sendable {
    private(set) var recorded: [ColonyShellExecutionRequest] = []

    func execute(_ request: ColonyShellExecutionRequest) async throws -> ColonyShellExecutionResult {
        recorded.append(request)
        return ColonyShellExecutionResult(exitCode: 0, stdout: "ok", stderr: "")
    }
}

@Test("Gateway provider resolution supports run override and fallback")
func gateway_providerSelectionAndFallback() async throws {
    let primary = AlwaysFailGatewayModelClient(message: "primary-down")
    let secondary = FixedGatewayModelClient(content: "fallback-ok")

    let providers = ColonyInMemoryProviderRegistry()
    await providers.upsert(
        profile: ColonyProviderProfile(name: "primary", model: "model-a", apiKey: "k1")
    ) { _ in
        AnyHiveModelClient(primary)
    }
    await providers.upsert(
        profile: ColonyProviderProfile(name: "secondary", model: "model-b", apiKey: "k2")
    ) { _ in
        AnyHiveModelClient(secondary)
    }

    let resolved = try await providers.resolve(
        defaultProviderName: "primary",
        defaultFallbackProviderNames: [],
        selection: ColonyProviderSelection(
            preferredProviderName: "primary",
            fallbackProviderNames: ["secondary"]
        )
    )
    #expect(resolved.map { $0.profile.name } == ["primary", "secondary"])

    let router = ColonyProviderRouter(
        providers: resolved.enumerated().map { index, provider in
            ColonyProviderRouter.Provider(
                id: provider.profile.name,
                client: provider.client,
                priority: index
            )
        },
        policy: ColonyProviderRouter.Policy(
            maxAttemptsPerProvider: 1,
            initialBackoffNanoseconds: 1,
            maxBackoffNanoseconds: 1,
            gracefulDegradation: .fail
        ),
        now: Date.init,
        sleep: { _ in }
    )

    let request = HiveChatRequest(
        model: "ignored",
        messages: [HiveChatMessage(id: "u1", role: .user, content: "hello")],
        tools: []
    )
    let response = try await router.route(request, hints: nil).complete(request)
    #expect(response.message.content == "fallback-ok")
    #expect(primary.requestCount() == 1)
}

@Test("Gateway execution policy enforces workspace and deterministic command safety")
func gateway_executionPolicyWorkspaceAndCommandSafety() async throws {
    let filesystem = ColonyInMemoryFileSystemBackend(
        files: [
            try ColonyVirtualPath("/workspace/notes.txt"): "ok",
            try ColonyVirtualPath("/outside.txt"): "denied",
        ]
    )
    let policy = ColonyExecutionPolicy(
        restrictToWorkspace: true,
        workspaceRoot: try ColonyVirtualPath("/workspace")
    )

    let scopedFS = ColonyPolicyAwareFileSystemBackend(base: filesystem, policy: policy)
    let value = try await scopedFS.read(at: ColonyVirtualPath("/workspace/notes.txt"))
    #expect(value == "ok")

    await #expect(throws: ColonyExecutionPolicyError.pathOutsideWorkspace(path: "/outside.txt", workspaceRoot: "/workspace")) {
        _ = try await scopedFS.read(at: ColonyVirtualPath("/outside.txt"))
    }

    let shellPolicy = ColonyExecutionPolicy(
        restrictToWorkspace: true,
        workspaceRoot: try ColonyVirtualPath("/workspace"),
        blockedCommandRules: [.exact("rm -rf /")]
    )
    let shell = ColonyPolicyAwareShellBackend(
        base: RecordingShellBackend(),
        policy: shellPolicy
    )

    await #expect(throws: ColonyExecutionPolicyError.commandBlocked("rm -rf /")) {
        _ = try await shell.execute(
            ColonyShellExecutionRequest(
                command: "rm -rf /",
                workingDirectory: try ColonyVirtualPath("/workspace")
            )
        )
    }
}

@Test("Gateway tool registry returns typed result envelopes for success and failure")
func gateway_toolResultEnvelopeSchema() async throws {
    enum SampleToolError: Error {
        case failed
    }

    let registry = ColonyRuntimeToolRegistry()
    registry.register(
        ColonyToolDefinition(
            name: "send_message",
            description: "Send a message.",
            inputJSONSchema: #"{"type":"object"}"#,
            outputJSONSchema: #"{"type":"object"}"#,
            riskLevel: .network,
            category: .messaging
        )
    ) { _, _ in
        ColonyToolResultEnvelope(
            success: true,
            payload: #"{"status":"sent"}"#,
            attemptCount: 1,
            durationMilliseconds: 3,
            requestID: "req-send-message"
        )
    }

    registry.register(
        ColonyToolDefinition(
            name: "cron_control",
            description: "Control cron.",
            inputJSONSchema: #"{"type":"object"}"#,
            outputJSONSchema: #"{"type":"object"}"#,
            riskLevel: .stateMutation,
            category: .cron
        )
    ) { _, _ in
        throw SampleToolError.failed
    }

    _ = try await registry.invoke(
        HiveToolCall(id: "call-1", name: "send_message", argumentsJSON: "{}")
    )
    _ = try await registry.invoke(
        HiveToolCall(id: "call-2", name: "cron_control", argumentsJSON: "{}")
    )

    let success = registry.resultEnvelope(forToolCallID: "call-1")
    #expect(success?.success == true)
    #expect(success?.requestID == "req-send-message")

    let failure = registry.resultEnvelope(forToolCallID: "call-2")
    #expect(failure?.success == false)
    #expect(failure?.errorCode == "tool_error")
    #expect(failure?.errorType?.contains("SampleToolError") == true)
}

@Test("Gateway checkpoint store adapter persists and resumes latest checkpoint")
func gateway_resumeFromCheckpointAdapter() async throws {
    let directory = try temporaryDirectory(prefix: "colony-gateway-checkpoint")
    defer { try? FileManager.default.removeItem(at: directory) }

    let store = try ColonyDurableRuntimeCheckpointStoreAdapter(baseURL: directory)
    let threadID = HiveThreadID("thread-gateway-checkpoint")
    let runID = HiveRunID(UUID(uuidString: "D39A7E4F-3355-43AF-AC72-3097F7706E57")!)
    let checkpoint = HiveCheckpoint(
        id: HiveCheckpointID("cp-1"),
        threadID: threadID,
        runID: runID,
        stepIndex: 1,
        schemaVersion: "colony-v1",
        graphVersion: "graph-v1",
        globalDataByChannelID: [:],
        frontier: [],
        joinBarrierSeenByJoinID: [:],
        interruption: nil
    )

    try await store.save(checkpoint)

    let reopened = try ColonyDurableRuntimeCheckpointStoreAdapter(baseURL: directory)
    let resumed = try await reopened.loadLatest(threadID: threadID)
    #expect(resumed?.id == HiveCheckpointID("cp-1"))
}

@Test("Gateway spawns isolated child run and routes lifecycle messages to parent sink")
func gateway_spawnIsolationAndMessageRouting() async throws {
    let sink = ColonyInMemoryMessageSink()
    let runtime = try await makeGatewayRuntime(
        model: AnyHiveModelClient(FixedGatewayModelClient(content: "ok")),
        filesystem: nil,
        messageSink: sink
    )

    let parentSessionID = ColonyRuntimeSessionID(rawValue: "session:parent")
    let parent = try await runtime.startRun(
        ColonyGatewayRunRequest(
            sessionID: parentSessionID,
            input: "parent"
        )
    )
    _ = await parent.awaitResult()

    let spawned = try await runtime.spawnSubagent(
        ColonySpawnRequest(
            parentRunID: parent.runID,
            parentSessionID: parentSessionID,
            prompt: "child"
        )
    )

    _ = await spawned.handle.awaitOutcome()

    #expect(spawned.childSessionID != parentSessionID)

    let routed = await sink.messages()
    #expect(routed.contains(where: { message in
        message.target == .parentContext && message.subagentID == spawned.subagentID
    }))

    let events = await runtime.recentEvents(limit: 100)
    #expect(events.contains(where: { $0.kind == .subagentStarted && $0.subagentID == spawned.subagentID }))

    var subagentCompletedObserved = events.contains(where: {
        $0.kind == .subagentCompleted && $0.subagentID == spawned.subagentID
    })
    if subagentCompletedObserved == false {
        for _ in 0 ..< 50 {
            try? await Task.sleep(nanoseconds: 10_000_000)
            let polled = await runtime.recentEvents(limit: 100)
            if polled.contains(where: { $0.kind == .subagentCompleted && $0.subagentID == spawned.subagentID }) {
                subagentCompletedObserved = true
                break
            }
        }
    }
    #expect(subagentCompletedObserved)
}

@Test("Gateway emits ordered structured runtime events")
func gateway_orderedRuntimeEvents() async throws {
    let runtime = try await makeGatewayRuntime(
        model: AnyHiveModelClient(ToolThenDoneGatewayModelClient()),
        filesystem: ColonyInMemoryFileSystemBackend(
            files: [
                try ColonyVirtualPath("/README.md"): "hello",
            ]
        ),
        messageSink: nil
    )

    let handle = try await runtime.startRun(
        ColonyGatewayRunRequest(
            sessionID: ColonyRuntimeSessionID(rawValue: "session:ordered"),
            input: "list files"
        )
    )
    _ = await handle.awaitResult()

    let events = await runtime
        .recentEvents(limit: 200)
        .filter { $0.runID == handle.runID }

    let sequences = events.map(\.sequence)
    #expect(sequences == sequences.sorted())

    let kinds = events.map(\.kind)
    #expect(kinds.first == .runStarted)
    #expect(kinds.contains(.toolDispatched))
    #expect(kinds.contains(.toolResult))
    #expect(kinds.contains(.runCompleted))
}

private func makeGatewayRuntime(
    model: AnyHiveModelClient,
    filesystem: (any ColonyFileSystemBackend)?,
    messageSink: (any ColonyMessageSink)?
) async throws -> ColonyGatewayRuntime {
    let providerRegistry = ColonyInMemoryProviderRegistry()
    await providerRegistry.upsert(
        profile: ColonyProviderProfile(
            name: "local",
            model: "gateway-model",
            apiKey: "test-key"
        )
    ) { _ in
        model
    }

    let configuration = ColonyGatewayRuntimeConfiguration(
        profile: .onDevice4k,
        lane: nil,
        agentID: "gateway-test-agent",
        providers: ColonyProviderRoutingConfiguration(defaultProviderName: "local"),
        defaultExecutionPolicy: ColonyExecutionPolicy(),
        providerRegistry: providerRegistry,
        sessionStore: ColonyInMemoryRuntimeSessionStore(),
        checkpointStore: nil,
        toolRegistry: nil,
        messageSink: messageSink,
        runOptionsOverride: HiveRunOptions(checkpointPolicy: .disabled)
    )

    return ColonyGatewayRuntime(
        configuration: configuration,
        backends: ColonyGatewayBackends(
            filesystem: filesystem
        )
    )
}

private func temporaryDirectory(prefix: String) throws -> URL {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(prefix + "-" + UUID().uuidString.lowercased(), isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
}
