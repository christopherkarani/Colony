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

private final class ToolCallSequenceModel: HiveModelClient, @unchecked Sendable {
    private let lock = NSLock()
    private var callIndex: Int = 0
    private let toolCalls: [HiveToolCall]
    private let finalContent: String

    init(toolCalls: [HiveToolCall], finalContent: String = "done") {
        self.toolCalls = toolCalls
        self.finalContent = finalContent
    }

    func complete(_ request: HiveChatRequest) async throws -> HiveChatResponse {
        try await streamFinal(request)
    }

    func stream(_ request: HiveChatRequest) -> AsyncThrowingStream<HiveChatStreamChunk, Error> {
        let response: HiveChatResponse = {
            lock.lock()
            defer { lock.unlock() }
            callIndex += 1
            if callIndex <= toolCalls.count {
                let call = toolCalls[callIndex - 1]
                return HiveChatResponse(
                    message: HiveChatMessage(
                        id: "assistant",
                        role: .assistant,
                        content: "tool:\(call.name)",
                        toolCalls: [call]
                    )
                )
            }
            return HiveChatResponse(
                message: HiveChatMessage(id: "assistant", role: .assistant, content: finalContent)
            )
        }()

        return AsyncThrowingStream { continuation in
            continuation.yield(.final(response))
            continuation.finish()
        }
    }
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

private actor RecordingFileSystemBackend: ColonyFileSystemBackend {
    enum Operation: Sendable, Equatable {
        case list(ColonyVirtualPath)
        case read(ColonyVirtualPath)
        case write(ColonyVirtualPath, content: String)
        case edit(ColonyVirtualPath, old: String, new: String, replaceAll: Bool)
        case glob(String)
        case grep(pattern: String, glob: String?)
    }

    private let base: any ColonyFileSystemBackend
    private var operations: [Operation] = []

    init(base: any ColonyFileSystemBackend) {
        self.base = base
    }

    func list(at path: ColonyVirtualPath) async throws -> [ColonyFileInfo] {
        operations.append(.list(path))
        return try await base.list(at: path)
    }

    func read(at path: ColonyVirtualPath) async throws -> String {
        operations.append(.read(path))
        return try await base.read(at: path)
    }

    func write(at path: ColonyVirtualPath, content: String) async throws {
        operations.append(.write(path, content: content))
        try await base.write(at: path, content: content)
    }

    func edit(
        at path: ColonyVirtualPath,
        oldString: String,
        newString: String,
        replaceAll: Bool
    ) async throws -> Int {
        operations.append(.edit(path, old: oldString, new: newString, replaceAll: replaceAll))
        return try await base.edit(
            at: path,
            oldString: oldString,
            newString: newString,
            replaceAll: replaceAll
        )
    }

    func glob(pattern: String) async throws -> [ColonyVirtualPath] {
        operations.append(.glob(pattern))
        return try await base.glob(pattern: pattern)
    }

    func grep(pattern: String, glob: String?) async throws -> [ColonyGrepMatch] {
        operations.append(.grep(pattern: pattern, glob: glob))
        return try await base.grep(pattern: pattern, glob: glob)
    }

    func recordedOperations() -> [Operation] {
        operations
    }
}

private func scratchbookFilePath(
    prefix: ColonyVirtualPath,
    threadID: HiveThreadID
) throws -> ColonyVirtualPath {
    // Spec: `{scratchbookPathPrefix}/{sanitizedThreadID}.json` (plan A2).
    // Choose test thread IDs that do not require sanitization.
    try ColonyVirtualPath(prefix.rawValue + "/" + threadID.rawValue + ".json")
}

private func decodeScratchbookJSON(_ text: String) throws -> [String: Any] {
    let data = Data(text.utf8)
    let obj = try JSONSerialization.jsonObject(with: data, options: [])
    guard let dict = obj as? [String: Any] else { return [:] }
    return dict
}

private func firstScratchItemID(from scratchbookJSON: [String: Any]) -> String? {
    guard let items = scratchbookJSON["items"] as? [[String: Any]] else { return nil }
    return items.first?["id"] as? String
}

private func scratchItem(withID id: String, in scratchbookJSON: [String: Any]) -> [String: Any]? {
    guard let items = scratchbookJSON["items"] as? [[String: Any]] else { return nil }
    return items.first { ($0["id"] as? String) == id }
}

@Test("Scratchbook tools are not advertised without ColonyCapabilities.scratchbook")
func scratchbookTools_notAdvertisedWithoutCapability() async throws {
    let graph = try ColonyAgent.compile()
    let fs = ColonyInMemoryFileSystemBackend()

    var configuration = ColonyConfiguration(
        capabilities: [.planning, .filesystem],
        modelName: "test-model",
        toolApprovalPolicy: .never,
        compactionPolicy: .maxTokens(0)
    )
    // Enable Scratchbook policy explicitly; capability gate should still hide tools.
    configuration.scratchbookPolicy = ColonyScratchbookPolicy(
        pathPrefix: try ColonyVirtualPath("/scratchbook"),
        viewTokenLimit: 200,
        maxRenderedItems: 20,
        autoCompact: false
    )

    let recordingModel = RecordingRequestModel()
    let context = ColonyContext(configuration: configuration, filesystem: fs)
    let environment = HiveEnvironment<ColonySchema>(
        context: context,
        clock: NoopClock(),
        logger: NoopLogger(),
        model: AnyHiveModelClient(recordingModel)
    )
    let runtime = HiveRuntime(graph: graph, environment: environment)

    let handle = await runtime.run(
        threadID: HiveThreadID("thread-scratchbook-gating-off"),
        input: "hi",
        options: HiveRunOptions(checkpointPolicy: .disabled)
    )
    _ = try await handle.outcome.value

    guard let request = recordingModel.recordedRequests().last else {
        #expect(Bool(false))
        return
    }

    let toolNames = Set(request.tools.map(\.name))
    #expect(toolNames.contains("scratch_read") == false)
    #expect(toolNames.contains("scratch_add") == false)
    #expect(toolNames.contains("scratch_update") == false)
    #expect(toolNames.contains("scratch_complete") == false)
    #expect(toolNames.contains("scratch_pin") == false)
    #expect(toolNames.contains("scratch_unpin") == false)
}

@Test("Scratchbook tools are advertised when ColonyCapabilities.scratchbook is enabled")
func scratchbookTools_advertisedWhenCapabilityEnabled() async throws {
    let graph = try ColonyAgent.compile()
    let fs = ColonyInMemoryFileSystemBackend()

    var configuration = ColonyConfiguration(
        capabilities: [.planning, .filesystem, .scratchbook],
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

    let recordingModel = RecordingRequestModel()
    let context = ColonyContext(configuration: configuration, filesystem: fs)
    let environment = HiveEnvironment<ColonySchema>(
        context: context,
        clock: NoopClock(),
        logger: NoopLogger(),
        model: AnyHiveModelClient(recordingModel)
    )
    let runtime = HiveRuntime(graph: graph, environment: environment)

    let handle = await runtime.run(
        threadID: HiveThreadID("thread-scratchbook-gating-on"),
        input: "hi",
        options: HiveRunOptions(checkpointPolicy: .disabled)
    )
    _ = try await handle.outcome.value

    guard let request = recordingModel.recordedRequests().last else {
        #expect(Bool(false))
        return
    }

    let toolNames = Set(request.tools.map(\.name))
    #expect(toolNames.contains("scratch_read"))
    #expect(toolNames.contains("scratch_add"))
    #expect(toolNames.contains("scratch_update"))
    #expect(toolNames.contains("scratch_complete"))
    #expect(toolNames.contains("scratch_pin"))
    #expect(toolNames.contains("scratch_unpin"))
}

@Test("Scratchbook tool execution rejects calls when ColonyCapabilities.scratchbook is disabled")
func scratchbookTools_rejectExecutionWhenCapabilityDisabled() async throws {
    let graph = try ColonyAgent.compile()
    let baseFS = ColonyInMemoryFileSystemBackend()
    let fs = RecordingFileSystemBackend(base: baseFS)

    var configuration = ColonyConfiguration(
        capabilities: [.filesystem],
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

    let call = HiveToolCall(id: "scratch-1", name: "scratch_read", argumentsJSON: #"{}"#)
    let model = ToolCallSequenceModel(toolCalls: [call], finalContent: "ok")

    let context = ColonyContext(configuration: configuration, filesystem: fs)
    let environment = HiveEnvironment<ColonySchema>(
        context: context,
        clock: NoopClock(),
        logger: NoopLogger(),
        model: AnyHiveModelClient(model)
    )
    let runtime = HiveRuntime(graph: graph, environment: environment)
    let threadID = HiveThreadID("thread-scratchbook-exec-gate")

    let handle = await runtime.run(
        threadID: threadID,
        input: "hi",
        options: HiveRunOptions(checkpointPolicy: .disabled)
    )
    let outcome = try await handle.outcome.value
    guard case let .finished(output, _) = outcome, case let .fullStore(store) = output else {
        #expect(Bool(false))
        return
    }

    let messages = try store.get(ColonySchema.Channels.messages)
    let toolMessage = messages.first { $0.role == .tool && $0.name == "scratch_read" }
    #expect(toolMessage != nil)
    #expect(toolMessage?.content.hasPrefix("Error:") == true)

    // No scratchbook file should be created/written when gated off.
    let scratchbookPath = try scratchbookFilePath(prefix: try ColonyVirtualPath("/scratchbook"), threadID: threadID)
    await #expect(throws: ColonyFileSystemError.notFound(scratchbookPath)) {
        _ = try await baseFS.read(at: scratchbookPath)
    }

    let ops = await fs.recordedOperations()
    #expect(ops.contains { op in
        switch op {
        case .write, .edit:
            return true
        case .read, .list, .glob, .grep:
            return false
        }
    } == false)

    #expect(ops.allSatisfy { op in
        switch op {
        case .read(let path):
            return path == scratchbookPath
        case .write, .edit, .list, .glob, .grep:
            return false
        }
    })
}

