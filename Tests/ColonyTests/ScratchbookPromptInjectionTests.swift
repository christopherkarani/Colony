import ColonyCore
import Foundation
import HiveCore
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

private final class RecordingRequestModel: HiveModelClient, ColonyCapabilityReportingHiveModelClient, @unchecked Sendable {
    private let lock = NSLock()
    private var requests: [HiveChatRequest] = []
    private let capabilities: ColonyModelCapabilities

    init(capabilities: ColonyModelCapabilities = []) {
        self.capabilities = capabilities
    }

    var colonyModelCapabilities: ColonyModelCapabilities {
        capabilities
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

        let response = HiveChatResponse(
            message: HiveChatMessage(id: "assistant", role: .assistant, content: "ok")
        )
        return AsyncThrowingStream { continuation in
            continuation.yield(.final(response))
            continuation.finish()
        }
    }
}

private func systemPromptString(from request: HiveChatRequest) -> String? {
    request.messages.first(where: { $0.role == .system })?.content
}

private func extractSection(named header: String, from systemPrompt: String) -> String? {
    // Sections are joined with "\n\n" in ColonyPrompts.
    let marker = header + "\n"
    guard let start = systemPrompt.range(of: marker) else { return nil }
    let remainder = systemPrompt[start.upperBound...]
    let end = remainder.range(of: "\n\n")?.lowerBound ?? remainder.endIndex
    return String(remainder[..<end])
}

private func scratchbookFilePath(prefix: ColonyVirtualPath, threadID: HiveThreadID) throws -> ColonyVirtualPath {
    let policy = ColonyScratchbookPolicy(pathPrefix: prefix)
    return try ColonyScratchbookStore.path(threadID: threadID.rawValue, policy: policy)
}

private func makeScratchbookFileJSON(items: [[String: Any]], pinnedItemIDs: [String] = []) throws -> String {
    let payload: [String: Any] = [
        "items": items,
        "pinnedItemIDs": pinnedItemIDs,
    ]
    let data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
    return String(decoding: data, as: UTF8.self)
}

@Test("System prompt injects Scratchbook view when enabled and filesystem backend exists")
func systemPrompt_injectsScratchbookView_whenEnabledAndFilesystemExists() async throws {
    let graph = try ColonyAgent.compile()
    let fs = ColonyInMemoryFileSystemBackend()

    let threadID = HiveThreadID("thread-scratchbook-inject")
    let prefix = try ColonyVirtualPath("/scratchbook")
    let scratchbookPath = try scratchbookFilePath(prefix: prefix, threadID: threadID)

    let fileJSON = try makeScratchbookFileJSON(items: [
        [
            "id": "item-1",
            "kind": "note",
            "status": "open",
            "title": "Alpha",
            "body": "Hello",
            "tags": ["t1"],
            "createdAtNanoseconds": 1,
            "updatedAtNanoseconds": 1,
        ],
    ])
    try await fs.write(at: scratchbookPath, content: fileJSON)

    var configuration = ColonyConfiguration(
        modelName: "test-model",
        capabilities: [.filesystem, .scratchbook],
        toolApprovalPolicy: .never
    )
    configuration.context.compactionPolicy = .maxTokens(0)
    configuration.context.scratchbookPolicy = ColonyScratchbookPolicy(
        pathPrefix: prefix,
        viewTokenLimit: 200,
        maxRenderedItems: 20,
        autoCompact: false
    )
    configuration.prompts.toolPromptStrategy = .includeInSystemPrompt

    let recordingModel = RecordingRequestModel()
    let context = ColonyContext(configuration: configuration, filesystem: fs)
    let environment = HiveEnvironment<ColonySchema>(
        context: context,
        clock: NoopClock(),
        logger: NoopLogger(),
        model: AnyHiveModelClient(recordingModel)
    )
    let runtime = try HiveRuntime(graph: graph, environment: environment)
    _ = try await (await runtime.run(
        threadID: threadID,
        input: "hi",
        options: HiveRunOptions(checkpointPolicy: .disabled)
    )).outcome.value

    guard let request = recordingModel.recordedRequests().last,
          let systemPrompt = systemPromptString(from: request) else {
        #expect(Bool(false))
        return
    }

    let scratchbookView = extractSection(named: "Scratchbook:", from: systemPrompt)
    #expect(scratchbookView != nil)
    #expect(scratchbookView?.contains("Alpha") == true)
}

