import Foundation
import Testing
@_spi(ColonyInternal) import Swarm
@testable import Colony

private final class FixedResponseModel: SwarmModelClient, @unchecked Sendable {
    private let content: String

    init(content: String) {
        self.content = content
    }

    func complete(_ request: SwarmChatRequest) async throws -> SwarmChatResponse {
        SwarmChatResponse(message: SwarmChatMessage(id: UUID().uuidString, role: .assistant, content: content))
    }

    func stream(_ request: SwarmChatRequest) -> AsyncThrowingStream<SwarmChatStreamChunk, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(.final(SwarmChatResponse(message: SwarmChatMessage(id: UUID().uuidString, role: .assistant, content: content))))
            continuation.finish()
        }
    }
}

@Test("On-device router falls back when no inference hints are provided")
func onDeviceRouter_defaultsToFallbackWhenHintsMissing() async throws {
    let router = ColonyOnDeviceModelRouter(
        onDevice: SwarmAnyModelClient(FixedResponseModel(content: "on-device")),
        fallback: SwarmAnyModelClient(FixedResponseModel(content: "fallback"))
    )

    let client = router.route(SwarmChatRequest(model: "test", messages: [], tools: []), hints: nil)
    let response = try await client.complete(SwarmChatRequest(model: "test", messages: [], tools: []))
    #expect(response.message.content == "fallback")
}

@Test("On-device router prefers on-device when privacy is required and available")
func onDeviceRouter_prefersOnDeviceForPrivacyWhenAvailable() async throws {
    let router = ColonyOnDeviceModelRouter(
        onDevice: SwarmAnyModelClient(FixedResponseModel(content: "on-device")),
        fallback: SwarmAnyModelClient(FixedResponseModel(content: "fallback")),
        policy: ColonyOnDeviceModelRouter.Policy(privacyBehavior: .preferOnDevice),
        isOnDeviceAvailable: { true }
    )

    let hints = SwarmInferenceHints(
        latencyTier: .interactive,
        privacyRequired: true,
        tokenBudget: nil,
        networkState: .online
    )

    let client = router.route(SwarmChatRequest(model: "test", messages: [], tools: []), hints: hints)
    let response = try await client.complete(SwarmChatRequest(model: "test", messages: [], tools: []))
    #expect(response.message.content == "on-device")
}

@Test("On-device router can require on-device and fail deterministically when unavailable")
func onDeviceRouter_requiresOnDeviceAndFailsWhenUnavailable() async throws {
    let router = ColonyOnDeviceModelRouter(
        onDevice: SwarmAnyModelClient(FixedResponseModel(content: "on-device")),
        fallback: SwarmAnyModelClient(FixedResponseModel(content: "fallback")),
        policy: ColonyOnDeviceModelRouter.Policy(privacyBehavior: .requireOnDevice),
        isOnDeviceAvailable: { false }
    )

    let hints = SwarmInferenceHints(
        latencyTier: .interactive,
        privacyRequired: true,
        tokenBudget: nil,
        networkState: .online
    )

    let client = router.route(SwarmChatRequest(model: "test", messages: [], tools: []), hints: hints)
    await #expect(throws: OnDeviceRoutingError.onDeviceRequiredButUnavailable) {
        _ = try await client.complete(SwarmChatRequest(model: "test", messages: [], tools: []))
    }
}

