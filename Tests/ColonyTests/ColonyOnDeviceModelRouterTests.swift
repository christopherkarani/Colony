import Foundation
import Testing
@testable import Colony

private final class FixedResponseModel: HiveModelClient, @unchecked Sendable {
    private let content: String

    init(content: String) {
        self.content = content
    }

    func complete(_ request: HiveChatRequest) async throws -> HiveChatResponse {
        HiveChatResponse(message: HiveChatMessage(id: UUID().uuidString, role: .assistant, content: content))
    }

    func stream(_ request: HiveChatRequest) -> AsyncThrowingStream<HiveChatStreamChunk, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(.final(HiveChatResponse(message: HiveChatMessage(id: UUID().uuidString, role: .assistant, content: content))))
            continuation.finish()
        }
    }
}

@Test("On-device router falls back when no inference hints are provided")
func onDeviceRouter_defaultsToFallbackWhenHintsMissing() async throws {
    let router = ColonyOnDeviceModelRouter(
        onDevice: AnyHiveModelClient(FixedResponseModel(content: "on-device")),
        fallback: AnyHiveModelClient(FixedResponseModel(content: "fallback"))
    )

    let client = router.route(HiveChatRequest(model: "test", messages: [], tools: []), hints: nil)
    let response = try await client.complete(HiveChatRequest(model: "test", messages: [], tools: []))
    #expect(response.message.content == "fallback")
}

@Test("On-device router prefers on-device when privacy is required and available")
func onDeviceRouter_prefersOnDeviceForPrivacyWhenAvailable() async throws {
    let router = ColonyOnDeviceModelRouter(
        onDevice: AnyHiveModelClient(FixedResponseModel(content: "on-device")),
        fallback: AnyHiveModelClient(FixedResponseModel(content: "fallback")),
        policy: ColonyOnDeviceModelRouter.Policy(privacyBehavior: .preferOnDevice),
        isOnDeviceAvailable: { true }
    )

    let hints = HiveInferenceHints(
        latencyTier: .interactive,
        privacyRequired: true,
        tokenBudget: nil,
        networkState: .online
    )

    let client = router.route(HiveChatRequest(model: "test", messages: [], tools: []), hints: hints)
    let response = try await client.complete(HiveChatRequest(model: "test", messages: [], tools: []))
    #expect(response.message.content == "on-device")
}

@Test("On-device router can require on-device and fail deterministically when unavailable")
func onDeviceRouter_requiresOnDeviceAndFailsWhenUnavailable() async throws {
    let router = ColonyOnDeviceModelRouter(
        onDevice: AnyHiveModelClient(FixedResponseModel(content: "on-device")),
        fallback: AnyHiveModelClient(FixedResponseModel(content: "fallback")),
        policy: ColonyOnDeviceModelRouter.Policy(privacyBehavior: .requireOnDevice),
        isOnDeviceAvailable: { false }
    )

    let hints = HiveInferenceHints(
        latencyTier: .interactive,
        privacyRequired: true,
        tokenBudget: nil,
        networkState: .online
    )

    let client = router.route(HiveChatRequest(model: "test", messages: [], tools: []), hints: hints)
    await #expect(throws: ColonyOnDeviceModelRouterError.onDeviceRequiredButUnavailable) {
        _ = try await client.complete(HiveChatRequest(model: "test", messages: [], tools: []))
    }
}

