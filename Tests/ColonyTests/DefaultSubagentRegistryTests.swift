import Foundation
import Testing
@testable import Colony

private struct NoopClock: HiveClock {
    func nowNanoseconds() -> UInt64 { 0 }
    func sleep(nanoseconds: UInt64) async throws { try await Task.sleep(nanoseconds: nanoseconds) }
}

private struct NoopLogger: HiveLogger {
    func debug(_ message: String, metadata: [String: String]) {}
    func info(_ message: String, metadata: [String: String]) {}
    func error(_ message: String, metadata: [String: String]) {}
}

private final class GeneralPurposeDelegatingModel: HiveModelClient, @unchecked Sendable {
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
            let call = HiveToolCall(
                id: "task-1",
                name: ColonyBuiltInToolDefinitions.taskName,
                argumentsJSON: #"{"prompt":"Create /from-subagent.txt with content 'hello'.","subagent_type":"general-purpose"}"#
            )
            return HiveChatResponse(
                message: HiveChatMessage(id: "assistant", role: .assistant, content: "delegating", toolCalls: [call])
            )
        }

        return HiveChatResponse(
            message: HiveChatMessage(id: "assistant", role: .assistant, content: "done")
        )
    }
}

private final class SubagentWriteFileModel: HiveModelClient, @unchecked Sendable {
    private let lock = NSLock()
    private var callCount: Int = 0
    private var lastRequest: HiveChatRequest?

    func complete(_ request: HiveChatRequest) async throws -> HiveChatResponse {
        try await streamFinal(request)
    }

    func stream(_ request: HiveChatRequest) -> AsyncThrowingStream<HiveChatStreamChunk, Error> {
        AsyncThrowingStream { continuation in
            Task {
                self.record(request)
                let response = self.respond()
                continuation.yield(.final(response))
                continuation.finish()
            }
        }
    }

    func recordedRequest() -> HiveChatRequest? {
        lock.lock()
        defer { lock.unlock() }
        return lastRequest
    }

    private func record(_ request: HiveChatRequest) {
        lock.lock()
        defer { lock.unlock() }
        lastRequest = request
    }

    private func respond() -> HiveChatResponse {
        let currentCall: Int = {
            lock.lock()
            defer { lock.unlock() }
            callCount += 1
            return callCount
        }()

        if currentCall == 1 {
            let call = HiveToolCall(
                id: "sub-write-1",
                name: "write_file",
                argumentsJSON: #"{"path":"/from-subagent.txt","content":"hello"}"#
            )
            return HiveChatResponse(
                message: HiveChatMessage(id: "assistant", role: .assistant, content: "writing", toolCalls: [call])
            )
        }

        return HiveChatResponse(
            message: HiveChatMessage(id: "assistant", role: .assistant, content: "subagent finished")
        )
    }
}

private final class RecursiveTaskCallModel: HiveModelClient, @unchecked Sendable {
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
            let call = HiveToolCall(
                id: "recursive-1",
                name: ColonyBuiltInToolDefinitions.taskName,
                argumentsJSON: #"{"prompt":"Should not run.","subagent_type":"general-purpose"}"#
            )
            return HiveChatResponse(
                message: HiveChatMessage(id: "assistant", role: .assistant, content: "attempt recursion", toolCalls: [call])
            )
        }

        return HiveChatResponse(
            message: HiveChatMessage(id: "assistant", role: .assistant, content: "done")
        )
    }
}

private final class SubagentLargeToolResultModel: HiveModelClient, @unchecked Sendable {
    private let lock = NSLock()
    private var callCount: Int = 0
    private var requests: [HiveChatRequest] = []

    func recordedRequests() -> [HiveChatRequest] {
        lock.lock()
        defer { lock.unlock() }
        return requests
    }

    func complete(_ request: HiveChatRequest) async throws -> HiveChatResponse {
        try await streamFinal(request)
    }

    func stream(_ request: HiveChatRequest) -> AsyncThrowingStream<HiveChatStreamChunk, Error> {
        lock.lock()
        requests.append(request)
        lock.unlock()

        return AsyncThrowingStream { continuation in
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
            let call = HiveToolCall(
                id: "sub-read-1",
                name: ColonyBuiltInToolDefinitions.readFile.name,
                argumentsJSON: #"{"path":"/big.txt","offset":0,"limit":400}"#
            )
            return HiveChatResponse(
                message: HiveChatMessage(id: "assistant", role: .assistant, content: "reading", toolCalls: [call])
            )
        }

        return HiveChatResponse(
            message: HiveChatMessage(id: "assistant", role: .assistant, content: "done")
        )
    }
}

