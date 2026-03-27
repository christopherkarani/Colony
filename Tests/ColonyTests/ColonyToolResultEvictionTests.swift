import Foundation
import Testing
@_spi(ColonyInternal) import Swarm
@testable import Colony

private struct NoopClock: SwarmClock {
    func nowNanoseconds() -> UInt64 { 0 }
    func sleep(nanoseconds: UInt64) async throws { try await Task.sleep(nanoseconds: nanoseconds) }
}

private struct NoopLogger: SwarmLogger {
    func debug(_ message: String, metadata: [String: String]) {}
    func info(_ message: String, metadata: [String: String]) {}
    func error(_ message: String, metadata: [String: String]) {}
}

private struct LargeOutputToolRegistry: SwarmToolRegistry, Sendable {
    let output: String

    func listTools() -> [SwarmToolDefinition] {
        [
            SwarmToolDefinition(
                name: "big_tool",
                description: "Returns a very large tool result.",
                parametersJSONSchema: #"{"type":"object","properties":{}}"#
            )
        ]
    }

    func invoke(_ call: SwarmToolCall) async throws -> SwarmToolResult {
        SwarmToolResult(toolCallID: call.id, content: output)
    }
}

private final class BigToolModel: SwarmModelClient, @unchecked Sendable {
    private let lock = NSLock()
    private var callCount: Int = 0

    func complete(_ request: SwarmChatRequest) async throws -> SwarmChatResponse {
        try await streamFinal(request)
    }

    func stream(_ request: SwarmChatRequest) -> AsyncThrowingStream<SwarmChatStreamChunk, Error> {
        AsyncThrowingStream { continuation in
            Task {
                let response = self.respond()
                continuation.yield(.final(response))
                continuation.finish()
            }
        }
    }

    private func respond() -> SwarmChatResponse {
        let currentCall: Int = {
            lock.lock()
            defer { lock.unlock() }
            callCount += 1
            return callCount
        }()

        if currentCall == 1 {
            let call = SwarmToolCall(
                id: "evict-1",
                name: "big_tool",
                argumentsJSON: #"{}"#
            )
            return SwarmChatResponse(
                message: SwarmChatMessage(id: "assistant", role: .assistant, content: "running big tool", toolCalls: [call])
            )
        }

        return SwarmChatResponse(
            message: SwarmChatMessage(id: "assistant", role: .assistant, content: "done")
        )
    }
}

private func extractEvictionPreview(from toolMessageContent: String) -> String? {
    guard let markerRange = toolMessageContent.range(of: "\nPreview:\n") else { return nil }
    return String(toolMessageContent[markerRange.upperBound...])
}

@Test("Colony evicts large tool results to /large_tool_results/{tool_call_id}")
func colonyEvictsLargeToolResultsToFilesystem() async throws {
    let graph = try ColonyAgent.compile()

    // Exceeds Deep Agents default eviction threshold (20k tokens ~= 80k chars).
    let largeOutput = String(repeating: "a", count: 120_000)
    let fs = ColonyInMemoryFileSystemBackend()

    let configuration = ColonyConfiguration(
        capabilities: [.filesystem],
        modelName: "test-model",
        toolApprovalPolicy: .never
    )
    let context = ColonyContext(configuration: configuration, filesystem: fs)

    let environment = SwarmGraphEnvironment<ColonySchema>(
        context: context,
        clock: NoopClock(),
        logger: NoopLogger(),
        model: SwarmAnyModelClient(BigToolModel()),
        tools: SwarmAnyToolRegistry(LargeOutputToolRegistry(output: largeOutput))
    )

    let runtime = try SwarmGraphRuntime(graph: graph, environment: environment)
    let handle = await runtime.run(
        threadID: SwarmThreadID("thread-evict"),
        input: "trigger",
        options: SwarmGraphRunOptions(checkpointPolicy: .disabled)
    )

    let outcome = try await handle.outcome.value
    guard case let .finished(output, _) = outcome, case let .fullStore(store) = output else {
        #expect(Bool(false))
        return
    }

    #expect((try store.get(ColonySchema.Channels.finalAnswer)) == "done")

    let persisted = try await fs.read(at: try ColonyVirtualPath("/large_tool_results/evict-1"))
    #expect(persisted == largeOutput)

    let messages = try store.get(ColonySchema.Channels.messages)
    let toolMessage = messages.first { $0.role == SwarmChatRole.tool && $0.toolCallID == "evict-1" }
    #expect(toolMessage != nil)
    #expect(toolMessage?.content.contains("/large_tool_results/evict-1") == true)
    #expect(toolMessage?.content.localizedCaseInsensitiveContains("result too large") == true)
}

