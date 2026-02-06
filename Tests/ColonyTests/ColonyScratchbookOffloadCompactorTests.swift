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

private final class ConstantModel: HiveModelClient, @unchecked Sendable {
    func complete(_ request: HiveChatRequest) async throws -> HiveChatResponse {
        try await streamFinal(request)
    }

    func stream(_ request: HiveChatRequest) -> AsyncThrowingStream<HiveChatStreamChunk, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(
                .final(HiveChatResponse(message: HiveChatMessage(id: "assistant", role: .assistant, content: "ok")))
            )
            continuation.finish()
        }
    }
}

private actor RecordingSubagentRegistry: ColonySubagentRegistry {
    nonisolated let subagents: [ColonySubagentDescriptor]
    nonisolated let runImpl: @Sendable (ColonySubagentRequest) async throws -> ColonySubagentResult

    private var requests: [ColonySubagentRequest] = []

    init(
        subagents: [ColonySubagentDescriptor],
        runImpl: @escaping @Sendable (ColonySubagentRequest) async throws -> ColonySubagentResult
    ) {
        self.subagents = subagents
        self.runImpl = runImpl
    }

    nonisolated func listSubagents() -> [ColonySubagentDescriptor] { subagents }

    func run(_ request: ColonySubagentRequest) async throws -> ColonySubagentResult {
        requests.append(request)
        return try await runImpl(request)
    }

    func recordedRequests() -> [ColonySubagentRequest] {
        requests
    }
}

private func scratchbookItems(from json: String) -> [[String: Any]]? {
    guard let data = json.data(using: .utf8) else { return nil }
    guard let object = try? JSONSerialization.jsonObject(with: data) else { return nil }
    guard let dict = object as? [String: Any] else { return nil }
    return dict["items"] as? [[String: Any]]
}

private func scratchbookContainsHistoryReference(_ json: String, historyPath: ColonyVirtualPath) -> Bool {
    guard let items = scratchbookItems(from: json) else { return false }
    for item in items {
        if let title = item["title"] as? String, title.contains(historyPath.rawValue) { return true }
        if let body = item["body"] as? String, body.contains(historyPath.rawValue) { return true }
    }
    return false
}

private func scratchbookContainsNextActions(_ json: String) -> Bool {
    guard let items = scratchbookItems(from: json) else { return false }

    let kinds = items.compactMap { $0["kind"] as? String }
    if kinds.contains(where: { $0 == "todo" || $0 == "task" }) { return true }

    let bodies = items.compactMap { $0["body"] as? String }
    return bodies.contains(where: { $0.localizedCaseInsensitiveContains("next action") })
}

private func runOffloadScenario(
    threadID: HiveThreadID,
    filesystem: ColonyInMemoryFileSystemBackend,
    configuration: ColonyConfiguration,
    subagents: (any ColonySubagentRegistry)?
) async throws {
    let graph = try ColonyAgent.compile()
    let context = ColonyContext(
        configuration: configuration,
        filesystem: filesystem,
        shell: nil,
        subagents: subagents
    )

    let environment = HiveEnvironment<ColonySchema>(
        context: context,
        clock: NoopClock(),
        logger: NoopLogger(),
        model: AnyHiveModelClient(ConstantModel())
    )

    let runtime = HiveRuntime(graph: graph, environment: environment)

    for i in 0..<5 {
        let input = "message-\(i): " + String(repeating: "x", count: 80)
        _ = try await runtime.run(
            threadID: threadID,
            input: input,
            options: HiveRunOptions(checkpointPolicy: .disabled)
        ).outcome.value
    }

    _ = try await runtime.run(
        threadID: threadID,
        input: "final",
        options: HiveRunOptions(checkpointPolicy: .disabled)
    ).outcome.value
}

@Test("History offload updates Scratchbook (deterministic fallback when subagents unavailable)")
func offload_updatesScratchbook_withDeterministicFallbackWhenSubagentsUnavailable() async throws {
    let threadID = HiveThreadID("thread-scratchbook-offload-fallback")
    let historyPath = try ColonyVirtualPath("/conversation_history/\(threadID.rawValue).md")
    let scratchbookPath = try ColonyVirtualPath("/scratchbook/\(threadID.rawValue).json")

    func makeConfiguration() throws -> ColonyConfiguration {
        var configuration = ColonyAgentFactory.configuration(profile: .onDevice4k, modelName: "test-model")
        configuration.toolApprovalPolicy = .never
        configuration.compactionPolicy = .disabled
        configuration.capabilities.remove(.subagents)
        configuration.summarizationPolicy = ColonySummarizationPolicy(
            triggerTokens: 100,
            keepLastMessages: 2,
            historyPathPrefix: try ColonyVirtualPath("/conversation_history")
        )
        return configuration
    }

    let fs1 = ColonyInMemoryFileSystemBackend()
    try await runOffloadScenario(
        threadID: threadID,
        filesystem: fs1,
        configuration: try makeConfiguration(),
        subagents: nil
    )

    let history1 = try await fs1.read(at: historyPath)
    #expect(history1.contains("message-0:") == true)

    let scratchbook1 = try await fs1.read(at: scratchbookPath)
    #expect(scratchbook1.isEmpty == false)
    #expect(scratchbookContainsHistoryReference(scratchbook1, historyPath: historyPath) == true)
    #expect(scratchbookContainsNextActions(scratchbook1) == true)

    let fs2 = ColonyInMemoryFileSystemBackend()
    try await runOffloadScenario(
        threadID: threadID,
        filesystem: fs2,
        configuration: try makeConfiguration(),
        subagents: nil
    )

    let scratchbook2 = try await fs2.read(at: scratchbookPath)
    #expect(scratchbook2 == scratchbook1)
}

@Test("History offload prefers compactor subagent for Scratchbook update when available")
func offload_prefersCompactorSubagentForScratchbookUpdate_whenAvailable() async throws {
    let threadID = HiveThreadID("thread-scratchbook-offload-compactor")
    let historyPath = try ColonyVirtualPath("/conversation_history/\(threadID.rawValue).md")
    let scratchbookPath = try ColonyVirtualPath("/scratchbook/\(threadID.rawValue).json")

    var configuration = ColonyAgentFactory.configuration(profile: .onDevice4k, modelName: "test-model")
    configuration.toolApprovalPolicy = .never
    configuration.compactionPolicy = .disabled
    configuration.summarizationPolicy = ColonySummarizationPolicy(
        triggerTokens: 100,
        keepLastMessages: 2,
        historyPathPrefix: try ColonyVirtualPath("/conversation_history")
    )

    let registry = RecordingSubagentRegistry(
        subagents: [ColonySubagentDescriptor(name: "compactor", description: "Scratchbook compactor.")],
        runImpl: { _ in ColonySubagentResult(content: "ok") }
    )

    let fs = ColonyInMemoryFileSystemBackend()
    try await runOffloadScenario(
        threadID: threadID,
        filesystem: fs,
        configuration: configuration,
        subagents: registry
    )

    let requests = await registry.recordedRequests()
    #expect(requests.contains(where: { $0.subagentType == "compactor" }) == true)
    #expect(requests.contains(where: { $0.prompt.contains(historyPath.rawValue) }) == true)

    let scratchbook = try await fs.read(at: scratchbookPath)
    #expect(scratchbook.isEmpty == false)
    #expect(scratchbookContainsHistoryReference(scratchbook, historyPath: historyPath) == true)
    #expect(scratchbookContainsNextActions(scratchbook) == true)
}
