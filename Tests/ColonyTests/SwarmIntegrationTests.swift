import ColonyCore
import ColonySwarmInterop
import Foundation
import HiveCore
import Swarm
import Testing
@testable import Colony

// MARK: - Test Helpers

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

/// A scripted model that calls a named tool on the first invocation,
/// then produces a final answer on the second.
private final class SwarmToolCallingModel: HiveModelClient, @unchecked Sendable {
    private let lock = NSLock()
    private var callCount: Int = 0
    private let toolName: String
    private let toolArgs: String

    init(toolName: String, toolArgs: String) {
        self.toolName = toolName
        self.toolArgs = toolArgs
    }

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
                id: "swarm-call-1",
                name: toolName,
                argumentsJSON: toolArgs
            )
            return HiveChatResponse(
                message: HiveChatMessage(id: "assistant", role: .assistant, content: "calling tool", toolCalls: [call])
            )
        }

        return HiveChatResponse(
            message: HiveChatMessage(id: "assistant", role: .assistant, content: "done with swarm tool")
        )
    }
}

/// Captures tool definitions seen by model requests for advertisement assertions.
private final class ToolCaptureModel: HiveModelClient, @unchecked Sendable {
    private let lock = NSLock()
    private var lastSeenToolNames: [String] = []

    func complete(_ request: HiveChatRequest) async throws -> HiveChatResponse {
        recordTools(from: request)
        return HiveChatResponse(
            message: HiveChatMessage(id: "assistant", role: .assistant, content: "done")
        )
    }

    func stream(_ request: HiveChatRequest) -> AsyncThrowingStream<HiveChatStreamChunk, Error> {
        recordTools(from: request)
        return AsyncThrowingStream { continuation in
            continuation.yield(.final(HiveChatResponse(
                message: HiveChatMessage(id: "assistant", role: .assistant, content: "done")
            )))
            continuation.finish()
        }
    }

    func seenToolNames() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return lastSeenToolNames
    }

    private func recordTools(from request: HiveChatRequest) {
        lock.lock()
        lastSeenToolNames = request.tools.map(\.name)
        lock.unlock()
    }
}

/// A simple Swarm tool for testing. Implements AnyJSONTool manually
/// (the @Tool macro would generate this in real code).
private struct EchoTool: AnyJSONTool {
    var name: String { "echo" }
    var description: String { "Echoes the input message back" }
    var parameters: [ToolParameter] {
        [
            ToolParameter(
                name: "message",
                description: "The message to echo",
                type: .string,
                isRequired: true
            ),
        ]
    }

    func execute(arguments: [String: SendableValue]) async throws -> SendableValue {
        guard case let .string(message) = arguments["message"] else {
            return .string("Error: missing message argument")
        }
        return .string("Echo: \(message)")
    }
}

private struct ApprovalMetadataEchoTool: AnyJSONTool {
    var name: String { "approval_echo" }
    var description: String { "Echoes input but always requires explicit approval." }
    var parameters: [ToolParameter] {
        [
            ToolParameter(
                name: "message",
                description: "The message to echo",
                type: .string,
                isRequired: true
            ),
        ]
    }
    var executionSemantics: ToolExecutionSemantics {
        ToolExecutionSemantics(
            sideEffectLevel: .readOnly,
            retryPolicy: .callerManaged,
            approvalRequirement: .always,
            resultDurability: .externalReference
        )
    }

    func execute(arguments: [String: SendableValue]) async throws -> SendableValue {
        .string("Approval Echo: \(arguments["message"]?.stringValue ?? "")")
    }
}

private actor ContextOnlyMemory: Memory {
    let fallbackContext: String

    init(fallbackContext: String) {
        self.fallbackContext = fallbackContext
    }

    var count: Int {
        get async { 0 }
    }

    var isEmpty: Bool {
        get async { true }
    }

    func add(_ message: MemoryMessage) async {}

    func context(for query: String, tokenLimit: Int) async -> String {
        guard !query.isEmpty, tokenLimit > 0 else { return "" }
        return fallbackContext
    }

    func allMessages() async -> [MemoryMessage] { [] }

    func clear() async {}
}

// MARK: - ColonySwarmToolBridge Tests