@Test("Colony caps tool eviction preview by toolResultEvictionTokenLimit budget")
func colonyCapsToolEvictionPreviewByBudget() async throws {
    let graph = try ColonyAgent.compile()

    let head = "HEAD-START:"
    let tail = ":TAIL-END"
    let largeOutput = head + String(repeating: "a", count: 20_000) + tail
    let fs = ColonyInMemoryFileSystemBackend()

    let evictionTokenLimit = 700
    let charsPerToken = 4
    let previewCharBudget = evictionTokenLimit * charsPerToken

    let configuration = ColonyConfiguration(
        capabilities: [.filesystem],
        modelName: "test-model",
        toolApprovalPolicy: .never,
        toolResultEvictionTokenLimit: evictionTokenLimit
    )
    let context = ColonyContext(configuration: configuration, filesystem: fs)

    let environment = SwarmGraphEnvironment<ColonySchema>(
        context: context,
        clock: NoopClock(),
        logger: NoopLogger(),
        model: SwarmAnyModelClient(BigToolModel()),
        tools: SwarmAnyToolRegistry(LargeOutputToolRegistry(output: largeOutput))
    )

    let runtime = try SwarmGraphRuntime(graph: graph, environment: environment)
    let handle = await runtime.run(
        threadID: SwarmThreadID("thread-evict-preview-budget"),
        input: "trigger",
        options: SwarmGraphRunOptions(checkpointPolicy: .disabled)
    )

    let outcome = try await handle.outcome.value
    guard case let .finished(output, _) = outcome, case let .fullStore(store) = output else {
        #expect(Bool(false))
        return
    }

    let messages = try store.get(ColonySchema.Channels.messages)
    guard let toolMessage = messages.first(where: { $0.role == .tool && $0.toolCallID == "evict-1" }) else {
        #expect(Bool(false))
        return
    }

    guard let preview = extractEvictionPreview(from: toolMessage.content) else {
        #expect(Bool(false))
        return
    }

    #expect(preview.isEmpty == false)
    #expect(preview.count <= previewCharBudget)
    #expect(preview.contains(head) == true)
}

@Test("Colony tool eviction preview trimming is deterministic under the same budget")
func colonyToolEvictionPreviewTrimming_isDeterministic() async throws {
    let head = "HEAD-START:"
    let largeOutput = head + String(repeating: "a", count: 20_000)
    let evictionTokenLimit = 700

    func runOnce(threadID: String) async throws -> String {
        let graph = try ColonyAgent.compile()
        let fs = ColonyInMemoryFileSystemBackend()

        let configuration = ColonyConfiguration(
            capabilities: [.filesystem],
            modelName: "test-model",
            toolApprovalPolicy: .never,
            toolResultEvictionTokenLimit: evictionTokenLimit
        )
        let context = ColonyContext(configuration: configuration, filesystem: fs)

        let environment = SwarmGraphEnvironment<ColonySchema>(
            context: context,
            clock: NoopClock(),
            logger: NoopLogger(),
            model: SwarmAnyModelClient(BigToolModel()),
            tools: SwarmAnyToolRegistry(LargeOutputToolRegistry(output: largeOutput))
        )

        let runtime = try SwarmGraphRuntime(graph: graph, environment: environment)
        let handle = await runtime.run(
            threadID: SwarmThreadID(threadID),
            input: "trigger",
            options: SwarmGraphRunOptions(checkpointPolicy: .disabled)
        )

        let outcome = try await handle.outcome.value
        guard case let .finished(output, _) = outcome, case let .fullStore(store) = output else {
            throw ColonyFileSystemError.ioError("Missing full store output.")
        }

        let messages = try store.get(ColonySchema.Channels.messages)
        guard let toolMessage = messages.first(where: { $0.role == .tool && $0.toolCallID == "evict-1" }) else {
            throw ColonyFileSystemError.ioError("Missing evicted tool message.")
        }

        guard let preview = extractEvictionPreview(from: toolMessage.content) else {
            throw ColonyFileSystemError.ioError("Missing Preview: section.")
        }

        return preview
    }

    let preview1 = try await runOnce(threadID: "thread-evict-preview-deterministic-1")
    let preview2 = try await runOnce(threadID: "thread-evict-preview-deterministic-2")
    #expect(preview1 == preview2)
}
