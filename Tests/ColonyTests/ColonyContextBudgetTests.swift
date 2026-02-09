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
    var tools: [HiveToolDefinition]

    func listTools() -> [HiveToolDefinition] { tools }

    func invoke(_ call: HiveToolCall) async throws -> HiveToolResult {
        HiveToolResult(toolCallID: call.id, content: "ok")
    }
}

@Test("Colony enforces strict request-level token cap before model invocation")
func contextBudget_enforcesStrictRequestLevelCap() async throws {
    let graph = try ColonyAgent.compile()
    let recordingModel = RecordingRequestModel()
    let hardCap = 220

    let configuration = ColonyConfiguration(
        capabilities: [],
        modelName: "test-model",
        toolApprovalPolicy: .never,
        compactionPolicy: .disabled,
        requestHardTokenLimit: hardCap
    )
    let context = ColonyContext(configuration: configuration, filesystem: nil, shell: nil, subagents: nil)

    let environment = HiveEnvironment<ColonySchema>(
        context: context,
        clock: NoopClock(),
        logger: NoopLogger(),
        model: AnyHiveModelClient(recordingModel)
    )
    let runtime = HiveRuntime(graph: graph, environment: environment)
    let threadID = HiveThreadID("thread-context-budget-hard-cap")

    for turn in 0..<6 {
        let input = "turn-\(turn): " + String(repeating: "a", count: 64)
        let handle = await runtime.run(
            threadID: threadID,
            input: input,
            options: HiveRunOptions(checkpointPolicy: .disabled)
        )
        _ = try await handle.outcome.value
    }

    guard let finalRequest = recordingModel.recordedRequests().last else {
        #expect(Bool(false))
        return
    }

    let requestTokenCount = ColonyApproximateTokenizer().countTokens(finalRequest.messages)
    #expect(requestTokenCount <= hardCap)
}

@Test("Colony trims oversized system prompt so request stays within strict cap")
func contextBudget_trimsOversizedSystemPromptToFitHardCap() async throws {
    let graph = try ColonyAgent.compile()
    let recordingModel = RecordingRequestModel()
    let hardCap = 90
    let oversizedAdditionalSystemPrompt = String(repeating: "s", count: 20_000)

    let configuration = ColonyConfiguration(
        capabilities: [],
        modelName: "test-model",
        toolApprovalPolicy: .never,
        compactionPolicy: .disabled,
        additionalSystemPrompt: oversizedAdditionalSystemPrompt,
        requestHardTokenLimit: hardCap
    )
    let context = ColonyContext(configuration: configuration, filesystem: nil, shell: nil, subagents: nil)

    let environment = HiveEnvironment<ColonySchema>(
        context: context,
        clock: NoopClock(),
        logger: NoopLogger(),
        model: AnyHiveModelClient(recordingModel)
    )
    let runtime = HiveRuntime(graph: graph, environment: environment)

    let handle = await runtime.run(
        threadID: HiveThreadID("thread-context-budget-system-overflow"),
        input: "hello",
        options: HiveRunOptions(checkpointPolicy: .disabled)
    )
    _ = try await handle.outcome.value

    guard let finalRequest = recordingModel.recordedRequests().last else {
        #expect(Bool(false))
        return
    }

    let requestTokenCount = ColonyApproximateTokenizer().countTokens(finalRequest.messages)
    #expect(requestTokenCount <= hardCap)

    guard let systemMessage = finalRequest.messages.first(where: { $0.role == .system }) else {
        #expect(Bool(false))
        return
    }

    let systemMessageTokenCount = ColonyApproximateTokenizer().countTokens([systemMessage])
    #expect(systemMessageTokenCount <= hardCap)
    #expect(systemMessage.content.count < oversizedAdditionalSystemPrompt.count)
}

