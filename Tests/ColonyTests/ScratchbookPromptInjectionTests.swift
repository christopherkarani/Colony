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

private func systemPromptString(from request: SwarmChatRequest) -> String? {
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

private func scratchbookFilePath(prefix: ColonyVirtualPath, threadID: SwarmThreadID) throws -> ColonyVirtualPath {
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

    let threadID = SwarmThreadID("thread-scratchbook-inject")
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
        capabilities: [.filesystem, .scratchbook],
        modelName: "test-model",
        toolApprovalPolicy: .never,
        compactionPolicy: .maxTokens(0)
    )
    configuration.scratchbookPolicy = ColonyScratchbookPolicy(
        pathPrefix: prefix,
        viewTokenLimit: 200,
        maxRenderedItems: 20,
        autoCompact: false
    )
    configuration.includeToolListInSystemPrompt = true

    let recordingModel = RecordingRequestModel()
    let context = ColonyContext(configuration: configuration, filesystem: fs)
    let environment = SwarmGraphEnvironment<ColonySchema>(
        context: context,
        clock: NoopClock(),
        logger: NoopLogger(),
        model: SwarmAnyModelClient(recordingModel)
    )
    let runtime = try SwarmGraphRuntime(graph: graph, environment: environment)
    _ = try await (await runtime.run(
        threadID: threadID,
        input: "hi",
        options: SwarmGraphRunOptions(checkpointPolicy: .disabled)
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

    let threadID = SwarmThreadID("thread/scratch\\path:injection")
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
        capabilities: [.filesystem, .scratchbook],
        modelName: "test-model",
        toolApprovalPolicy: .never,
        compactionPolicy: .maxTokens(0)
    )
    configuration.scratchbookPolicy = ColonyScratchbookPolicy(
        pathPrefix: prefix,
        viewTokenLimit: 200,
        maxRenderedItems: 20,
        autoCompact: false
    )
    configuration.includeToolListInSystemPrompt = true

    let recordingModel = RecordingRequestModel()
    let context = ColonyContext(configuration: configuration, filesystem: fs)
    let environment = SwarmGraphEnvironment<ColonySchema>(
        context: context,
        clock: NoopClock(),
        logger: NoopLogger(),
        model: SwarmAnyModelClient(recordingModel)
    )
    let runtime = try SwarmGraphRuntime(graph: graph, environment: environment)
    _ = try await (await runtime.run(
        threadID: threadID,
        input: "hi",
        options: SwarmGraphRunOptions(checkpointPolicy: .disabled)
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
    let threadID = SwarmThreadID("thread-scratchbook-no-fs")

    var configuration = ColonyConfiguration(
        capabilities: [.scratchbook],
        modelName: "test-model",
        toolApprovalPolicy: .never,
        compactionPolicy: .maxTokens(0)
    )
    configuration.scratchbookPolicy = ColonyScratchbookPolicy(
        pathPrefix: try ColonyVirtualPath("/scratchbook"),
        viewTokenLimit: 200,
        maxRenderedItems: 20,
        autoCompact: false
    )
    configuration.includeToolListInSystemPrompt = true

    let recordingModel = RecordingRequestModel()
    let context = ColonyContext(configuration: configuration, filesystem: nil)
    let environment = SwarmGraphEnvironment<ColonySchema>(
        context: context,
        clock: NoopClock(),
        logger: NoopLogger(),
        model: SwarmAnyModelClient(recordingModel)
    )
    let runtime = try SwarmGraphRuntime(graph: graph, environment: environment)
    _ = try await (await runtime.run(
        threadID: threadID,
        input: "hi",
        options: SwarmGraphRunOptions(checkpointPolicy: .disabled)
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

    let threadID = SwarmThreadID("thread-scratchbook-max-items")
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
        capabilities: [.filesystem, .scratchbook],
        modelName: "test-model",
        toolApprovalPolicy: .never,
        compactionPolicy: .maxTokens(0)
    )
    configuration.scratchbookPolicy = ColonyScratchbookPolicy(
        pathPrefix: prefix,
        viewTokenLimit: 5_000,
        maxRenderedItems: 2,
        autoCompact: false
    )
    configuration.includeToolListInSystemPrompt = true

    let recordingModel = RecordingRequestModel()
    let context = ColonyContext(configuration: configuration, filesystem: fs)
    let environment = SwarmGraphEnvironment<ColonySchema>(
        context: context,
        clock: NoopClock(),
        logger: NoopLogger(),
        model: SwarmAnyModelClient(recordingModel)
    )
    let runtime = try SwarmGraphRuntime(graph: graph, environment: environment)
    _ = try await (await runtime.run(
        threadID: threadID,
        input: "hi",
        options: SwarmGraphRunOptions(checkpointPolicy: .disabled)
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

    let threadID = SwarmThreadID("thread-scratchbook-token-limit")
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
        capabilities: [.filesystem, .scratchbook],
        modelName: "test-model",
        toolApprovalPolicy: .never,
        compactionPolicy: .maxTokens(0),
        requestHardTokenLimit: nil
    )
    configuration.scratchbookPolicy = ColonyScratchbookPolicy(
        pathPrefix: prefix,
        viewTokenLimit: viewTokenLimit,
        maxRenderedItems: 200,
        autoCompact: false
    )
    configuration.includeToolListInSystemPrompt = true

    let recordingModel = RecordingRequestModel()
    let context = ColonyContext(configuration: configuration, filesystem: fs)
    let environment = SwarmGraphEnvironment<ColonySchema>(
        context: context,
        clock: NoopClock(),
        logger: NoopLogger(),
        model: SwarmAnyModelClient(recordingModel)
    )
    let runtime = try SwarmGraphRuntime(graph: graph, environment: environment)
    _ = try await (await runtime.run(
        threadID: threadID,
        input: "hi",
        options: SwarmGraphRunOptions(checkpointPolicy: .disabled)
    )).outcome.value

    guard let request = recordingModel.recordedRequests().last,
          let systemPrompt = systemPromptString(from: request),
          let scratchbookView = extractSection(named: "Scratchbook:", from: systemPrompt) else {
        #expect(Bool(false))
        return
    }

    let tokenizer = ColonyApproximateTokenizer()
    let tokens = tokenizer.countTokens([
        SwarmChatMessage(id: "budget:scratchbook-view", role: .system, content: scratchbookView)
    ])
    #expect(tokens <= viewTokenLimit)
}

@Test("includeToolListInSystemPrompt toggles system prompt tool list output without removing tool definitions")
func includeToolListInSystemPrompt_togglesToolsSection() async throws {
    let graph = try ColonyAgent.compile()
    let fs = ColonyInMemoryFileSystemBackend()

    func run(includeToolsInPrompt: Bool) async throws -> SwarmChatRequest {
        var configuration = ColonyConfiguration(
            capabilities: [.filesystem],
            modelName: "test-model",
            toolApprovalPolicy: .never,
            compactionPolicy: .maxTokens(0)
        )
        configuration.includeToolListInSystemPrompt = includeToolsInPrompt

        let recordingModel = RecordingRequestModel()
        let context = ColonyContext(configuration: configuration, filesystem: fs)
        let environment = SwarmGraphEnvironment<ColonySchema>(
            context: context,
            clock: NoopClock(),
            logger: NoopLogger(),
            model: SwarmAnyModelClient(recordingModel)
        )
        let runtime = try SwarmGraphRuntime(graph: graph, environment: environment)
        _ = try await (await runtime.run(
            threadID: SwarmThreadID("thread-tools-section-\(includeToolsInPrompt)"),
            input: "hi",
            options: SwarmGraphRunOptions(checkpointPolicy: .disabled)
        )).outcome.value

        guard let request = recordingModel.recordedRequests().last else {
            throw ColonyFileSystemError.ioError("Missing recorded request.")
        }
        return request
    }

    let withTools = try await run(includeToolsInPrompt: true)
    let withoutTools = try await run(includeToolsInPrompt: false)

    #expect(withTools.tools.isEmpty == false)
    #expect(withoutTools.tools.isEmpty == false)
    #expect(withTools.tools.map(\.name) == withoutTools.tools.map(\.name))

    let withPrompt = systemPromptString(from: withTools) ?? ""
    let withoutPrompt = systemPromptString(from: withoutTools) ?? ""

    #expect(withPrompt.contains("Tools:\n"))
    #expect(withoutPrompt.contains("Tools:\n") == false)
}

@Test("includeToolListInSystemPrompt defaults are on-device=false and cloud=true")
func includeToolListInSystemPrompt_defaults_matchProfiles() throws {
    let onDevice = ColonyAgentFactory.configuration(profile: .onDevice4k, modelName: "test-model")
    let cloud = ColonyAgentFactory.configuration(profile: .cloud, modelName: "test-model")

    #expect(onDevice.includeToolListInSystemPrompt == false)
    #expect(cloud.includeToolListInSystemPrompt == true)
}