@Test("Scratchbook tools persist mutations and are scoped to the thread scratchbook file")
func scratchbookTools_persistAndAreThreadScoped() async throws {
    let graph = try ColonyAgent.compile()
    let baseFS = ColonyInMemoryFileSystemBackend()

    let prefix = try ColonyVirtualPath("/scratchbook")
    let threadID = HiveThreadID("thread-scratchbook-crud")
    let scratchbookPath = try scratchbookFilePath(prefix: prefix, threadID: threadID)

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

    // 1) Add an item (with a malicious path parameter that must be ignored).
    let add = HiveToolCall(
        id: "scratch-add",
        name: "scratch_add",
        argumentsJSON: #"{"kind":"note","title":"Alpha","body":"hello","tags":["t1"],"path":"/evil.json"}"#
    )
    let fs1 = RecordingFileSystemBackend(base: baseFS)
    let model1 = ToolCallSequenceModel(toolCalls: [add], finalContent: "ok")
    let context1 = ColonyContext(configuration: configuration, filesystem: fs1)
    let env1 = HiveEnvironment<ColonySchema>(
        context: context1,
        clock: NoopClock(),
        logger: NoopLogger(),
        model: AnyHiveModelClient(model1)
    )
    let runtime1 = HiveRuntime(graph: graph, environment: env1)
    _ = try await (await runtime1.run(
        threadID: threadID,
        input: "hi",
        options: HiveRunOptions(checkpointPolicy: .disabled)
    )).outcome.value

    let scratchbookText = try await baseFS.read(at: scratchbookPath)
    let scratchbookJSON = try decodeScratchbookJSON(scratchbookText)
    let id = firstScratchItemID(from: scratchbookJSON)
    #expect(id != nil)

    // 2) Pin the item.
    let pin = HiveToolCall(id: "scratch-pin", name: "scratch_pin", argumentsJSON: #"{"id":"\#(id!)"}"#)
    let fs2 = RecordingFileSystemBackend(base: baseFS)
    let model2 = ToolCallSequenceModel(toolCalls: [pin], finalContent: "ok")
    let context2 = ColonyContext(configuration: configuration, filesystem: fs2)
    let env2 = HiveEnvironment<ColonySchema>(
        context: context2,
        clock: NoopClock(),
        logger: NoopLogger(),
        model: AnyHiveModelClient(model2)
    )
    let runtime2 = HiveRuntime(graph: graph, environment: env2)
    _ = try await (await runtime2.run(
        threadID: threadID,
        input: "pin",
        options: HiveRunOptions(checkpointPolicy: .disabled)
    )).outcome.value

    let pinnedText = try await baseFS.read(at: scratchbookPath)
    let pinnedJSON = try decodeScratchbookJSON(pinnedText)
    let pinnedIDs = pinnedJSON["pinnedItemIDs"] as? [String] ?? []
    #expect(pinnedIDs.contains(id!))

    // 3) Mutate: update → complete → unpin → read.
    let update = HiveToolCall(id: "scratch-update", name: "scratch_update", argumentsJSON: #"{"id":"\#(id!)","title":"Alpha (updated)"}"#)
    let complete = HiveToolCall(id: "scratch-complete", name: "scratch_complete", argumentsJSON: #"{"id":"\#(id!)"}"#)
    let unpin = HiveToolCall(id: "scratch-unpin", name: "scratch_unpin", argumentsJSON: #"{"id":"\#(id!)"}"#)
    let read = HiveToolCall(id: "scratch-read", name: "scratch_read", argumentsJSON: #"{}"#)

    let fs3 = RecordingFileSystemBackend(base: baseFS)
    let model3 = ToolCallSequenceModel(toolCalls: [update, complete, unpin, read], finalContent: "done")
    let context3 = ColonyContext(configuration: configuration, filesystem: fs3)
    let env3 = HiveEnvironment<ColonySchema>(
        context: context3,
        clock: NoopClock(),
        logger: NoopLogger(),
        model: AnyHiveModelClient(model3)
    )
    let runtime3 = HiveRuntime(graph: graph, environment: env3)
    let handle3 = await runtime3.run(
        threadID: threadID,
        input: "mutate",
        options: HiveRunOptions(checkpointPolicy: .disabled)
    )
    let outcome3 = try await handle3.outcome.value
    guard case let .finished(output3, _) = outcome3, case let .fullStore(store3) = output3 else {
        #expect(Bool(false))
        return
    }

    let mutatedText = try await baseFS.read(at: scratchbookPath)
    let mutatedJSON = try decodeScratchbookJSON(mutatedText)

    let mutatedItem = scratchItem(withID: id!, in: mutatedJSON)
    #expect((mutatedItem?["title"] as? String) == "Alpha (updated)")
    #expect((mutatedItem?["status"] as? String) == "done")

    // Pin metadata should be round-tripped and end up unpinned.
    let pinned = mutatedJSON["pinnedItemIDs"] as? [String] ?? []
    #expect(pinned.contains(id!) == false)

    // `scratch_read` should return a compact view that includes the updated title.
    let messages3 = try store3.get(ColonySchema.Channels.messages)
    let scratchReadTool = messages3.last { $0.role == HiveChatRole.tool && $0.name == "scratch_read" }
    #expect(scratchReadTool != nil)
    #expect(scratchReadTool?.content.contains("Alpha (updated)") == true)

    // Strict scoping: only the thread scratchbook file may be touched.
    let ops1 = await fs1.recordedOperations()
    let ops2 = await fs2.recordedOperations()
    let ops3 = await fs3.recordedOperations()
    for ops in [ops1, ops2, ops3] {
        #expect(ops.allSatisfy { op in
            switch op {
            case .read(let path),
                 .write(let path, _),
                 .edit(let path, _, _, _):
                return path == scratchbookPath
            case .list, .glob, .grep:
                return false
            }
        })
    }
}

@Test("On-device profile tool approval allowlist includes scratchbook tool names")
func onDeviceAllowList_includesScratchbookToolNames() throws {
    let config = ColonyAgentFactory.configuration(profile: .onDevice4k, modelName: "test-model")
    #expect(config.capabilities.contains(.scratchbook))
    guard case let .allowList(allowed) = config.toolApprovalPolicy else {
        #expect(Bool(false))
        return
    }

    #expect(allowed.contains("scratch_read"))
    #expect(allowed.contains("scratch_add"))
    #expect(allowed.contains("scratch_update"))
    #expect(allowed.contains("scratch_complete"))
    #expect(allowed.contains("scratch_pin"))
    #expect(allowed.contains("scratch_unpin"))
}
