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

private actor InMemoryCheckpointStore<Schema: HiveSchema>: HiveCheckpointStore {
    private var checkpoints: [HiveCheckpoint<Schema>] = []

    func save(_ checkpoint: HiveCheckpoint<Schema>) async throws {
        checkpoints.append(checkpoint)
    }

    func loadLatest(threadID: HiveThreadID) async throws -> HiveCheckpoint<Schema>? {
        checkpoints
            .filter { $0.threadID == threadID }
            .max { lhs, rhs in
                if lhs.stepIndex == rhs.stepIndex { return lhs.id.rawValue < rhs.id.rawValue }
                return lhs.stepIndex < rhs.stepIndex
            }
    }
}

private final class ScriptedModel: HiveModelClient, @unchecked Sendable {
    private let lock = NSLock()
    private var callCount: Int = 0

    func complete(_ request: HiveChatRequest) async throws -> HiveChatResponse {
        try await streamFinal(request)
    }

    func stream(_ request: HiveChatRequest) -> AsyncThrowingStream<HiveChatStreamChunk, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let response = try self.respond(to: request)
                    continuation.yield(.final(response))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    private func respond(to request: HiveChatRequest) throws -> HiveChatResponse {
        let currentCall: Int = {
            lock.lock()
            defer { lock.unlock() }
            callCount += 1
            return callCount
        }()

        let sawRejectionSystemMessage = request.messages.contains { message in
            message.role == .system && message.content.contains("Tool execution rejected by user.")
        }

        if sawRejectionSystemMessage {
            return HiveChatResponse(
                message: HiveChatMessage(id: "assistant", role: .assistant, content: "ok")
            )
        }

        if currentCall == 1 {
            let call = HiveToolCall(
                id: "call-1",
                name: "write_file",
                argumentsJSON: #"{"path":"/note.md","content":"hello"}"#
            )
            return HiveChatResponse(
                message: HiveChatMessage(id: "assistant", role: .assistant, content: "writing", toolCalls: [call])
            )
        }

        return HiveChatResponse(
            message: HiveChatMessage(id: "assistant", role: .assistant, content: "done")
        )
    }
}

private actor RecordingShellBackend: ColonyShellBackend {
    private var requests: [ColonyShellExecutionRequest] = []
    private let fixedResult: ColonyShellExecutionResult

    init(fixedResult: ColonyShellExecutionResult) {
        self.fixedResult = fixedResult
    }

    func execute(_ request: ColonyShellExecutionRequest) async throws -> ColonyShellExecutionResult {
        requests.append(request)
        return fixedResult
    }

    func recordedRequests() -> [ColonyShellExecutionRequest] {
        requests
    }
}

private actor RecordingSubagentRegistry: ColonySubagentRegistry {
    private var requests: [ColonySubagentRequest] = []

    nonisolated func listSubagents() -> [ColonySubagentDescriptor] {
        [
            ColonySubagentDescriptor(name: "general-purpose", description: "General-purpose helper."),
            ColonySubagentDescriptor(name: "research", description: "Deep research helper."),
        ]
    }

    func run(_ request: ColonySubagentRequest) async throws -> ColonySubagentResult {
        requests.append(request)
        return ColonySubagentResult(content: "subagent[\(request.subagentType)] completed")
    }

    func recordedRequests() -> [ColonySubagentRequest] {
        requests
    }
}

private final class ExecuteToolModel: HiveModelClient, @unchecked Sendable {
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
                id: "exec-1",
                name: "execute",
                argumentsJSON: #"{"command":"echo hi","timeout_ms":1500}"#
            )
            return HiveChatResponse(
                message: HiveChatMessage(id: "assistant", role: .assistant, content: "running", toolCalls: [call])
            )
        }

        return HiveChatResponse(
            message: HiveChatMessage(id: "assistant", role: .assistant, content: "done")
        )
    }
}

private final class TaskToolModel: HiveModelClient, @unchecked Sendable {
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
                argumentsJSON: #"{"prompt":"Collect three iOS benchmark ideas.","subagent_type":"research"}"#
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

private final class RecordingRequestModel: HiveModelClient, @unchecked Sendable {
    private let lock = NSLock()
    private var requests: [HiveChatRequest] = []
    private let responder: @Sendable (HiveChatRequest) -> HiveChatResponse