@Test("ColonySwarmToolBridge converts Swarm tools to HiveToolDefinitions")
func swarmToolBridgeListsTools() throws {
    let bridge = try ColonySwarmToolBridge(
        tools: [EchoTool()],
        capability: .plugins,
        riskLevel: .readOnly
    )

    let definitions = bridge.listTools()
    #expect(definitions.count == 1)
    #expect(definitions.first?.name == "echo")
    #expect(definitions.first?.description == "Echoes the input message back")
}

@Test("ColonySwarmToolBridge filters tools by capability")
func swarmToolBridgeFiltersCapabilities() throws {
    let bridge = try ColonySwarmToolBridge(registrations: [
        ColonySwarmToolRegistration(tool: EchoTool(), capability: .webSearch, riskLevel: .network),
    ])

    // webSearch capability not enabled — should return empty
    let noMatch = bridge.listTools(filteredBy: [.filesystem, .planning])
    #expect(noMatch.isEmpty)

    // webSearch capability enabled — should return the tool
    let withMatch = bridge.listTools(filteredBy: [.webSearch])
    #expect(withMatch.count == 1)
    #expect(withMatch.first?.name == "echo")
}

@Test("ColonyAgentFactory applies capability filtering to Swarm tool advertisements")
func colonyFactoryFiltersSwarmToolAdvertisements() async throws {
    let bridge = try ColonySwarmToolBridge(
        tools: [EchoTool()],
        capability: .plugins,
        riskLevel: .readOnly
    )
    let captureModel = ToolCaptureModel()

    let runtime = try ColonyAgentFactory().makeRuntime(
        profile: .cloud,
        modelName: "test-model",
        model: AnyHiveModelClient(captureModel),
        swarmTools: bridge,
        filesystem: ColonyInMemoryFileSystemBackend(),
        configure: { configuration in
            configuration.model.capabilities.remove(.plugins)
        }
    )

    let handle = await runtime.sendUserMessage("hello")
    _ = try await handle.outcome.value

    let seenNames = captureModel.seenToolNames()
    #expect(seenNames.contains("echo") == false)
}

@Test("ColonyAgentFactory advertises Swarm tools by default when capability is provided by bridge")
func colonyFactoryAdvertisesSwarmToolAdvertisementsByDefault() async throws {
    let bridge = try ColonySwarmToolBridge(
        tools: [EchoTool()],
        capability: .plugins,
        riskLevel: .readOnly
    )
    let captureModel = ToolCaptureModel()

    let runtime = try ColonyAgentFactory().makeRuntime(
        profile: .cloud,
        modelName: "test-model",
        model: AnyHiveModelClient(captureModel),
        swarmTools: bridge,
        filesystem: ColonyInMemoryFileSystemBackend()
    )

    let handle = await runtime.sendUserMessage("hello")
    _ = try await handle.outcome.value

    let seenNames = captureModel.seenToolNames()
    #expect(seenNames.contains("echo"))
}