@Test("System prompt scratchbook injection resolves canonical sanitized scratchbook path")
func systemPrompt_injectsScratchbookView_fromSanitizedPath() async throws {
    let graph = try ColonyAgent.compile()
    let fs = ColonyInMemoryFileSystemBackend()

    let threadID = HiveThreadID("thread/scratch\\path:injection")
    let prefix = try ColonyVirtualPath("/scratchbook")
    let scratchbookPath = try scratchbookFilePath(prefix: prefix, threadID: threadID)

    try await fs.write(
        at: scratchbookPath,
        content: try makeScratchbookFileJSON(items: [[
            "id": "item-1",
            "kind": "note",
            "status": "open",
            "title": "Sanitized Path Item",
            "body": "",
            "tags": [],
            "createdAtNanoseconds": 1,
            "updatedAtNanoseconds": 1,
        ]])
    )

    let unsanitizedPath = try ColonyVirtualPath(prefix.rawValue + "/" + threadID.rawValue + ".json")
    await #expect(throws: ColonyFileSystemError.notFound(unsanitizedPath)) {
        _ = try await fs.read(at: unsanitizedPath)
    }

    var configuration = ColonyConfiguration(
        modelName: "test-model",
        capabilities: [.filesystem, .scratchbook],
        toolApprovalPolicy: .never
    )
    configuration.context.compactionPolicy = .maxTokens(0)
    configuration.context.scratchbookPolicy = ColonyScratchbookPolicy(
        pathPrefix: prefix,
        viewTokenLimit: 200,
        maxRenderedItems: 20,
        autoCompact: false
    )
    configuration.prompts.toolPromptStrategy = .includeInSystemPrompt

    let recordingModel = RecordingRequestModel()
    let context = ColonyContext(configuration: configuration, filesystem: fs)
    let environment = HiveEnvironment<ColonySchema>(
        context: context,
        clock: NoopClock(),
        logger: NoopLogger(),
        model: AnyHiveModelClient(recordingModel)
    )
    let runtime = try HiveRuntime(graph: graph, environment: environment)
    _ = try await (await runtime.run(
        threadID: threadID,
        input: "hi",
        options: HiveRunOptions(checkpointPolicy: .disabled)
    )).outcome.value

    guard let request = recordingModel.recordedRequests().last,
          let systemPrompt = systemPromptString(from: request) else {
        #expect(Bool(false))
        return
    }

    let scratchbookView = extractSection(named: "Scratchbook:", from: systemPrompt)
    #expect(scratchbookView?.contains("Sanitized Path Item") == true)
}

@Test("System prompt does not inject Scratchbook view when filesystem backend is missing")
func systemPrompt_omitsScratchbookView_whenFilesystemMissing() async throws {
    let graph = try ColonyAgent.compile()
    let threadID = HiveThreadID("thread-scratchbook-no-fs")

    var configuration = ColonyConfiguration(
        modelName: "test-model",
        capabilities: [.scratchbook],
        toolApprovalPolicy: .never
    )
    configuration.context.compactionPolicy = .maxTokens(0)
    configuration.context.scratchbookPolicy = ColonyScratchbookPolicy(
        pathPrefix: try ColonyVirtualPath("/scratchbook"),
        viewTokenLimit: 200,
        maxRenderedItems: 20,
        autoCompact: false
    )
    configuration.prompts.toolPromptStrategy = .includeInSystemPrompt

    let recordingModel = RecordingRequestModel()
    let context = ColonyContext(configuration: configuration, filesystem: nil)
    let environment = HiveEnvironment<ColonySchema>(
        context: context,
        clock: NoopClock(),
        logger: NoopLogger(),
        model: AnyHiveModelClient(recordingModel)
    )
    let runtime = try HiveRuntime(graph: graph, environment: environment)
    _ = try await (await runtime.run(
        threadID: threadID,
        input: "hi",
        options: HiveRunOptions(checkpointPolicy: .disabled)
    )).outcome.value

    guard let request = recordingModel.recordedRequests().last,
          let systemPrompt = systemPromptString(from: request) else {
        #expect(Bool(false))
        return
    }

    #expect(extractSection(named: "Scratchbook:", from: systemPrompt) == nil)
}