    init(responder: @escaping @Sendable (HiveChatRequest) -> HiveChatResponse = { _ in
        HiveChatResponse(message: HiveChatMessage(id: "assistant", role: .assistant, content: "ok"))
    }) {
        self.responder = responder
    }

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

        let response = responder(request)
        return AsyncThrowingStream { continuation in
            continuation.yield(.final(response))
            continuation.finish()
        }
    }
}

@Test("Colony interrupts for tool approval and resumes approved path")
func colonyInterruptsAndResumesApproved() async throws {
    let graph = try ColonyAgent.compile()
    let fs = ColonyInMemoryFileSystemBackend()

    let configuration = ColonyConfiguration(
        capabilities: [.filesystem],
        modelName: "test-model",
        toolApprovalPolicy: .allowList(["ls", "read_file", "glob", "grep"])
    )
    let context = ColonyContext(configuration: configuration, filesystem: fs)

    let checkpointStore = InMemoryCheckpointStore<ColonySchema>()
    let environment = HiveEnvironment(
        context: context,
        clock: NoopClock(),
        logger: NoopLogger(),
        model: AnyHiveModelClient(ScriptedModel()),
        checkpointStore: AnyHiveCheckpointStore(checkpointStore)
    )

    let runtime = HiveRuntime(graph: graph, environment: environment)
    let threadID = HiveThreadID("thread-approved")

    let handle = await runtime.run(
        threadID: threadID,
        input: "hi",
        options: HiveRunOptions(checkpointPolicy: .onInterrupt)
    )

    let outcome = try await handle.outcome.value
    guard case let .interrupted(interruption) = outcome else {
        #expect(Bool(false))
        return
    }

    guard case let .toolApprovalRequired(toolCalls) = interruption.interrupt.payload else {
        #expect(Bool(false))
        return
    }
    #expect(toolCalls.count == 1)
    #expect(toolCalls.first?.name == "write_file")

    let resumed = await runtime.resume(
        threadID: threadID,
        interruptID: interruption.interrupt.id,
        payload: .toolApproval(decision: .approved),
        options: HiveRunOptions(checkpointPolicy: .onInterrupt)
    )

    let resumedOutcome = try await resumed.outcome.value
    guard case let .finished(output, _) = resumedOutcome else {
        #expect(Bool(false))
        return
    }

    guard case let .fullStore(store) = output else {
        #expect(Bool(false))
        return
    }

    #expect((try store.get(ColonySchema.Channels.finalAnswer)) == "done")

    let written = try await fs.read(at: try ColonyVirtualPath("/note.md"))
    #expect(written == "hello")
}

@Test("Colony resumes rejected tool path without executing tools")
func colonyResumesRejected() async throws {
    let graph = try ColonyAgent.compile()
    let fs = ColonyInMemoryFileSystemBackend()

    let configuration = ColonyConfiguration(
        capabilities: [.filesystem],
        modelName: "test-model",
        toolApprovalPolicy: .always
    )
    let context = ColonyContext(configuration: configuration, filesystem: fs)

    let checkpointStore = InMemoryCheckpointStore<ColonySchema>()
    let environment = HiveEnvironment(
        context: context,
        clock: NoopClock(),
        logger: NoopLogger(),
        model: AnyHiveModelClient(ScriptedModel()),
        checkpointStore: AnyHiveCheckpointStore(checkpointStore)
    )

    let runtime = HiveRuntime(graph: graph, environment: environment)
    let threadID = HiveThreadID("thread-rejected")

    let handle = await runtime.run(
        threadID: threadID,
        input: "hi",
        options: HiveRunOptions(checkpointPolicy: .onInterrupt)
    )

    let outcome = try await handle.outcome.value
    guard case let .interrupted(interruption) = outcome else {
        #expect(Bool(false))
        return
    }

    let resumed = await runtime.resume(
        threadID: threadID,
        interruptID: interruption.interrupt.id,
        payload: .toolApproval(decision: .rejected),
        options: HiveRunOptions(checkpointPolicy: .onInterrupt)
    )

    let resumedOutcome = try await resumed.outcome.value
    guard case let .finished(output, _) = resumedOutcome else {
        #expect(Bool(false))
        return
    }

    guard case let .fullStore(store) = output else {
        #expect(Bool(false))
        return
    }

    #expect((try store.get(ColonySchema.Channels.finalAnswer)) == "ok")

    do {
        _ = try await fs.read(at: try ColonyVirtualPath("/note.md"))
        #expect(Bool(false))
    } catch {
        // Expected: file does not exist.
    }

    // Deep Agents parity: rejecting tool execution must still "close" tool_call_ids
    // by emitting a tool message for each pending tool call.
    let messages = try store.get(ColonySchema.Channels.messages)
    let cancellation = messages.first { message in
        message.role == .tool && message.toolCallID == "call-1"
    }
    #expect(cancellation != nil)
}

