import ColonyCore
import Foundation
import HiveCheckpointWax
import HiveCore
import Membrane
import MembraneCore
import MembraneWax
import Swarm
import Testing
@testable import Colony

@Suite("ColonyBootstrap Integration")
struct ColonyBootstrapIntegrationTests {
    @Test("Colony bootstrap provisions Wax memory and Membrane ContextCore by default")
    func colonyBootstrap_defaultsProvisionFullContextAndMemoryStack() async throws {
        let threadID = HiveThreadID("colony/bootstrap/default-stack/\(UUID().uuidString.lowercased())")
        let storageRoot = defaultBootstrapStorageRoot(for: threadID)
        defer { try? FileManager.default.removeItem(at: storageRoot) }

        let bootstrap = ColonyBootstrap()
        let result = try await bootstrap.bootstrap(
            profile: .onDevice4k,
            threadID: threadID,
            modelName: "bootstrap-defaults"
        )
        let defaultModelClient: ColonyDefaultConduitModelClient = bootstrap.makeDefaultModelClient(
            modelName: "bootstrap-defaults"
        )
        _ = defaultModelClient

        #expect(result.memoryBackend is ColonyWaxMemoryBackend)
        let sessionAdapter = try #require(result.membraneEnvironment.adapter as? SessionMembraneAgentAdapter)
        let snapshot = try await sessionAdapter.contextSnapshot()

        let remembered = try await result.memoryBackend.remember(
            ColonyMemoryRememberRequest(content: "default stack memory")
        )
        let recalled = try await result.memoryBackend.recall(
            ColonyMemoryRecallRequest(query: "default stack", limit: 5)
        )

        #expect(snapshot?.backendID == "contextcore")
        #expect(remembered.id.isEmpty == false)
        #expect(recalled.items.contains { $0.content.contains("default stack memory") })
    }

    @Test("Colony bootstrap creates a Swarm membrane environment backed by ContextCore")
    func colonyBootstrap_createsSwarmMembraneEnvironmentBackedByContextCore() async throws {
        let directory = try temporaryDirectory("bootstrap-membrane")
        defer { try? FileManager.default.removeItem(at: directory) }

        let memoryURL = directory.appendingPathComponent("memory.wax", isDirectory: false)
        let bootstrap = ColonyBootstrap()
        let membrane = try await bootstrap.makeMembraneEnvironment(memoryStoreURL: memoryURL)
        let provider = RecordingConversationProvider()

        let agent = try Agent(
            tools: [],
            instructions: "Use the provided context pipeline.",
            configuration: AgentConfiguration(
                name: "colony-bootstrap-membrane",
                contextMode: .strict4k,
                defaultTracingEnabled: false
            ),
            inferenceProvider: provider
        ).environment(\.membrane, membrane)

        let result = try await agent.run("bootstrap test input")
        #expect(result.output == "bootstrap-ok")

        let sessionAdapter = try #require(membrane.adapter as? SessionMembraneAgentAdapter)
        let snapshot = try await sessionAdapter.contextSnapshot()
        #expect(snapshot?.backendID == "contextcore")

        let messages = provider.lastMessages()
        #expect(messages?.contains(where: { $0.role == .user && $0.content.contains("bootstrap test input") }) == true)
    }

    @Test("Colony bootstrap injects membrane-derived context into Colony model requests")
    func colonyBootstrap_runtimeUsesMembraneContextInPrompt() async throws {
        let directory = try temporaryDirectory("bootstrap-runtime-membrane")
        defer { try? FileManager.default.removeItem(at: directory) }

        let membraneURL = directory.appendingPathComponent("membrane.wax", isDirectory: false)
        let storage = try await WaxStorageBackend.create(at: membraneURL)
        _ = try await storage.storeContextFrame(
            "Deployment guidance: prefer the macOS target for membrane-probe-token investigations."
        )
        try await storage.close()

        let model = PromptCaptureModel()
        let bootstrap = ColonyBootstrap()
        let result = try await bootstrap.bootstrap(
            profile: .onDevice4k,
            threadID: HiveThreadID("colony/bootstrap/runtime-membrane/\(UUID().uuidString.lowercased())"),
            modelName: "bootstrap-membrane-runtime",
            model: AnyHiveModelClient(model),
            membraneStoreURL: membraneURL,
            configure: { configuration in
                configuration.model.capabilities = [.planning]
                configuration.context.summarizationPolicy = nil
                configuration.context.toolResultEvictionTokenLimit = nil
            }
        )

        let handle = await result.runtime.sendUserMessage("What deployment target should I use for membrane-probe-token?")
        let outcome = try await handle.outcome.value
        guard case .finished = outcome else {
            Issue.record("Expected runtime to finish successfully.")
            return
        }

        let systemPrompt = try #require(model.lastSystemPrompt())
        #expect(systemPrompt.contains("Membrane Context:"))
        #expect(systemPrompt.contains("prefer the macOS target"))
    }