@Test("Scratchbook injection respects maxRenderedItems")
func scratchbookInjection_respectsMaxRenderedItems() async throws {
    let graph = try ColonyAgent.compile()
    let fs = ColonyInMemoryFileSystemBackend()

    let threadID = HiveThreadID("thread-scratchbook-max-items")
    let prefix = try ColonyVirtualPath("/scratchbook")
    let scratchbookPath = try scratchbookFilePath(prefix: prefix, threadID: threadID)

    let items: [[String: Any]] = (1...3).map { i in
        [
            "id": "item-\(i)",
            "kind": "note",
            "status": "open",
            "title": "Title-\(i)",
            "body": "Body-\(i)",
            "tags": [],
            "createdAtNanoseconds": i,
            "updatedAtNanoseconds": i,
        ]
    }
    try await fs.write(at: scratchbookPath, content: try makeScratchbookFileJSON(items: items))

    var configuration = ColonyConfiguration(
        modelName: "test-model",
        capabilities: [.filesystem, .scratchbook],
        toolApprovalPolicy: .never
    )
    configuration.context.compactionPolicy = .maxTokens(0)
    configuration.context.scratchbookPolicy = ColonyScratchbookPolicy(
        pathPrefix: prefix,
        viewTokenLimit: 5_000,
        maxRenderedItems: 2,
        autoCompact: false
    )
    configuration.prompts.toolPromptStrategy = .includeInSystemPrompt

    let recordingModel = RecordingRequestModel()
    let context = ColonyContext(configuration: configuration, filesystem: fs)
    let environment = HiveEnvironment<ColonySchema>(
        context: context,
        clock: NoopClock(),
        logger: NoopLogger(),
        model: AnyHiveModelClient(recordingModel)
    )
    let runtime = try HiveRuntime(graph: graph, environment: environment)
    _ = try await (await runtime.run(
        threadID: threadID,
        input: "hi",
        options: HiveRunOptions(checkpointPolicy: .disabled)
    )).outcome.value

    guard let request = recordingModel.recordedRequests().last,
          let systemPrompt = systemPromptString(from: request),
          let scratchbookView = extractSection(named: "Scratchbook:", from: systemPrompt) else {
        #expect(Bool(false))
        return
    }

    let titles = ["Title-1", "Title-2", "Title-3"]
    let presentCount = titles.reduce(0) { $0 + (scratchbookView.contains($1) ? 1 : 0) }
    #expect(presentCount <= 2)
}