@Test("Colony messages reducer supports removeAll markers and delete-by-id")
func colonyMessagesReducerSemantics() throws {
    let a = HiveChatMessage(id: "a", role: .user, content: "a")
    let b = HiveChatMessage(id: "b", role: .assistant, content: "b")

    let removeAll = HiveChatMessage(
        id: ColonySchema.removeAllMessagesID,
        role: .system,
        content: "",
        op: .removeAll
    )
    let c = HiveChatMessage(id: "c", role: .user, content: "c")

    let merged = try ColonyMessages.reduceMessages(left: [a, b], right: [removeAll, c])
    #expect(merged.map(\.id) == ["c"])

    let removeB = HiveChatMessage(id: "b", role: .system, content: "", op: .remove)
    let merged2 = try ColonyMessages.reduceMessages(left: [a, b], right: [removeB])
    #expect(merged2.map(\.id) == ["a"])

    do {
        _ = try ColonyMessages.reduceMessages(
            left: [a],
            right: [HiveChatMessage(id: "missing", role: .system, content: "", op: .remove)]
        )
        #expect(Bool(false))
    } catch let error as HiveRuntimeError {
        switch error {
        case .invalidMessagesUpdate:
            #expect(Bool(true))
        default:
            #expect(Bool(false))
        }
    } catch {
        #expect(Bool(false))
    }
}

@Test("Colony execute tool uses shell backend")
func colonyExecuteToolUsesShellBackend() async throws {
    let graph = try ColonyAgent.compile()
    let shell = RecordingShellBackend(
        fixedResult: ColonyShellExecutionResult(exitCode: 0, stdout: "hi", stderr: "")
    )

    let configuration = ColonyConfiguration(
        capabilities: [.shell],
        modelName: "test-model",
        toolApprovalPolicy: .never
    )
    let context = ColonyContext(configuration: configuration, filesystem: nil, shell: shell)

    let environment = HiveEnvironment<ColonySchema>(
        context: context,
        clock: NoopClock(),
        logger: NoopLogger(),
        model: AnyHiveModelClient(ExecuteToolModel())
    )

    let runtime = HiveRuntime(graph: graph, environment: environment)
    let handle = await runtime.run(
        threadID: HiveThreadID("thread-execute"),
        input: "run execute",
        options: HiveRunOptions(checkpointPolicy: .disabled)
    )

    let outcome = try await handle.outcome.value
    guard case let .finished(output, _) = outcome, case let .fullStore(store) = output else {
        #expect(Bool(false))
        return
    }

    #expect((try store.get(ColonySchema.Channels.finalAnswer)) == "done")

    let requests = await shell.recordedRequests()
    #expect(requests.count == 1)
    #expect(requests.first?.command == "echo hi")

    let messages = try store.get(ColonySchema.Channels.messages)
    let toolMessage = messages.first { $0.role == HiveChatRole.tool }
    #expect(toolMessage?.content.contains("exit_code: 0") == true)
}

@Test("Colony task tool delegates to subagent registry")
func colonyTaskToolDelegatesToSubagentRegistry() async throws {
    let graph = try ColonyAgent.compile()
    let subagents = RecordingSubagentRegistry()

    let configuration = ColonyConfiguration(
        capabilities: [.subagents],
        modelName: "test-model",
        toolApprovalPolicy: .never
    )
    let context = ColonyContext(
        configuration: configuration,
        filesystem: nil,
        subagents: subagents
    )

    let environment = HiveEnvironment<ColonySchema>(
        context: context,
        clock: NoopClock(),
        logger: NoopLogger(),
        model: AnyHiveModelClient(TaskToolModel())
    )

    let runtime = HiveRuntime(graph: graph, environment: environment)
    let handle = await runtime.run(
        threadID: HiveThreadID("thread-task"),
        input: "delegate task",
        options: HiveRunOptions(checkpointPolicy: .disabled)
    )

    let outcome = try await handle.outcome.value
    guard case let .finished(output, _) = outcome, case let .fullStore(store) = output else {
        #expect(Bool(false))
        return
    }

    #expect((try store.get(ColonySchema.Channels.finalAnswer)) == "done")

    let requests = await subagents.recordedRequests()
    #expect(requests.count == 1)
    #expect(requests.first?.subagentType == "research")
    #expect(requests.first?.prompt == "Collect three iOS benchmark ideas.")

    let messages = try store.get(ColonySchema.Channels.messages)
    let toolMessage = messages.first { $0.role == HiveChatRole.tool }
    #expect(toolMessage?.content == "subagent[research] completed")
}