    @Test("Colony bootstrap durable memory uses Wax provenance instead of runtime checkpoints")
    func colonyBootstrap_durableMemoryUsesWaxProvenance() async throws {
        let directory = try temporaryDirectory("bootstrap-memory")
        defer { try? FileManager.default.removeItem(at: directory) }

        let memoryURL = directory.appendingPathComponent("memory.wax", isDirectory: false)
        let bootstrap = ColonyBootstrap()
        let memory = try await bootstrap.makeMemoryBackend(at: memoryURL)

        let remembered = try await memory.remember(
            ColonyMemoryRememberRequest(
                content: "Wax keeps durable memory separate from checkpoints.",
                tags: ["architecture"],
                metadata: ["topic": "boundaries"]
            )
        )
        let recalled = try await memory.recall(
            ColonyMemoryRecallRequest(query: "durable memory", limit: 5)
        )

        let item = try #require(recalled.items.first)
        #expect(item.id == remembered.id)
        #expect(item.tags == ["architecture"])
        #expect(item.metadata["colony.memory.provenance.backendID"] == "wax")
        #expect(item.metadata["colony.memory.provenance.kind"] != "hive.checkpoint")
        #expect(item.content.contains("durable memory"))
    }

    @Test("Colony bootstrap resumes interrupted runs from HiveCheckpointWax without polluting Wax memory")
    func colonyBootstrap_resumesInterruptedRunsFromHiveCheckpointWax() async throws {
        let directory = try temporaryDirectory("bootstrap-runtime")
        defer { try? FileManager.default.removeItem(at: directory) }

        let checkpointURL = directory.appendingPathComponent("checkpoints.wax", isDirectory: false)
        let memoryURL = directory.appendingPathComponent("memory.wax", isDirectory: false)
        let filesystem = ColonyInMemoryFileSystemBackend()
        let threadID = HiveThreadID("colony-bootstrap-resume")
        let bootstrap = ColonyBootstrap()

        let memory = try await bootstrap.makeMemoryBackend(at: memoryURL)
        _ = try await memory.remember(
            ColonyMemoryRememberRequest(
                content: "Durable note for runtime separation.",
                metadata: ["source": "integration-test"]
            )
        )

        let firstRuntime = try await bootstrap.makeRuntime(
            profile: .onDevice4k,
            threadID: threadID,
            modelName: "bootstrap-runtime",
            model: AnyHiveModelClient(InterruptingWriteModel()),
            filesystem: filesystem,
            memory: memory,
            durableCheckpointStoreURL: checkpointURL,
            configure: { configuration in
                configuration.model.capabilities = [.filesystem, .memory]
                configuration.safety.toolApprovalPolicy = .always
                configuration.context.summarizationPolicy = nil
                configuration.context.toolResultEvictionTokenLimit = nil
            }
        )

        let firstHandle = await firstRuntime.sendUserMessage("Write the checkpoint file")
        let firstOutcome = try await firstHandle.outcome.value
        guard case let .interrupted(interruption) = firstOutcome else {
            Issue.record("Expected the first runtime to interrupt for tool approval.")
            return
        }

        let checkpointStore = try await HiveCheckpointWaxStore<ColonySchema>.open(at: checkpointURL)
        let latestCheckpoint = try await checkpointStore.loadLatest(threadID: threadID)
        #expect(latestCheckpoint?.interruption?.id == interruption.interruptID.hive)

        let secondRuntime = try await bootstrap.makeRuntime(
            profile: .onDevice4k,
            threadID: threadID,
            modelName: "bootstrap-runtime",
            model: AnyHiveModelClient(FinalAnswerModel(content: "resume-finished")),
            filesystem: filesystem,
            memory: memory,
            durableCheckpointStoreURL: checkpointURL,
            configure: { configuration in
                configuration.model.capabilities = [.filesystem, .memory]
                configuration.safety.toolApprovalPolicy = .always
                configuration.context.summarizationPolicy = nil
                configuration.context.toolResultEvictionTokenLimit = nil
            }
        )

        let resumedHandle = await secondRuntime.resumeToolApproval(
            interruptID: interruption.interruptID,
            decision: .approved
        )
        let resumedOutcome = try await resumedHandle.outcome.value
        guard case let .finished(transcript, _) = resumedOutcome else {
            Issue.record("Expected resumed runtime to finish successfully.")
            return
        }

        let finalAnswer = transcript.finalAnswer
        let written = try await filesystem.read(at: try ColonyVirtualPath("/checkpoint.md"))
        let recalled = try await memory.recall(ColonyMemoryRecallRequest(query: "durable note", limit: 5))

        #expect(finalAnswer == "resume-finished")
        #expect(written == "checkpoint")
        #expect(recalled.items.count == 1)
        #expect(recalled.items.first?.content == "Durable note for runtime separation.")
        #expect(recalled.items.first?.metadata["colony.memory.provenance.kind"] != "hive.checkpoint")
    }
}

private final class RecordingConversationProvider: ConversationInferenceProvider, @unchecked Sendable {
    private let lock = NSLock()
    private var storedMessages: [InferenceMessage] = []