@Test("Scratchbook injection respects viewTokenLimit")
func scratchbookInjection_respectsViewTokenLimit() async throws {
    let graph = try ColonyAgent.compile()
    let fs = ColonyInMemoryFileSystemBackend()

    let threadID = HiveThreadID("thread-scratchbook-token-limit")
    let prefix = try ColonyVirtualPath("/scratchbook")
    let scratchbookPath = try scratchbookFilePath(prefix: prefix, threadID: threadID)

    let items: [[String: Any]] = (1...40).map { i in
        [
            "id": "item-\(i)",
            "kind": "note",
            "status": "open",
            "title": "Item-\(i): " + String(repeating: "x", count: 80),
            "body": "",
            "tags": [],
            "createdAtNanoseconds": i,
            "updatedAtNanoseconds": i,
        ]
    }
    try await fs.write(at: scratchbookPath, content: try makeScratchbookFileJSON(items: items))

    let viewTokenLimit = 50
    var configuration = ColonyConfiguration(
        modelName: "test-model",
        capabilities: [.filesystem, .scratchbook],
        toolApprovalPolicy: .never
    )
    configuration.context.compactionPolicy = .maxTokens(0)
    configuration.context.scratchbookPolicy = ColonyScratchbookPolicy(
        pathPrefix: prefix,
        viewTokenLimit: viewTokenLimit,
        maxRenderedItems: 200,
        autoCompact: false
    )
    configuration.prompts.toolPromptStrategy = .includeInSystemPrompt

    let recordingModel = RecordingRequestModel()
    let context = ColonyContext(configuration: configuration, filesystem: fs)
    let environment = HiveEnvironment<ColonySchema>(
        context: context,
        clock: NoopClock(),
        logger: NoopLogger(),
        model: AnyHiveModelClient(recordingModel)
    )
    let runtime = try HiveRuntime(graph: graph, environment: environment)
    _ = try await (await runtime.run(
        threadID: threadID,
        input: "hi",
        options: HiveRunOptions(checkpointPolicy: .disabled)
    )).outcome.value

    guard let request = recordingModel.recordedRequests().last,
          let systemPrompt = systemPromptString(from: request),
          let scratchbookView = extractSection(named: "Scratchbook:", from: systemPrompt) else {
        #expect(Bool(false))
        return
    }

    let tokenizer = ColonyApproximateTokenizer()
    let tokens = tokenizer.countTokens([
        HiveChatMessage(id: "budget:scratchbook-view", role: .system, content: scratchbookView)
    ])
    #expect(tokens <= viewTokenLimit)
}

@Test("toolPromptStrategy overrides system prompt tool list output without removing tool definitions")
func toolPromptStrategy_overridesToolsSection() async throws {
    let graph = try ColonyAgent.compile()
    let fs = ColonyInMemoryFileSystemBackend()

    func run(_ toolPromptStrategy: ColonyToolPromptStrategy) async throws -> HiveChatRequest {
        var configuration = ColonyConfiguration(
            modelName: "test-model",
            capabilities: [.filesystem],
            toolApprovalPolicy: .never
        )
        configuration.context.compactionPolicy = .maxTokens(0)
        configuration.prompts.toolPromptStrategy = toolPromptStrategy

        let recordingModel = RecordingRequestModel()
        let context = ColonyContext(configuration: configuration, filesystem: fs)
        let environment = HiveEnvironment<ColonySchema>(
            context: context,
            clock: NoopClock(),
            logger: NoopLogger(),
            model: AnyHiveModelClient(recordingModel)
        )
        let runtime = try HiveRuntime(graph: graph, environment: environment)
        _ = try await (await runtime.run(
            threadID: HiveThreadID("thread-tools-section-\(toolPromptStrategy)"),
            input: "hi",
            options: HiveRunOptions(checkpointPolicy: .disabled)
        )).outcome.value

        guard let request = recordingModel.recordedRequests().last else {
            throw ColonyFileSystemError.ioError("Missing recorded request.")
        }
        return request
    }

    let withTools = try await run(.includeInSystemPrompt)
    let withoutTools = try await run(.omitFromSystemPrompt)

    #expect(withTools.tools.isEmpty == false)
    #expect(withoutTools.tools.isEmpty == false)
    #expect(withTools.tools.map(\.name) == withoutTools.tools.map(\.name))

    let withPrompt = systemPromptString(from: withTools) ?? ""
    let withoutPrompt = systemPromptString(from: withoutTools) ?? ""

    #expect(withPrompt.contains("Tools:\n"))
    #expect(withoutPrompt.contains("Tools:\n") == false)
}

@Test("toolPromptStrategy defaults are automatic for on-device and cloud profiles")
func toolPromptStrategy_defaultsToAutomaticAcrossProfiles() throws {
    let onDevice = ColonyAgentFactory.configuration(profile: .onDevice4k, modelName: "test-model")
    let cloud = ColonyAgentFactory.configuration(profile: .cloud, modelName: "test-model")

    #expect(onDevice.prompts.toolPromptStrategy == .automatic)
    #expect(cloud.prompts.toolPromptStrategy == .automatic)
}

