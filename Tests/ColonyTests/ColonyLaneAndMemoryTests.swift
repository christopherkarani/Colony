import Foundation
import Testing
@testable import Colony

private struct LaneMemoryNoopClock: HiveClock {
    func nowNanoseconds() -> UInt64 { 0 }
    func sleep(nanoseconds: UInt64) async throws { try await Task.sleep(nanoseconds: nanoseconds) }
}

private struct LaneMemoryNoopLogger: HiveLogger {
    func debug(_ message: String, metadata: [String: String]) {}
    func info(_ message: String, metadata: [String: String]) {}
    func error(_ message: String, metadata: [String: String]) {}
}

private final class LaneMemoryToolListModel: HiveModelClient, @unchecked Sendable {
    private let lock = NSLock()
    private var requests: [HiveChatRequest] = []

    func complete(_ request: HiveChatRequest) async throws -> HiveChatResponse {
        try await streamFinal(request)
    }

    func stream(_ request: HiveChatRequest) -> AsyncThrowingStream<HiveChatStreamChunk, Error> {
        AsyncThrowingStream { continuation in
            Task {
                self.lock.withLock {
                    self.requests.append(request)
                }

                continuation.yield(
                    .final(
                        HiveChatResponse(
                            message: HiveChatMessage(id: "assistant", role: .assistant, content: "done")
                        )
                    )
                )
                continuation.finish()
            }
        }
    }

    func recordedRequests() -> [HiveChatRequest] {
        lock.withLock { requests }
    }
}

private final class MemoryToolChainModel: HiveModelClient, @unchecked Sendable {
    private let lock = NSLock()
    private var callCount: Int = 0

    func complete(_ request: HiveChatRequest) async throws -> HiveChatResponse {
        try await streamFinal(request)
    }

    func stream(_ request: HiveChatRequest) -> AsyncThrowingStream<HiveChatStreamChunk, Error> {
        AsyncThrowingStream { continuation in
            Task {
                let response = self.respond()
                continuation.yield(.final(response))
                continuation.finish()
            }
        }
    }

    private func respond() -> HiveChatResponse {
        let currentCall: Int = {
            lock.lock()
            defer { lock.unlock() }
            callCount += 1
            return callCount
        }()

        if currentCall == 1 {
            let rememberCall = HiveToolCall(
                id: "wax-remember-1",
                name: ColonyBuiltInToolDefinitions.memoryRemember.name,
                argumentsJSON: #"{"content":"Use Swift concurrency and value types first.","tags":["swift","style"],"metadata":{"source":"user"}}"#
            )
            return HiveChatResponse(
                message: HiveChatMessage(
                    id: "assistant-1",
                    role: .assistant,
                    content: "remembering",
                    toolCalls: [rememberCall]
                )
            )
        }

        if currentCall == 2 {
            let recallCall = HiveToolCall(
                id: "wax-recall-1",
                name: ColonyBuiltInToolDefinitions.memoryRecall.name,
                argumentsJSON: #"{"query":"swift concurrency","limit":5}"#
            )
            return HiveChatResponse(
                message: HiveChatMessage(
                    id: "assistant-2",
                    role: .assistant,
                    content: "recalling",
                    toolCalls: [recallCall]
                )
            )
        }

        return HiveChatResponse(
            message: HiveChatMessage(id: "assistant-3", role: .assistant, content: "done")
        )
    }
}

@Test("Lane router classifies coding and general intents deterministically")
func laneRouterClassifiesCodingAndGeneralIntents() {
    #expect(ColonyAgentFactory.routeLane(forIntent: "Fix this Swift build error and update tests.") == .coding)
    #expect(ColonyAgentFactory.routeLane(forIntent: "Draft a concise team update email.") == .general)
    #expect(ColonyAgentFactory.routeLane(forIntent: "Can you decode this base64 string?") == .general)
}

@Test("Coding lane preset enables coding-specific capabilities")
func codingLanePresetEnablesCodingSpecificCapabilities() {
    let coding = ColonyAgentFactory.configuration(profile: .onDevice4k, modelName: "test-model", lane: .coding)
    #expect(coding.capabilities.contains(.shell))
    #expect(coding.capabilities.contains(.shellSessions))
    #expect(coding.capabilities.contains(.git))
    #expect(coding.capabilities.contains(.lsp))
    #expect(coding.capabilities.contains(.applyPatch))

    let general = ColonyAgentFactory.configuration(profile: .onDevice4k, modelName: "test-model", lane: .general)
    #expect(general.capabilities.contains(.shell) == false)
    #expect(general.capabilities.contains(.git) == false)
    #expect(general.capabilities.contains(.lsp) == false)
}