@Test("System prompt injects AGENTS memory when configured")
func systemPromptInjectsAgentsMemory() async throws {
    let graph = try ColonyAgent.compile()
    let model = RecordingRequestModel()

    let fs = ColonyInMemoryFileSystemBackend(
        files: [
            try ColonyVirtualPath("/AGENTS.md"): "MEMORY_A: Keep responses concise.\n",
            try ColonyVirtualPath("/nested/AGENTS.md"): "MEMORY_B: Prefer value types.\n",
        ]
    )

    var configuration = ColonyConfiguration(
        capabilities: [.filesystem],
        modelName: "test-model",
        toolApprovalPolicy: .never
    )
    configuration.memorySources = [
        try ColonyVirtualPath("/AGENTS.md"),
        try ColonyVirtualPath("/nested/AGENTS.md"),
    ]
    let context = ColonyContext(configuration: configuration, filesystem: fs)

    let environment = HiveEnvironment<ColonySchema>(
        context: context,
        clock: NoopClock(),
        logger: NoopLogger(),
        model: AnyHiveModelClient(model)
    )
    let runtime = HiveRuntime(graph: graph, environment: environment)

    let handle = await runtime.run(
        threadID: HiveThreadID("thread-memory"),
        input: "hi",
        options: HiveRunOptions(checkpointPolicy: .disabled)
    )
    _ = try await handle.outcome.value

    let requests = model.recordedRequests()
    #expect(requests.count == 1)
    #expect(requests.first?.messages.first?.role == .system)

    let systemPrompt = requests.first?.messages.first?.content ?? ""
    #expect(systemPrompt.contains("MEMORY_A: Keep responses concise.") == true)
    #expect(systemPrompt.contains("MEMORY_B: Prefer value types.") == true)
}

@Test("System prompt injects SKILL metadata (without body) when configured")
func systemPromptInjectsSkillCatalogMetadata() async throws {
    let graph = try ColonyAgent.compile()
    let model = RecordingRequestModel()

    let fs = ColonyInMemoryFileSystemBackend(
        files: [
            try ColonyVirtualPath("/skills/example/SKILL.md"): """
---
name: Example Skill
description: Does example things.
---

BODY_SENTINEL_SHOULD_NOT_BE_DISCLOSED
""",
        ]
    )

    var configuration = ColonyConfiguration(
        capabilities: [.filesystem],
        modelName: "test-model",
        toolApprovalPolicy: .never
    )
    configuration.skillSources = [
        try ColonyVirtualPath("/skills"),
    ]
    let context = ColonyContext(configuration: configuration, filesystem: fs)

    let environment = HiveEnvironment<ColonySchema>(
        context: context,
        clock: NoopClock(),
        logger: NoopLogger(),
        model: AnyHiveModelClient(model)
    )
    let runtime = HiveRuntime(graph: graph, environment: environment)

    let handle = await runtime.run(
        threadID: HiveThreadID("thread-skills"),
        input: "hi",
        options: HiveRunOptions(checkpointPolicy: .disabled)
    )
    _ = try await handle.outcome.value

    let requests = model.recordedRequests()
    #expect(requests.count == 1)
    #expect(requests.first?.messages.first?.role == .system)

    let systemPrompt = requests.first?.messages.first?.content ?? ""
    #expect(systemPrompt.contains("Example Skill") == true)
    #expect(systemPrompt.contains("Does example things.") == true)
    #expect(systemPrompt.contains("/skills/example/SKILL.md") == true)
    #expect(systemPrompt.contains("BODY_SENTINEL_SHOULD_NOT_BE_DISCLOSED") == false)
}