@Test("automatic tool prompt strategy omits the tools section for managed tool prompting models")
func automaticToolPromptStrategy_omitsToolsSectionForManagedModels() async throws {
    let graph = try ColonyAgent.compile()
    let fs = ColonyInMemoryFileSystemBackend()

    var configuration = ColonyConfiguration(
        modelName: "test-model",
        capabilities: [.filesystem],
        toolApprovalPolicy: .never
    )
    configuration.context.compactionPolicy = .maxTokens(0)
    configuration.prompts.toolPromptStrategy = .automatic

    let recordingModel = RecordingRequestModel(capabilities: [.managedToolPrompting])
    let context = ColonyContext(configuration: configuration, modelCapabilities: recordingModel.colonyModelCapabilities, filesystem: fs)
    let environment = HiveEnvironment<ColonySchema>(
        context: context,
        clock: NoopClock(),
        logger: NoopLogger(),
        model: AnyHiveModelClient(recordingModel)
    )
    let runtime = try HiveRuntime(graph: graph, environment: environment)
    _ = try await (await runtime.run(
        threadID: HiveThreadID("thread-tools-managed"),
        input: "hi",
        options: HiveRunOptions(checkpointPolicy: .disabled)
    )).outcome.value

    guard let request = recordingModel.recordedRequests().last else {
        #expect(Bool(false))
        return
    }

    let systemPrompt = systemPromptString(from: request) ?? ""
    #expect(request.tools.isEmpty == false)
    #expect(systemPrompt.contains("Tools:\n") == false)
}

@Test("automatic tool prompt strategy includes the tools section for unknown models")
func automaticToolPromptStrategy_includesToolsSectionForUnknownModels() async throws {
    let graph = try ColonyAgent.compile()
    let fs = ColonyInMemoryFileSystemBackend()

    var configuration = ColonyConfiguration(
        modelName: "test-model",
        capabilities: [.filesystem],
        toolApprovalPolicy: .never
    )
    configuration.context.compactionPolicy = .maxTokens(0)
    configuration.prompts.toolPromptStrategy = .automatic

    let recordingModel = RecordingRequestModel()
    let context = ColonyContext(configuration: configuration, filesystem: fs)
    let environment = HiveEnvironment<ColonySchema>(
        context: context,
        clock: NoopClock(),
        logger: NoopLogger(),
        model: AnyHiveModelClient(recordingModel)
    )
    let runtime = try HiveRuntime(graph: graph, environment: environment)
    _ = try await (await runtime.run(
        threadID: HiveThreadID("thread-tools-unknown"),
        input: "hi",
        options: HiveRunOptions(checkpointPolicy: .disabled)
    )).outcome.value

    guard let request = recordingModel.recordedRequests().last else {
        #expect(Bool(false))
        return
    }

    let systemPrompt = systemPromptString(from: request) ?? ""
    #expect(request.tools.isEmpty == false)
    #expect(systemPrompt.contains("Tools:\n"))
}

@Test("factory infers direct model capabilities for automatic tool prompt strategy")
func factory_infersDirectModelCapabilitiesForAutomaticToolPromptStrategy() async throws {
    let recordingModel = RecordingRequestModel(capabilities: [.managedToolPrompting])
    let runtime = try ColonyAgentFactory().makeRuntime(
        profile: .cloud,
        threadID: HiveThreadID("thread-tools-factory-inference"),
        modelName: "test-model",
        model: recordingModel,
        configure: { configuration in
            configuration.model.capabilities = [.filesystem]
            configuration.safety.toolApprovalPolicy = .never
            configuration.context.compactionPolicy = .maxTokens(0)
            configuration.prompts.toolPromptStrategy = .automatic
        }
    )

    _ = try await (await runtime.runControl.startRaw(input: "hi")).outcome.value

    guard let request = recordingModel.recordedRequests().last else {
        #expect(Bool(false))
        return
    }

    let systemPrompt = systemPromptString(from: request) ?? ""
    #expect(request.tools.isEmpty == false)
    #expect(systemPrompt.contains("Tools:\n") == false)
}

