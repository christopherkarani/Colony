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

private final class RecordingRequestModel: SwarmModelClient, @unchecked Sendable {
    private let lock = NSLock()
    private var requests: [SwarmChatRequest] = []

    func recordedRequests() -> [SwarmChatRequest] {
        lock.lock()
        defer { lock.unlock() }
        return requests
    }

    func complete(_ request: SwarmChatRequest) async throws -> SwarmChatResponse {
        try await streamFinal(request)
    }

    func stream(_ request: SwarmChatRequest) -> AsyncThrowingStream<SwarmChatStreamChunk, Error> {
        lock.lock()
        requests.append(request)
        lock.unlock()

        let response = SwarmChatResponse(
            message: SwarmChatMessage(id: "assistant", role: .assistant, content: "ok")
        )
        return AsyncThrowingStream { continuation in
            continuation.yield(.final(response))
            continuation.finish()
        }
    }
}

private struct FixedToolRegistry: SwarmToolRegistry, Sendable {
    let tools: [SwarmToolDefinition]

    func listTools() -> [SwarmToolDefinition] { tools }

    func invoke(_ call: SwarmToolCall) async throws -> SwarmToolResult {
        SwarmToolResult(toolCallID: call.id, content: "ok")
    }
}

private func encodeToolsAsSortedJSON(_ tools: [SwarmToolDefinition]) throws -> String {
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

    let baseTool = SwarmToolDefinition(
        name: "big_tool",
        description: "A tool with a (tiny) schema.",
        parametersJSONSchema: ""
    )
    let baseToolJSON = try encodeToolsAsSortedJSON([baseTool])
    let padding = (3 - (baseToolJSON.count % 4) + 4) % 4

    let tool = SwarmToolDefinition(
        name: "big_tool",
        description: "A tool with a (tiny) schema.",
        parametersJSONSchema: String(repeating: "a", count: padding)
    )
    let toolJSON = try encodeToolsAsSortedJSON([tool])
    #expect(toolJSON.count % 4 == 3)

    let toolTokenCount = tokenizer.countTokens([
        SwarmChatMessage(id: "budget:tools", role: .system, content: toolJSON)
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

    let environment = SwarmGraphEnvironment<ColonySchema>(
        context: context,
        clock: NoopClock(),
        logger: NoopLogger(),
        model: SwarmAnyModelClient(recordingModel),
        tools: SwarmAnyToolRegistry(FixedToolRegistry(tools: [tool]))
    )
    let runtime = try SwarmGraphRuntime(graph: graph, environment: environment)

    let handle = await runtime.run(
        threadID: SwarmThreadID("thread-request-hard-cap-tools-payload"),
        input: "hello",
        options: SwarmGraphRunOptions(checkpointPolicy: .disabled)
    )
    _ = try await handle.outcome.value

    guard let request = recordingModel.recordedRequests().last else {
        #expect(Bool(false))
        return
    }

    let toolsPayload = try encodeToolsAsSortedJSON(request.tools)
    let combined = tokenizer.countTokens(
        request.messages + [SwarmChatMessage(id: "budget:tools", role: .system, content: toolsPayload)]
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
        model: SwarmAnyModelClient(recordingModel),
        clock: NoopClock(),
        logger: NoopLogger(),
        filesystem: nil
    )

    // Keep under the cloud profile compaction threshold (~12k) so the user prompt is not dropped before budgeting.
    let prompt = String(repeating: "p", count: 20_000) // ~5k tokens via ColonyApproximateTokenizer
    _ = try await registry.run(ColonySubagentRequest(prompt: prompt, subagentType: .general))

    guard let request = recordingModel.recordedRequests().last else {
        #expect(Bool(false))
        return
    }

    let requestTokenCount = ColonyApproximateTokenizer().countTokens(request.messages)
    #expect(requestTokenCount <= 4_000)
}

