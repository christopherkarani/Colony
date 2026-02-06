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

private struct LargeOutputToolRegistry: HiveToolRegistry, Sendable {
    let output: String

    func listTools() -> [HiveToolDefinition] {
        [
            HiveToolDefinition(
                name: "big_tool",
                description: "Returns a very large tool result.",
                parametersJSONSchema: #"{"type":"object","properties":{}}"#
            )
        ]
    }

    func invoke(_ call: HiveToolCall) async throws -> HiveToolResult {
        HiveToolResult(toolCallID: call.id, content: output)
    }
}

private final class BigToolModel: HiveModelClient, @unchecked Sendable {
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
                id: "evict-1",
                name: "big_tool",
                argumentsJSON: #"{}"#
            )
            return HiveChatResponse(
                message: HiveChatMessage(id: "assistant", role: .assistant, content: "running big tool", toolCalls: [call])
            )
        }

        return HiveChatResponse(
            message: HiveChatMessage(id: "assistant", role: .assistant, content: "done")
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

    let environment = HiveEnvironment<ColonySchema>(
        context: context,
        clock: NoopClock(),
        logger: NoopLogger(),
        model: AnyHiveModelClient(BigToolModel()),
        tools: AnyHiveToolRegistry(LargeOutputToolRegistry(output: largeOutput))
    )

    let runtime = HiveRuntime(graph: graph, environment: environment)
    let handle = await runtime.run(
        threadID: HiveThreadID("thread-evict"),
        input: "trigger",
        options: HiveRunOptions(checkpointPolicy: .disabled)
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
    let toolMessage = messages.first { $0.role == HiveChatRole.tool && $0.toolCallID == "evict-1" }
    #expect(toolMessage != nil)
    #expect(toolMessage?.content.contains("/large_tool_results/evict-1") == true)
    #expect(toolMessage?.content.contains("Tool result too large") == true)
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

    let environment = HiveEnvironment<ColonySchema>(
        context: context,
        clock: NoopClock(),
        logger: NoopLogger(),
        model: AnyHiveModelClient(BigToolModel()),
        tools: AnyHiveToolRegistry(LargeOutputToolRegistry(output: largeOutput))
    )

    let runtime = HiveRuntime(graph: graph, environment: environment)
    let handle = await runtime.run(
        threadID: HiveThreadID("thread-evict-preview-budget"),
        input: "trigger",
        options: HiveRunOptions(checkpointPolicy: .disabled)
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