@Test("automatic tool prompt strategy uses routed model capabilities")
func automaticToolPromptStrategy_usesRoutedModelCapabilities() async throws {
    let onDeviceModel = RecordingRequestModel()
    let fallbackModel = RecordingRequestModel()
    let router = ColonyOnDeviceModelRouter(
        onDevice: AnyHiveModelClient(onDeviceModel),
        fallback: AnyHiveModelClient(fallbackModel),
        onDeviceCapabilities: [.managedToolPrompting],
        fallbackCapabilities: []
    )

    let runtime = try ColonyAgentFactory().makeRuntime(
        profile: .cloud,
        threadID: HiveThreadID("thread-tools-router-capabilities"),
        modelName: "test-model",
        modelRouter: router,
        inferenceHints: HiveInferenceHints(
            latencyTier: .interactive,
            privacyRequired: true,
            tokenBudget: nil,
            networkState: .online
        ),
        configure: { configuration in
            configuration.model.capabilities = [.filesystem]
            configuration.safety.toolApprovalPolicy = .never
            configuration.context.compactionPolicy = .maxTokens(0)
            configuration.prompts.toolPromptStrategy = .automatic
        }
    )

    _ = try await (await runtime.runControl.startRaw(input: "hi")).outcome.value

    guard let request = onDeviceModel.recordedRequests().last else {
        #expect(Bool(false))
        return
    }

    let systemPrompt = systemPromptString(from: request) ?? ""
    #expect(request.tools.isEmpty == false)
    #expect(systemPrompt.contains("Tools:\n") == false)
    #expect(fallbackModel.recordedRequests().isEmpty)
}

@Test("structured output instructions are injected when model cannot handle them directly")
func structuredOutputPrompting_isInjectedForModelsWithoutStructuredOutputCapability() async throws {
    let recordingModel = RecordingRequestModel()
    let runtime = try ColonyAgentFactory().makeRuntime(
        profile: .cloud,
        threadID: HiveThreadID("thread-structured-output-prompt"),
        modelName: "test-model",
        model: AnyHiveModelClient(recordingModel),
        configure: { configuration in
            configuration.context.compactionPolicy = .maxTokens(0)
            configuration.model.structuredOutput = .jsonObject
        }
    )

    _ = try await (await runtime.runControl.startRaw(input: "return json")).outcome.value

    guard let request = recordingModel.recordedRequests().last else {
        #expect(Bool(false))
        return
    }

    let systemPrompt = systemPromptString(from: request) ?? ""
    #expect(request.structuredOutput == .jsonObject)
    #expect(systemPrompt.contains("Respond with valid JSON only.") == true)
}

@Test("structured output instructions are omitted when wrapped models provide managed structured-output capabilities")
func structuredOutputPrompting_isOmittedForWrappedManagedStructuredOutputModels() async throws {
    let recordingModel = RecordingRequestModel(capabilities: [.managedStructuredOutputs])
    let runtime = try ColonyAgentFactory().makeRuntime(
        profile: .cloud,
        threadID: HiveThreadID("thread-structured-output-managed"),
        modelName: "test-model",
        model: AnyHiveModelClient(recordingModel),
        modelCapabilities: [.managedStructuredOutputs],
        configure: { configuration in
            configuration.context.compactionPolicy = .maxTokens(0)
            configuration.model.structuredOutput = .jsonObject
        }
    )

    _ = try await (await runtime.runControl.startRaw(input: "return json")).outcome.value

    guard let request = recordingModel.recordedRequests().last else {
        #expect(Bool(false))
        return
    }

    let systemPrompt = systemPromptString(from: request) ?? ""
    #expect(request.structuredOutput == .jsonObject)
    #expect(systemPrompt.contains("Respond with valid JSON only.") == false)
}
