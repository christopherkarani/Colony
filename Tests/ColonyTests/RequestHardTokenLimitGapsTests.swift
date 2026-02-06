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

private final class RecordingRequestModel: HiveModelClient, @unchecked Sendable {
    private let lock = NSLock()
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

        let response = HiveChatResponse(
            message: HiveChatMessage(id: "assistant", role: .assistant, content: "ok")
        )
        return AsyncThrowingStream { continuation in
            continuation.yield(.final(response))
            continuation.finish()
        }
    }
}

private struct FixedToolRegistry: HiveToolRegistry, Sendable {
    let tools: [HiveToolDefinition]

    func listTools() -> [HiveToolDefinition] { tools }

    func invoke(_ call: HiveToolCall) async throws -> HiveToolResult {
        HiveToolResult(toolCallID: call.id, content: "ok")
    }
}

private func encodeToolsAsSortedJSON(_ tools: [HiveToolDefinition]) throws -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let data = try encoder.encode(tools)
    return String(decoding: data, as: UTF8.self)
}

@Test("requestHardTokenLimit must account for tool definition payload size")
func requestHardTokenLimit_accountsForToolDefinitionPayloadSize() async throws {
    let graph = try ColonyAgent.compile()
    let recordingModel = RecordingRequestModel()
    let tokenizer = ColonyApproximateTokenizer()

    let baseTool = HiveToolDefinition(
        name: "big_tool",
        description: "A tool with a (tiny) schema.",
        parametersJSONSchema: ""
    )
    let baseToolJSON = try encodeToolsAsSortedJSON([baseTool])
    let padding = (3 - (baseToolJSON.count % 4) + 4) % 4

    let tool = HiveToolDefinition(
        name: "big_tool",
        description: "A tool with a (tiny) schema.",
        parametersJSONSchema: String(repeating: "a", count: padding)
    )
    let toolJSON = try encodeToolsAsSortedJSON([tool])
    #expect(toolJSON.count % 4 == 3)

    let toolTokenCount = tokenizer.countTokens([
        HiveChatMessage(id: "budget:tools", role: .system, content: toolJSON)
    ])
    let messageTokenLimit = 150
    let hardCap = toolTokenCount + messageTokenLimit

    let configuration = ColonyConfiguration(
        capabilities: [],
        modelName: "test-model",
        toolApprovalPolicy: .never,
        compactionPolicy: .maxTokens(0),
        additionalSystemPrompt: String(repeating: "x", count: 20_000),
        requestHardTokenLimit: hardCap
    )
    let context = ColonyContext(
        configuration: configuration,
        filesystem: nil,
        shell: nil,
        subagents: nil,
        tokenizer: tokenizer
    )

    let environment = HiveEnvironment<ColonySchema>(
        context: context,
        clock: NoopClock(),
        logger: NoopLogger(),
        model: AnyHiveModelClient(recordingModel),
        tools: AnyHiveToolRegistry(FixedToolRegistry(tools: [tool]))
    )
    let runtime = HiveRuntime(graph: graph, environment: environment)

    let handle = await runtime.run(
        threadID: HiveThreadID("thread-request-hard-cap-tools-payload"),
        input: "hello",
        options: HiveRunOptions(checkpointPolicy: .disabled)
    )
    _ = try await handle.outcome.value

    guard let request = recordingModel.recordedRequests().last else {
        #expect(Bool(false))
        return
    }

    let toolsPayload = try encodeToolsAsSortedJSON(request.tools)
    let combined = tokenizer.countTokens(
        request.messages + [HiveChatMessage(id: "budget:tools", role: .system, content: toolsPayload)]
    )

    // NOTE: This must hold for strict request-level capping; today the budget math can undercount by ~1 token.
    #expect(combined <= hardCap)
}

@Test("Default subagent runtime must inherit on-device 4k requestHardTokenLimit")
func defaultSubagentRuntime_inheritsOnDeviceHard4kRequestCap() async throws {
    let recordingModel = RecordingRequestModel()

    // NOTE: This initializer is the "default" path; it should be safe for on-device usage.
    let registry = ColonyDefaultSubagentRegistry(
        modelName: "test-subagent-model",
        model: AnyHiveModelClient(recordingModel),
        clock: NoopClock(),
        logger: NoopLogger(),
        filesystem: nil
    )

    // Keep under the cloud profile compaction threshold (~12k) so the user prompt is not dropped before budgeting.
    let prompt = String(repeating: "p", count: 20_000) // ~5k tokens via ColonyApproximateTokenizer
    _ = try await registry.run(ColonySubagentRequest(prompt: prompt, subagentType: "general-purpose"))

    guard let request = recordingModel.recordedRequests().last else {
        #expect(Bool(false))
        return
    }

    let requestTokenCount = ColonyApproximateTokenizer().countTokens(request.messages)
    #expect(requestTokenCount <= 4_000)
}