@Test("ColonySwarmToolBridge invokes tool and returns result")
func swarmToolBridgeInvokesTool() async throws {
    let bridge = try ColonySwarmToolBridge(
        tools: [EchoTool()],
        capability: .plugins,
        riskLevel: .readOnly
    )

    let call = ColonyToolCall(id: "test-1", name: "echo", argumentsJSON: #"{"message":"hello world"}"#)
    let result = try await bridge.invoke(call)
    #expect(result.content.contains("Echo: hello world"))
}

@Test("ColonySwarmToolBridge risk-level overrides are populated")
func swarmToolBridgeRiskLevels() throws {
    let bridge = try ColonySwarmToolBridge(registrations: [
        ColonySwarmToolRegistration(tool: EchoTool(), capability: .plugins, riskLevel: .network),
    ])

    #expect(bridge.riskLevelOverrides["echo"] == .network)
}

@Test("ColonySwarmToolBridge derives Colony policy metadata from Swarm tool semantics")
func swarmToolBridgeDerivesPolicyMetadataFromExecutionSemantics() throws {
    let bridge = try ColonySwarmToolBridge(
        tools: [ApprovalMetadataEchoTool()],
        capability: .plugins,
        riskLevel: .readOnly
    )

    let metadata = bridge.toolPolicyMetadataByName["approval_echo"]
    #expect(metadata?.riskLevel == .readOnly)
    #expect(metadata?.approvalDisposition == .always)
    #expect(metadata?.retryDisposition == .approvalGated)
    #expect(metadata?.resultDurability == .durable)
}

private struct PrimaryEchoRegistry: HiveToolRegistry, Sendable {
    func listTools() -> [HiveToolDefinition] {
        [
            HiveToolDefinition(
                name: "echo",
                description: "Primary echo implementation",
                parametersJSONSchema: #"{"type":"object","properties":{"message":{"type":"string"}},"required":["message"],"additionalProperties":false}"#
            )
        ]
    }

    func invoke(_ call: HiveToolCall) async throws -> HiveToolResult {
        HiveToolResult(toolCallID: call.id, content: "primary-echo")
    }
}

@Test("CompositeToolRegistry keeps listing and invocation precedence aligned")
func compositeToolRegistryPrecedenceIsAligned() async throws {
    let bridge = try ColonySwarmToolBridge(
        tools: [EchoTool()],
        capability: .plugins,
        riskLevel: .readOnly
    )
    let composite = CompositeToolRegistry(
        primary: AnyHiveToolRegistry(PrimaryEchoRegistry()),
        secondary: AnyHiveToolRegistry(ColonyHiveToolRegistryAdapter(base: bridge))
    )

    var dedupedByName: [String: HiveToolDefinition] = [:]
    for definition in composite.listTools() {
        dedupedByName[definition.name] = definition
    }

    #expect(dedupedByName["echo"]?.description == "Primary echo implementation")

    let result = try await composite.invoke(
        HiveToolCall(id: "composite-echo", name: "echo", argumentsJSON: #"{"message":"hello"}"#)
    )
    #expect(result.content == "primary-echo")
}

// MARK: - ColonySwarmMemoryAdapter Tests

@Test("ColonySwarmMemoryAdapter remembers and recalls")
func swarmMemoryAdapterRoundTrip() async throws {
    let adapter = ColonySwarmMemoryAdapter(
        backend: InMemoryBackend(),
        conversationID: "test-roundtrip"
    )

    let rememberResult = try await adapter.remember(
        ColonyMemoryRememberRequest(content: "Swift is a programming language", tags: ["lang"])
    )
    #expect(UUID(uuidString: rememberResult.id) != nil)

    let recallResult = try await adapter.recall(
        ColonyMemoryRecallRequest(query: "Swift programming", limit: 5)
    )
    #expect(!recallResult.items.isEmpty)
    #expect(recallResult.items.first?.content.contains("Swift") == true)
    #expect(recallResult.items.first?.tags == ["lang"])
}

@Test("ColonySwarmMemoryAdapter returns empty on no match")
func swarmMemoryAdapterEmptyRecall() async throws {
    let adapter = ColonySwarmMemoryAdapter(
        backend: InMemoryBackend(),
        conversationID: "test-empty"
    )

    _ = try await adapter.remember(
        ColonyMemoryRememberRequest(content: "iOS and macOS development")
    )

    let result = try await adapter.recall(
        ColonyMemoryRecallRequest(query: "nonexistent topic", limit: 5)
    )
    #expect(result.items.isEmpty)
}

@Test("ColonySwarmMemoryAdapter falls back to contextual recall when memory has no local messages")
func swarmMemoryAdapterFallsBackToContextWhenMessagesUnavailable() async throws {
    let adapter = ColonySwarmMemoryAdapter(
        ContextOnlyMemory(fallbackContext: "[assistant]: Wax fallback context")
    )

    let result = try await adapter.recall(
        ColonyMemoryRecallRequest(query: "wax fallback", limit: 3)
    )

    #expect(result.items.count == 1)
    #expect(result.items.first?.content == "[assistant]: Wax fallback context")
    #expect(result.items.first?.metadata["source"] == "swarm-memory")
}

// MARK: - ColonySwarmSubagentAdapter Tests

private actor StubAgent: AgentRuntime {
    nonisolated let tools: [any AnyJSONTool] = []
    nonisolated let instructions: String = "Test agent"
    nonisolated let configuration: AgentConfiguration = .default

    func run(_ input: String, session: (any Session)? = nil, observer: (any AgentObserver)? = nil) async throws -> AgentResult {
        AgentResult(output: "Handled: \(input)")
    }

    nonisolated func stream(_ input: String, session: (any Session)? = nil, observer: (any AgentObserver)? = nil) -> AsyncThrowingStream<AgentEvent, Error> {
        AsyncThrowingStream { $0.finish() }
    }

    func cancel() async {}
}

@Test("ColonySwarmSubagentAdapter lists registered agents")
func swarmSubagentAdapterListsAgents() {
    let adapter = ColonySwarmSubagentAdapter(agents: [
        ("researcher", StubAgent(), "Research specialist"),
        ("coder", StubAgent(), "Coding specialist"),
    ])

    let descriptors = adapter.listSubagents()
    #expect(descriptors.count == 2)
    #expect(descriptors.map(\.name).contains("researcher"))
    #expect(descriptors.map(\.name).contains("coder"))
}

@Test("ColonySwarmSubagentAdapter routes to named agent")
func swarmSubagentAdapterRoutesToAgent() async throws {
    let adapter = ColonySwarmSubagentAdapter(agents: [
        ("researcher", StubAgent(), "Research specialist"),
    ])

    let result = try await adapter.run(
        ColonySubagentRequest(prompt: "Find iOS benchmarks", subagentType: "researcher")
    )
    #expect(result.content.contains("Handled: Find iOS benchmarks"))
}

// MARK: - End-to-End: Swarm tool through Colony's pipeline

@Test("Swarm tool executes through Colony's harness with capability gating")
func swarmToolThroughColonyPipeline() async throws {
    let echoTool = EchoTool()
    let bridge = try ColonySwarmToolBridge(
        tools: [echoTool],
        capability: .plugins,
        riskLevel: .readOnly
    )

    let graph = try ColonyAgent.compile()
    let fs = ColonyInMemoryFileSystemBackend()

    var configuration = ColonyConfiguration(
        modelName: "test-model",
        capabilities: [.plugins],
        toolApprovalPolicy: .never
    )
    // Merge risk-level overrides from bridge
    for (name, level) in bridge.riskLevelOverrides {
        configuration.safety.toolRiskLevelOverrides[name] = level
    }

    let context = ColonyContext(configuration: configuration, filesystem: fs)
    let checkpointStore = InMemoryCheckpointStore<ColonySchema>()

    let model = SwarmToolCallingModel(
        toolName: "echo",
        toolArgs: #"{"message":"integration test"}"#
    )

    let environment = HiveEnvironment<ColonySchema>(
        context: context,
        clock: NoopClock(),
        logger: NoopLogger(),
        model: AnyHiveModelClient(model),
        tools: AnyHiveToolRegistry(ColonyHiveToolRegistryAdapter(base: bridge)),
        checkpointStore: AnyHiveCheckpointStore(checkpointStore)
    )

    let runtime = try HiveRuntime(graph: graph, environment: environment)
    let threadID = HiveThreadID("swarm-integration-test")

    let handle = await runtime.run(
        threadID: threadID,
        input: "Please echo integration test",
        options: HiveRunOptions(checkpointPolicy: .disabled)
    )

    let outcome = try await handle.outcome.value
    guard case let .finished(output, _) = outcome else {
        #expect(Bool(false), "Expected finished outcome")
        return
    }

    guard case let .fullStore(store) = output else {
        #expect(Bool(false), "Expected full store output")
        return
    }

    // The model should have produced a final answer after the tool was executed.
    let finalAnswer = try store.get(ColonySchema.Channels.finalAnswer)
    #expect(finalAnswer == "done with swarm tool")

    // Verify the echo tool's result is in the messages.
    let messages = try store.get(ColonySchema.Channels.messages)
    let toolMessages = messages.filter { $0.role == HiveChatRole.tool }
    #expect(toolMessages.contains { $0.content.contains("Echo: integration test") })
}

@Test("Swarm tool requires approval when risk level triggers mandatory approval")
func swarmToolRequiresApprovalForHighRisk() async throws {
    let echoTool = EchoTool()
    let bridge = try ColonySwarmToolBridge(
        tools: [echoTool],
        capability: .plugins,
        riskLevel: .execution  // High risk → mandatory approval
    )

    let graph = try ColonyAgent.compile()
    let fs = ColonyInMemoryFileSystemBackend()

    var configuration = ColonyConfiguration(
        modelName: "test-model",
        capabilities: [.plugins],
        toolApprovalPolicy: .always
    )
    for (name, level) in bridge.riskLevelOverrides {
        configuration.safety.toolRiskLevelOverrides[name] = level
    }

    let context = ColonyContext(configuration: configuration, filesystem: fs)
    let checkpointStore = InMemoryCheckpointStore<ColonySchema>()

    let model = SwarmToolCallingModel(
        toolName: "echo",
        toolArgs: #"{"message":"risky call"}"#
    )

    let environment = HiveEnvironment<ColonySchema>(
        context: context,
        clock: NoopClock(),
        logger: NoopLogger(),
        model: AnyHiveModelClient(model),
        tools: AnyHiveToolRegistry(ColonyHiveToolRegistryAdapter(base: bridge)),
        checkpointStore: AnyHiveCheckpointStore(checkpointStore)
    )

    let runtime = try HiveRuntime(graph: graph, environment: environment)
    let threadID = HiveThreadID("swarm-approval-test")

    let handle = await runtime.run(
        threadID: threadID,
        input: "echo something risky",
        options: HiveRunOptions(checkpointPolicy: .onInterrupt)
    )

    let outcome = try await handle.outcome.value
    guard case let .interrupted(interruption) = outcome else {
        #expect(Bool(false), "Expected interrupted outcome for high-risk Swarm tool")
        return
    }

    guard case let .toolApprovalRequired(toolCalls) = interruption.interrupt.payload else {
        #expect(Bool(false), "Expected toolApprovalRequired payload")
        return
    }
    #expect(toolCalls.count == 1)
    #expect(toolCalls.first?.name == "echo")
}

@Test("Swarm tool requires approval when Swarm execution semantics demand it")
func swarmToolRequiresApprovalForExplicitMetadata() async throws {
    let bridge = try ColonySwarmToolBridge(
        tools: [ApprovalMetadataEchoTool()],
        capability: .plugins,
        riskLevel: .readOnly
    )

    let graph = try ColonyAgent.compile()
    let fs = ColonyInMemoryFileSystemBackend()

    var configuration = ColonyConfiguration(
        modelName: "test-model",
        capabilities: [.plugins],
        toolApprovalPolicy: .never
    )
    for (name, level) in bridge.riskLevelOverrides {
        configuration.safety.toolRiskLevelOverrides[name] = level
    }
    for (name, metadata) in bridge.toolPolicyMetadataByName {
        configuration.safety.toolPolicyMetadataByName[name] = metadata
    }

    let context = ColonyContext(configuration: configuration, filesystem: fs)
    let checkpointStore = InMemoryCheckpointStore<ColonySchema>()
    let model = SwarmToolCallingModel(
        toolName: "approval_echo",
        toolArgs: #"{"message":"approval-gated"}"#
    )

    let environment = HiveEnvironment<ColonySchema>(
        context: context,
        clock: NoopClock(),
        logger: NoopLogger(),
        model: AnyHiveModelClient(model),
        tools: AnyHiveToolRegistry(ColonyHiveToolRegistryAdapter(base: bridge)),
        checkpointStore: AnyHiveCheckpointStore(checkpointStore)
    )

    let runtime = try HiveRuntime(graph: graph, environment: environment)
    let handle = await runtime.run(
        threadID: HiveThreadID("swarm-metadata-approval-test"),
        input: "echo something approval-gated",
        options: HiveRunOptions(checkpointPolicy: .onInterrupt)
    )

    let outcome = try await handle.outcome.value
    guard case let .interrupted(interruption) = outcome else {
        #expect(Bool(false), "Expected interrupted outcome for metadata-gated Swarm tool")
        return
    }

    guard case let .toolApprovalRequired(toolCalls) = interruption.interrupt.payload else {
        #expect(Bool(false), "Expected toolApprovalRequired payload")
        return
    }

    #expect(toolCalls.count == 1)
    #expect(toolCalls.first?.name == "approval_echo")
}

// MARK: - Factory Integration

@Test("makeRuntime accepts swarmTools parameter and merges risk overrides")
func makeRuntimeWithSwarmTools() throws {
    let echoTool = EchoTool()
    let bridge = try ColonySwarmToolBridge(
        tools: [echoTool],
        capability: .plugins,
        riskLevel: .network
    )

    // This should not throw — verifies the factory wires everything correctly.
    let runtime = try ColonyAgentFactory().makeRuntime(
        profile: .cloud,
        modelName: "test-model",
        swarmTools: bridge,
        filesystem: ColonyInMemoryFileSystemBackend()
    )

    #expect(runtime.runControl.threadID.rawValue.hasPrefix("colony:"))
}