@Test("Memory tools are advertised only when capability and backend are both configured")
func memoryToolsAdvertisedOnlyWithCapabilityAndBackend() async throws {
    let graph = try ColonyAgent.compile()

    let modelWithBackend = LaneMemoryToolListModel()
    let contextWithBackend = ColonyContext(
        configuration: ColonyConfiguration(
            capabilities: [.memory],
            modelName: "test-model",
            toolApprovalPolicy: .never
        ),
        filesystem: nil,
        memory: ColonyInMemoryMemoryBackend()
    )
    let envWithBackend = HiveEnvironment<ColonySchema>(
        context: contextWithBackend,
        clock: LaneMemoryNoopClock(),
        logger: LaneMemoryNoopLogger(),
        model: AnyHiveModelClient(modelWithBackend)
    )
    let runtimeWithBackend = HiveRuntime(graph: graph, environment: envWithBackend)
    _ = try await runtimeWithBackend
        .run(
            threadID: HiveThreadID("thread-memory-tools-with-backend"),
            input: "hi",
            options: HiveRunOptions(checkpointPolicy: .disabled)
        )
        .outcome
        .value

    let withBackendToolNames = Set(modelWithBackend.recordedRequests().first?.tools.map(\.name) ?? [])
    #expect(withBackendToolNames.contains(ColonyBuiltInToolDefinitions.memoryRecall.name))
    #expect(withBackendToolNames.contains(ColonyBuiltInToolDefinitions.memoryRemember.name))

    let modelWithoutBackend = LaneMemoryToolListModel()
    let contextWithoutBackend = ColonyContext(
        configuration: ColonyConfiguration(
            capabilities: [.memory],
            modelName: "test-model",
            toolApprovalPolicy: .never
        ),
        filesystem: nil
    )
    let envWithoutBackend = HiveEnvironment<ColonySchema>(
        context: contextWithoutBackend,
        clock: LaneMemoryNoopClock(),
        logger: LaneMemoryNoopLogger(),
        model: AnyHiveModelClient(modelWithoutBackend)
    )
    let runtimeWithoutBackend = HiveRuntime(graph: graph, environment: envWithoutBackend)
    _ = try await runtimeWithoutBackend
        .run(
            threadID: HiveThreadID("thread-memory-tools-without-backend"),
            input: "hi",
            options: HiveRunOptions(checkpointPolicy: .disabled)
        )
        .outcome
        .value

    let withoutBackendToolNames = Set(modelWithoutBackend.recordedRequests().first?.tools.map(\.name) ?? [])
    #expect(withoutBackendToolNames.contains(ColonyBuiltInToolDefinitions.memoryRecall.name) == false)
    #expect(withoutBackendToolNames.contains(ColonyBuiltInToolDefinitions.memoryRemember.name) == false)
}

@Test("Memory tools dispatch to configured backend and persist recalled content")
func memoryToolsDispatchAndPersist() async throws {
    let graph = try ColonyAgent.compile()
    let memory = ColonyInMemoryMemoryBackend()

    let configuration = ColonyConfiguration(
        capabilities: [.memory],
        modelName: "test-model",
        toolApprovalPolicy: .never,
        mandatoryApprovalRiskLevels: []
    )
    let context = ColonyContext(
        configuration: configuration,
        filesystem: nil,
        memory: memory
    )
    let environment = HiveEnvironment<ColonySchema>(
        context: context,
        clock: LaneMemoryNoopClock(),
        logger: LaneMemoryNoopLogger(),
        model: AnyHiveModelClient(MemoryToolChainModel())
    )
    let runtime = HiveRuntime(graph: graph, environment: environment)

    let outcome = try await runtime
        .run(
            threadID: HiveThreadID("thread-memory-dispatch"),
            input: "store and recall memory",
            options: HiveRunOptions(maxSteps: 50, checkpointPolicy: .disabled)
        )
        .outcome
        .value

    guard case let .finished(output, _) = outcome, case let .fullStore(store) = output else {
        #expect(Bool(false))
        return
    }

    #expect((try store.get(ColonySchema.Channels.finalAnswer)) == "done")

    let recalled = try await memory.recall(
        ColonyMemoryRecallRequest(query: "swift concurrency", limit: 5)
    )
    #expect(recalled.items.isEmpty == false)
    #expect(recalled.items.contains(where: { $0.content.contains("Swift concurrency") }))

    let messages = try store.get(ColonySchema.Channels.messages)
    let recallToolMessage = messages.first(where: { $0.role == .tool && $0.toolCallID == "wax-recall-1" })
    #expect(recallToolMessage?.content.contains("Use Swift concurrency") == true)
}

@Test("In-memory memory backend chooses non-colliding IDs when seeded")
func memoryBackendAvoidsIDCollisionsWhenSeeded() async throws {
    let backend = ColonyInMemoryMemoryBackend(
        nextID: 1,
        items: [
            ColonyMemoryItem(id: "mem-3", content: "existing"),
            ColonyMemoryItem(id: "custom-id", content: "other"),
        ]
    )

    let first = try await backend.remember(
        ColonyMemoryRememberRequest(content: "new fact")
    )
    let second = try await backend.remember(
        ColonyMemoryRememberRequest(content: "another fact")
    )

    #expect(first.id == "mem-4")
    #expect(second.id == "mem-5")
}