@Test("Default subagent registry runs general-purpose in an isolated runtime (single tool result + shared FS side-effects only)")
func defaultSubagentRegistry_generalPurpose_runsIsolated_andSharesFileSystemOnly() async throws {
    let graph = try ColonyAgent.compile()
    let fs = ColonyInMemoryFileSystemBackend()
    let subagentModel = SubagentWriteFileModel()

    let registry = ColonyDefaultSubagentRegistry(
        modelName: "test-subagent-model",
        model: AnyHiveModelClient(subagentModel),
        clock: NoopClock(),
        logger: NoopLogger(),
        filesystem: fs
    )

    let configuration = ColonyConfiguration(
        capabilities: [.subagents],
        modelName: "test-parent-model",
        toolApprovalPolicy: .never
    )
    let context = ColonyContext(
        configuration: configuration,
        filesystem: nil,
        subagents: registry
    )

    let environment = HiveEnvironment<ColonySchema>(
        context: context,
        clock: NoopClock(),
        logger: NoopLogger(),
        model: AnyHiveModelClient(GeneralPurposeDelegatingModel())
    )

    let runtime = HiveRuntime(graph: graph, environment: environment)
    let handle = await runtime.run(
        threadID: HiveThreadID("thread-default-subagent-registry"),
        input: "parent secret: 123",
        options: HiveRunOptions(checkpointPolicy: .disabled)
    )

    let outcome = try await handle.outcome.value
    guard case let .finished(output, _) = outcome, case let .fullStore(store) = output else {
        #expect(Bool(false))
        return
    }

    #expect((try store.get(ColonySchema.Channels.finalAnswer)) == "done")

    let messages = try store.get(ColonySchema.Channels.messages)
    let toolMessages = messages.filter { $0.role == HiveChatRole.tool }
    #expect(toolMessages.count == 1)
    #expect(toolMessages.first?.toolCallID == "task-1")

    // Subagent internal tool calls (write_file) must not appear in the parent store.
    #expect(messages.contains(where: { $0.toolCallID == "sub-write-1" }) == false)

    // Shared filesystem side-effect is allowed.
    #expect(try await fs.read(at: ColonyVirtualPath("/from-subagent.txt")) == "hello")

    // Prompt-only isolation: the subagent should not see parent message history.
    let subagentRequest = subagentModel.recordedRequest()
    let sawSecret = subagentRequest?.messages.contains(where: { $0.content.contains("parent secret: 123") }) ?? false
    #expect(sawSecret == false)
}

@Test("Default subagent registry disables recursive subagent invocation by default")
func defaultSubagentRegistry_disablesRecursiveSubagentsByDefault() async throws {
    let graph = try ColonyAgent.compile()

    let registry = ColonyDefaultSubagentRegistry(
        modelName: "test-subagent-model",
        model: AnyHiveModelClient(RecursiveTaskCallModel()),
        clock: NoopClock(),
        logger: NoopLogger(),
        filesystem: nil
    )

    let configuration = ColonyConfiguration(
        capabilities: [.subagents],
        modelName: "test-parent-model",
        toolApprovalPolicy: .never
    )
    let context = ColonyContext(
        configuration: configuration,
        filesystem: nil,
        subagents: registry
    )

    let environment = HiveEnvironment<ColonySchema>(
        context: context,
        clock: NoopClock(),
        logger: NoopLogger(),
        model: AnyHiveModelClient(GeneralPurposeDelegatingModel())
    )

    let runtime = HiveRuntime(graph: graph, environment: environment)
    let handle = await runtime.run(
        threadID: HiveThreadID("thread-default-subagent-registry-recursion"),
        input: "trigger",
        options: HiveRunOptions(checkpointPolicy: .disabled)
    )

    let outcome = try await handle.outcome.value
    guard case let .finished(output, _) = outcome, case let .fullStore(store) = output else {
        #expect(Bool(false))
        return
    }

    let messages = try store.get(ColonySchema.Channels.messages)
    let toolMessage = messages.first { $0.role == HiveChatRole.tool }
    #expect(toolMessage?.content.contains("Subagent registry not configured") == true)
}

@Test("Default subagent registry inherits on-device budget posture (4k-safe) by default")
func defaultSubagentRegistry_inheritsOnDeviceBudgetPosture() async throws {
    let fs = ColonyInMemoryFileSystemBackend()
    let line = String(repeating: "x", count: 60)
    let content = (0..<400).map { _ in line }.joined(separator: "\n")
    try await fs.write(at: ColonyVirtualPath("/big.txt"), content: content)

    let model = SubagentLargeToolResultModel()
    let registry = ColonyDefaultSubagentRegistry(
        profile: .onDevice4k,
        modelName: "test-subagent-model",
        model: AnyHiveModelClient(model),
        clock: NoopClock(),
        logger: NoopLogger(),
        filesystem: fs
    )

    _ = try await registry.run(
        ColonySubagentRequest(
            prompt: "Read /big.txt and confirm the first and last line number.",
            subagentType: "general-purpose"
        )
    )

    let recorded = model.recordedRequests()
    guard recorded.count >= 2 else {
        #expect(Bool(false))
        return
    }

    let postToolRequest = recorded[1]
    let messagesTokenCount = ColonyApproximateTokenizer().countTokens(postToolRequest.messages)
    let toolsTokenCount = approximateToolTokens(postToolRequest.tools)
    #expect((messagesTokenCount + toolsTokenCount) <= 4_000)
}

@Test("Default subagent registry advertises a compactor subagent type")
func defaultSubagentRegistry_advertisesCompactorSubagentType() async throws {
    let registry = ColonyDefaultSubagentRegistry(
        profile: .onDevice4k,
        modelName: "test-subagent-model",
        model: AnyHiveModelClient(GeneralPurposeDelegatingModel()),
        clock: NoopClock(),
        logger: NoopLogger(),
        filesystem: nil
    )

    let names = registry.listSubagents().map(\.name)
    #expect(names.contains("compactor") == true)
}

private func approximateToolTokens(_ tools: [HiveToolDefinition]) -> Int {
    guard tools.isEmpty == false else { return 0 }
    let chars = tools.reduce(into: 0) { partial, tool in
        partial += tool.name.count
        partial += tool.description.count
        partial += tool.parametersJSONSchema.count
    }
    return max(1, chars / 4)
}