@Test("Colony includes tool definition payload when enforcing strict request budget")
func contextBudget_includesToolDefinitionPayloadInHardCap() async throws {
    let graph = try ColonyAgent.compile()
    let recordingModel = RecordingRequestModel()
    let hardCap = 200

    let externalTools = AnyHiveToolRegistry(
        FixedToolRegistry(
            tools: [
                HiveToolDefinition(
                    name: "big_tool",
                    description: String(repeating: "d", count: 256),
                    parametersJSONSchema: String(repeating: "s", count: 256)
                )
            ]
        )
    )

    let configuration = ColonyConfiguration(
        capabilities: [],
        modelName: "test-model",
        toolApprovalPolicy: .never,
        compactionPolicy: .disabled,
        requestHardTokenLimit: hardCap
    )
    let context = ColonyContext(configuration: configuration, filesystem: nil, shell: nil, subagents: nil)

    let environment = HiveEnvironment<ColonySchema>(
        context: context,
        clock: NoopClock(),
        logger: NoopLogger(),
        model: AnyHiveModelClient(recordingModel),
        tools: externalTools
    )
    let runtime = HiveRuntime(graph: graph, environment: environment)

    let handle = await runtime.run(
        threadID: HiveThreadID("thread-context-budget-tools"),
        input: "hi",
        options: HiveRunOptions(checkpointPolicy: .disabled)
    )
    _ = try await handle.outcome.value

    guard let finalRequest = recordingModel.recordedRequests().last else {
        #expect(Bool(false))
        return
    }

    let messagesTokenCount = ColonyApproximateTokenizer().countTokens(finalRequest.messages)
    let toolsTokenCount = approximateToolTokens(finalRequest.tools)
    #expect((messagesTokenCount + toolsTokenCount) <= hardCap)
}

@Test("Colony trims oldest messages first while preserving newest messages under strict request budget")
func contextBudget_trimsOldestFirstAndPreservesNewestMessages() async throws {
    let graph = try ColonyAgent.compile()
    let recordingModel = RecordingRequestModel()
    let hardCap = 200

    let configuration = ColonyConfiguration(
        capabilities: [],
        modelName: "test-model",
        toolApprovalPolicy: .never,
        compactionPolicy: .disabled,
        requestHardTokenLimit: hardCap
    )
    let context = ColonyContext(configuration: configuration, filesystem: nil, shell: nil, subagents: nil)

    let environment = HiveEnvironment<ColonySchema>(
        context: context,
        clock: NoopClock(),
        logger: NoopLogger(),
        model: AnyHiveModelClient(recordingModel)
    )
    let runtime = HiveRuntime(graph: graph, environment: environment)
    let threadID = HiveThreadID("thread-context-budget-recency")

    for turn in 0..<10 {
        let marker = String(format: "turn-%02d", turn)
        let input = marker + " " + String(repeating: "b", count: 44)
        let handle = await runtime.run(
            threadID: threadID,
            input: input,
            options: HiveRunOptions(checkpointPolicy: .disabled)
        )
        _ = try await handle.outcome.value
    }

    guard let finalRequest = recordingModel.recordedRequests().last else {
        #expect(Bool(false))
        return
    }

    let requestTokenCount = ColonyApproximateTokenizer().countTokens(finalRequest.messages)
    let allContent = finalRequest.messages.map(\.content).joined(separator: "\n")

    #expect(requestTokenCount <= hardCap)
    #expect(allContent.contains("turn-00") == false)
    #expect(allContent.contains("turn-01") == false)
    #expect(allContent.contains("turn-08") == true)
    #expect(allContent.contains("turn-09") == true)
}

@Test("Colony on-device profile wires a default hard 4k request cap")
func contextBudget_onDeviceProfileDefaultsToHard4kRequestBudget() async throws {
    let recordingModel = RecordingRequestModel()
    let factory = ColonyAgentFactory()
    let onDeviceConfiguration = ColonyAgentFactory.configuration(profile: .onDevice4k, modelName: "test-model")
    #expect(onDeviceConfiguration.requestHardTokenLimit == 4_000)

    let runtime = try factory.makeRuntime(
        profile: .onDevice4k,
        threadID: HiveThreadID("thread-context-budget-on-device-4k"),
        modelName: "test-model",
        model: AnyHiveModelClient(recordingModel),
        configure: { configuration in
            configuration.toolApprovalPolicy = .never
            configuration.additionalSystemPrompt = String(repeating: "m", count: 8_000)
        }
    )

    for turn in 0..<12 {
        let input = "on-device-\(turn): " + String(repeating: "z", count: 700)
        let handle = await runtime.runControl.start(.init(input: input))
        _ = try await handle.outcome.value
    }

    guard let finalRequest = recordingModel.recordedRequests().last else {
        #expect(Bool(false))
        return
    }

    let requestTokenCount = ColonyApproximateTokenizer().countTokens(finalRequest.messages)
    #expect(requestTokenCount <= 4_000)
}

@Test("Colony cloud profile leaves request hard cap unbounded by default")
func contextBudget_cloudProfileDefaultsToUnboundedRequestBudget() {
    let cloudConfiguration = ColonyAgentFactory.configuration(profile: .cloud, modelName: "test-model")
    #expect(cloudConfiguration.requestHardTokenLimit == nil)
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