    func lastMessages() -> [InferenceMessage]? {
        lock.lock()
        defer { lock.unlock() }
        return storedMessages.isEmpty ? nil : storedMessages
    }

    private func record(_ messages: [InferenceMessage]) {
        lock.lock()
        storedMessages = messages
        lock.unlock()
    }

    func generate(prompt: String, options: InferenceOptions) async throws -> String {
        record([.user(prompt)])
        return "bootstrap-ok"
    }

    func stream(prompt: String, options: InferenceOptions) -> AsyncThrowingStream<String, Error> {
        record([.user(prompt)])
        return AsyncThrowingStream { continuation in
            continuation.yield("bootstrap-ok")
            continuation.finish()
        }
    }

    func generateWithToolCalls(
        prompt: String,
        tools: [ToolSchema],
        options: InferenceOptions
    ) async throws -> InferenceResponse {
        record([.user(prompt)])
        return InferenceResponse(content: "bootstrap-ok", toolCalls: [], finishReason: .completed)
    }

    func generate(messages: [InferenceMessage], options: InferenceOptions) async throws -> String {
        record(messages)
        return "bootstrap-ok"
    }

    func generateWithToolCalls(
        messages: [InferenceMessage],
        tools: [ToolSchema],
        options: InferenceOptions
    ) async throws -> InferenceResponse {
        record(messages)
        return InferenceResponse(content: "bootstrap-ok", toolCalls: [], finishReason: .completed)
    }
}

private final class PromptCaptureModel: HiveModelClient, @unchecked Sendable {
    private let lock = NSLock()
    private var systemPrompt: String?

    func lastSystemPrompt() -> String? {
        lock.lock()
        defer { lock.unlock() }
        return systemPrompt
    }

    func complete(_ request: HiveChatRequest) async throws -> HiveChatResponse {
        capture(from: request)
        return HiveChatResponse(
            message: HiveChatMessage(id: "assistant-capture", role: .assistant, content: "captured")
        )
    }

    func stream(_ request: HiveChatRequest) -> AsyncThrowingStream<HiveChatStreamChunk, Error> {
        capture(from: request)
        return AsyncThrowingStream { continuation in
            continuation.yield(.final(HiveChatResponse(
                message: HiveChatMessage(id: "assistant-capture", role: .assistant, content: "captured")
            )))
            continuation.finish()
        }
    }

    private func capture(from request: HiveChatRequest) {
        lock.lock()
        systemPrompt = request.messages.first(where: { $0.role == .system })?.content
        lock.unlock()
    }
}

private final class InterruptingWriteModel: HiveModelClient, @unchecked Sendable {
    func complete(_ request: HiveChatRequest) async throws -> HiveChatResponse {
        HiveChatResponse(
            message: HiveChatMessage(
                id: "assistant-write",
                role: .assistant,
                content: "needs approval",
                toolCalls: [
                    HiveToolCall(
                        id: "approval-write-1",
                        name: "write_file",
                        argumentsJSON: #"{"path":"/checkpoint.md","content":"checkpoint"}"#
                    ),
                ]
            )
        )
    }

    func stream(_ request: HiveChatRequest) -> AsyncThrowingStream<HiveChatStreamChunk, Error> {
        AsyncThrowingStream { continuation in
            Task {
                continuation.yield(.final(try await self.complete(request)))
                continuation.finish()
            }
        }
    }
}

private final class FinalAnswerModel: HiveModelClient, @unchecked Sendable {
    private let content: String

    init(content: String) {
        self.content = content
    }

    func complete(_ request: HiveChatRequest) async throws -> HiveChatResponse {
        HiveChatResponse(
            message: HiveChatMessage(
                id: "assistant-final",
                role: .assistant,
                content: content
            )
        )
    }

    func stream(_ request: HiveChatRequest) -> AsyncThrowingStream<HiveChatStreamChunk, Error> {
        AsyncThrowingStream { continuation in
            Task {
                continuation.yield(.final(try await self.complete(request)))
                continuation.finish()
            }
        }
    }
}

private func defaultBootstrapStorageRoot(for threadID: HiveThreadID) -> URL {
    let baseDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        ?? FileManager.default.temporaryDirectory
    let sanitized = sanitizedPathComponent(threadID.rawValue)
    return baseDirectory
        .appendingPathComponent("AIStack", isDirectory: true)
        .appendingPathComponent("Colony", isDirectory: true)
        .appendingPathComponent(sanitized, isDirectory: true)
}

private func sanitizedPathComponent(_ rawValue: String) -> String {
    let sanitized = rawValue.map { character -> Character in
        if character.isLetter || character.isNumber || character == "-" || character == "_" {
            return character
        }
        return "-"
    }
    let collapsed = String(sanitized).trimmingCharacters(in: CharacterSet(charactersIn: "-_"))
    return collapsed.isEmpty ? "default" : collapsed
}

private func temporaryDirectory(_ suffix: String) throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("colony-bootstrap-tests", isDirectory: true)
        .appendingPathComponent(suffix + "-" + UUID().uuidString.lowercased(), isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}
