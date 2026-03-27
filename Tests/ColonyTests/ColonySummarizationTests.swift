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

private final class ConstantModel: SwarmModelClient, @unchecked Sendable {
    func complete(_ request: SwarmChatRequest) async throws -> SwarmChatResponse {
        try await streamFinal(request)
    }

    func stream(_ request: SwarmChatRequest) -> AsyncThrowingStream<SwarmChatStreamChunk, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(
                .final(SwarmChatResponse(message: SwarmChatMessage(id: "assistant", role: .assistant, content: "ok")))
            )
            continuation.finish()
        }
    }
}

@Test("Colony summarizes long conversations and offloads history to /conversation_history/{thread}.md")
func colonySummarizationOffloadsHistory() async throws {
    let graph = try ColonyAgent.compile()
    let fs = ColonyInMemoryFileSystemBackend()

    var configuration = ColonyConfiguration(
        capabilities: [.filesystem],
        modelName: "test-model",
        toolApprovalPolicy: .never,
        compactionPolicy: .disabled
    )
    configuration.summarizationPolicy = ColonySummarizationPolicy(
        triggerTokens: 100,
        keepLastMessages: 2,
        historyPathPrefix: try ColonyVirtualPath("/conversation_history")
    )

    let context = ColonyContext(configuration: configuration, filesystem: fs)
    let environment = SwarmGraphEnvironment<ColonySchema>(
        context: context,
        clock: NoopClock(),
        logger: NoopLogger(),
        model: SwarmAnyModelClient(ConstantModel())
    )

    let runtime = try SwarmGraphRuntime(graph: graph, environment: environment)
    let threadID = SwarmThreadID("thread-summarize")

    // Build up enough history to trigger summarization.
    for i in 0..<5 {
        let input = "message-\(i): " + String(repeating: "x", count: 80)
        _ = try await runtime.run(
            threadID: threadID,
            input: input,
            options: SwarmGraphRunOptions(checkpointPolicy: .disabled)
        ).outcome.value
    }

    let latest = await runtime.run(
        threadID: threadID,
        input: "final",
        options: SwarmGraphRunOptions(checkpointPolicy: .disabled)
    )

    let outcome = try await latest.outcome.value
    guard case let .finished(output, _) = outcome, case let .fullStore(store) = output else {
        #expect(Bool(false))
        return
    }

    // History file exists and contains prior messages.
    let history = try await fs.read(at: try ColonyVirtualPath("/conversation_history/thread-summarize.md"))
    #expect(history.contains("message-0:") == true)

    // In-context messages contain a summary marker and file reference.
    let messages = try store.get(ColonySchema.Channels.messages)
    let summaryMessage = messages.first { $0.content.contains("/conversation_history/thread-summarize.md") }
    #expect(summaryMessage != nil)
    #expect(summaryMessage?.content.contains("/conversation_history/thread-summarize.md") == true)
}
