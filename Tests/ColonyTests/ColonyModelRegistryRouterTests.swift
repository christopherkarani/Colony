import Foundation
import Testing
@testable import Colony

private final class RecordingModelClient: HiveModelClient, @unchecked Sendable {
    private let lock = NSLock()
    private var models: [String] = []
    private let responseContent: String

    init(responseContent: String) {
        self.responseContent = responseContent
    }

    func complete(_ request: HiveChatRequest) async throws -> HiveChatResponse {
        try await streamFinal(request)
    }

    func stream(_ request: HiveChatRequest) -> AsyncThrowingStream<HiveChatStreamChunk, Error> {
        AsyncThrowingStream { continuation in
            self.lock.lock()
            self.models.append(request.model)
            self.lock.unlock()

            continuation.yield(
                .final(
                    HiveChatResponse(
                        message: HiveChatMessage(
                            id: UUID().uuidString,
                            role: .assistant,
                            content: self.responseContent
                        )
                    )
                )
            )
            continuation.finish()
        }
    }

    func recordedModels() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return models
    }
}

@Test("Model registry router routes provider/model and strips provider prefix")
func modelRegistryRouter_routesQualifiedIdentifier() async throws {
    let openAI = RecordingModelClient(responseContent: "openai")
    let anthropic = RecordingModelClient(responseContent: "anthropic")

    let router = ColonyModelRegistryRouter(
        providers: [
            .init(id: "openai", client: AnyHiveModelClient(openAI)),
            .init(id: "anthropic", client: AnyHiveModelClient(anthropic)),
        ]
    )

    let request = HiveChatRequest(
        model: "openai/gpt-4.1",
        messages: [HiveChatMessage(id: "u1", role: .user, content: "hello")],
        tools: []
    )
    let routed = router.route(request, hints: nil)
    let response = try await routed.complete(request)

    #expect(response.message.content == "openai")
    #expect(openAI.recordedModels() == ["gpt-4.1"])
    #expect(anthropic.recordedModels().isEmpty)
}

@Test("Model registry router uses default provider for unqualified model names")
func modelRegistryRouter_usesDefaultProviderForUnqualifiedModel() async throws {
    let defaultProvider = RecordingModelClient(responseContent: "default")

    let router = ColonyModelRegistryRouter(
        providers: [.init(id: "openai", client: AnyHiveModelClient(defaultProvider))],
        defaultProviderID: "openai"
    )

    let request = HiveChatRequest(
        model: "gpt-4o-mini",
        messages: [HiveChatMessage(id: "u1", role: .user, content: "hello")],
        tools: []
    )
    let routed = router.route(request, hints: nil)
    let response = try await routed.complete(request)

    #expect(response.message.content == "default")
    #expect(defaultProvider.recordedModels() == ["gpt-4o-mini"])
}

@Test("Model registry router throws deterministic error for unknown provider")
func modelRegistryRouter_throwsUnknownProvider() async throws {
    let router = ColonyModelRegistryRouter(
        providers: [.init(id: "openai", client: AnyHiveModelClient(RecordingModelClient(responseContent: "unused")))]
    )

    let request = HiveChatRequest(
        model: "anthropic/claude-sonnet-4",
        messages: [HiveChatMessage(id: "u1", role: .user, content: "hello")],
        tools: []
    )
    let routed = router.route(request, hints: nil)

    do {
        _ = try await routed.complete(request)
        Issue.record("Expected unknown provider error.")
    } catch let error as ColonyModelRegistryRouterError {
        #expect(error == .unknownProvider("anthropic"))
    }
}

@Test("Model registry router rejects malformed provider/model identifiers")
func modelRegistryRouter_rejectsMalformedIdentifier() async throws {
    let router = ColonyModelRegistryRouter(
        providers: [.init(id: "openai", client: AnyHiveModelClient(RecordingModelClient(responseContent: "unused")))]
    )

    let request = HiveChatRequest(
        model: "openai/",
        messages: [HiveChatMessage(id: "u1", role: .user, content: "hello")],
        tools: []
    )
    let routed = router.route(request, hints: nil)

    do {
        _ = try await routed.complete(request)
        Issue.record("Expected malformed model identifier error.")
    } catch let error as ColonyModelRegistryRouterError {
        #expect(error == .malformedModelIdentifier("openai/"))
    }
}

@Test("Model registry router stream path preserves final chunk")
func modelRegistryRouter_streamPathWorks() async throws {
    let openAI = RecordingModelClient(responseContent: "stream-ok")
    let router = ColonyModelRegistryRouter(
        providers: [.init(id: "openai", client: AnyHiveModelClient(openAI))]
    )
    let request = HiveChatRequest(
        model: "openai/gpt-4o-mini",
        messages: [HiveChatMessage(id: "u1", role: .user, content: "hello")],
        tools: []
    )
    let routed = router.route(request, hints: nil)

    var finalContent: String?
    for try await chunk in routed.stream(request) {
        if case let .final(response) = chunk {
            finalContent = response.message.content
        }
    }

    #expect(finalContent == "stream-ok")
    #expect(openAI.recordedModels() == ["gpt-4o-mini"])
}
