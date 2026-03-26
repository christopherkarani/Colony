import Foundation
import Testing
@testable import Colony

// MARK: - Test Fixtures

private func makeRequest(complexity: ColonyInferenceRequest.Complexity = .automatic) -> ColonyInferenceRequest {
    ColonyInferenceRequest(
        messages: [
            ColonyMessage(
                id: "1",
                role: .user,
                content: "hi"
            )
        ],
        tools: [],
        complexity: complexity
    )
}

private final class FixedResponseModel: ColonyModelClient, @unchecked Sendable {
    let content: String
    let providerID: String

    init(content: String, providerID: String = "fixed") {
        self.content = content
        self.providerID = providerID
    }

    func generate(_ request: ColonyInferenceRequest) async throws -> ColonyInferenceResponse {
        ColonyInferenceResponse(
            message: ColonyMessage(
                id: UUID().uuidString,
                role: .assistant,
                content: "[\(providerID)]: \(content)"
            ),
            providerID: providerID
        )
    }

    func stream(_ request: ColonyInferenceRequest) -> AsyncThrowingStream<ColonyInferenceStreamChunk, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(.final(ColonyInferenceResponse(
                message: ColonyMessage(
                    id: UUID().uuidString,
                    role: .assistant,
                    content: "[\(providerID)]: \(content)"
                ),
                providerID: providerID
            )))
            continuation.finish()
        }
    }
}

private final class FailingModel: ColonyModelClient, @unchecked Sendable {
    let error: Error

    init(error: Error) {
        self.error = error
    }

    func generate(_ request: ColonyInferenceRequest) async throws -> ColonyInferenceResponse {
        throw error
    }

    func stream(_ request: ColonyInferenceRequest) -> AsyncThrowingStream<ColonyInferenceStreamChunk, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish(throwing: error)
        }
    }
}

// MARK: - ColonyModelRouter Tests

@Test("Single strategy routes to the provided client")
func singleStrategy_routesToClient() async throws {
    let client = FixedResponseModel(content: "hello", providerID: "single")
    let router = ColonyModelRouter(strategy: .single(client))

    let response = try await router.generate(makeRequest())
    #expect(response.content.contains("[single]: hello"))
}

@Test("Prioritized strategy tries providers in order")
func prioritizedStrategy_triesProvidersInOrder() async throws {
    let failingClient = FailingModel(error: TestError.generic)
    let successClient = FixedResponseModel(content: "success", providerID: "backup")

    let routes = [
        ColonyModelRouter.ProviderRoute(
            providerID: "primary",
            client: failingClient,
            weight: 1.0
        ),
        ColonyModelRouter.ProviderRoute(
            providerID: "backup",
            client: successClient,
            weight: 1.0
        )
    ]

    let policy = ColonyModelRouter.RetryPolicy(
        maxAttempts: 1,
        initialBackoff: .zero
    )

    let router = ColonyModelRouter(strategy: .prioritized(routes, policy))

    let response = try await router.generate(makeRequest())
    #expect(response.content.contains("[backup]: success"))
}

@Test("Prioritized strategy throws when all providers fail")
func prioritizedStrategy_throwsWhenAllFail() async throws {
    let failingClient1 = FailingModel(error: TestError.provider1)
    let failingClient2 = FailingModel(error: TestError.provider2)

    let routes = [
        ColonyModelRouter.ProviderRoute(
            providerID: "p1",
            client: failingClient1,
            weight: 1.0
        ),
        ColonyModelRouter.ProviderRoute(
            providerID: "p2",
            client: failingClient2,
            weight: 1.0
        )
    ]

    let policy = ColonyModelRouter.RetryPolicy(
        maxAttempts: 1,
        initialBackoff: .zero
    )

    let router = ColonyModelRouter(strategy: .prioritized(routes, policy))

    await #expect(throws: ColonyModelRouterError.self) {
        _ = try await router.generate(makeRequest())
    }
}

@Test("OnDevice strategy uses on-device when available")
func onDeviceStrategy_usesOnDeviceWhenAvailable() async throws {
    let onDeviceClient = FixedResponseModel(content: "on-device", providerID: "local")
    let fallbackClient = FixedResponseModel(content: "cloud", providerID: "remote")

    let router = ColonyModelRouter(strategy: .onDevice(
        onDevice: onDeviceClient,
        fallback: fallbackClient,
        privacy: .preferOnDevice
    ))

    let response = try await router.generate(makeRequest())
    #expect(response.content.contains("[local]: on-device"))
}

@Test("OnDevice strategy falls back when on-device is nil")
func onDeviceStrategy_fallsBackWhenNil() async throws {
    let fallbackClient = FixedResponseModel(content: "cloud", providerID: "remote")

    let router = ColonyModelRouter(strategy: .onDevice(
        onDevice: nil,
        fallback: fallbackClient,
        privacy: .preferOnDevice
    ))

    let response = try await router.generate(makeRequest())
    #expect(response.content.contains("[remote]: cloud"))
}

@Test("OnDevice strategy respects privacy behavior for complex tasks")
func onDeviceStrategy_respectsPrivacyBehavior() async throws {
    let onDeviceClient = FixedResponseModel(content: "on-device", providerID: "local")
    let fallbackClient = FixedResponseModel(content: "cloud", providerID: "remote")

    // With .alwaysCloud, should always use fallback regardless of on-device availability
    let router = ColonyModelRouter(strategy: .onDevice(
        onDevice: onDeviceClient,
        fallback: fallbackClient,
        privacy: .alwaysCloud
    ))

    let response = try await router.generate(makeRequest(complexity: .complex))
    #expect(response.content.contains("[remote]: cloud"))
}

@Test("CostOptimized strategy selects lowest cost provider")
func costOptimizedStrategy_selectsLowestCost() async throws {
    let expensiveClient = FixedResponseModel(content: "expensive", providerID: "premium")
    let cheapClient = FixedResponseModel(content: "cheap", providerID: "budget")

    let routes = [
        ColonyModelRouter.ProviderRoute(
            providerID: "premium",
            client: expensiveClient,
            weight: 2.0  // Higher weight = higher cost
        ),
        ColonyModelRouter.ProviderRoute(
            providerID: "budget",
            client: cheapClient,
            weight: 0.5  // Lower weight = lower cost
        )
    ]

    let costPolicy = ColonyModelRouter.CostPolicy(
        costCeilingUSD: 100.0,
        preferLowerCost: true
    )

    let router = ColonyModelRouter(strategy: .costOptimized(routes, costPolicy))

    let response = try await router.generate(makeRequest())
    // Should prefer the cheaper option
    #expect(response.content.contains("[budget]: cheap"))
}

@Test("Router generates streaming responses")
func router_generatesStreamingResponses() async throws {
    let client = FixedResponseModel(content: "streamed", providerID: "test")
    let router = ColonyModelRouter(strategy: .single(client))

    var chunks: [String] = []
    for try await chunk in router.stream(makeRequest()) {
        switch chunk {
        case .token(let text):
            chunks.append(text)
        case .final(let response):
            chunks.append(response.content)
        }
    }

    #expect(chunks.count > 0)
}

@Test("ProviderRoute initializes with correct values")
func providerRoute_initializesCorrectly() async throws {
    let client = FixedResponseModel(content: "test")
    let route = ColonyModelRouter.ProviderRoute(
        providerID: "test-provider",
        client: client,
        weight: 1.5
    )

    #expect(route.providerID == "test-provider")
    #expect(route.weight == 1.5)
}

@Test("RetryPolicy has correct default values")
func retryPolicy_defaultValues() async throws {
    let policy = ColonyModelRouter.RetryPolicy()

    #expect(policy.maxAttempts == 3)
}

@Test("CostPolicy has correct default values")
func costPolicy_defaultValues() async throws {
    let policy = ColonyModelRouter.CostPolicy()

    #expect(policy.costCeilingUSD == nil)
    #expect(policy.preferLowerCost == true)
}

@Test("InferenceRequest complexity defaults to automatic")
func inferenceRequest_complexityDefaultsToAutomatic() async throws {
    let request = makeRequest()

    #expect(request.complexity == .automatic)
}

@Test("InferenceResponse creates with content and metadata")
func inferenceResponse_createsCorrectly() async throws {
    let response = ColonyInferenceResponse(
        message: ColonyMessage(
            id: "assistant-1",
            role: .assistant,
            content: "Hello"
        ),
        usage: ColonyInferenceResponse.Usage(promptTokens: 10, completionTokens: 5),
        providerID: "test"
    )

    #expect(response.content == "Hello")
    #expect(response.usage?.promptTokens == 10)
    #expect(response.usage?.completionTokens == 5)
    #expect(response.providerID == "test")
}

// MARK: - Error Tests

@Test("NoEligibleProvider error contains provider reasons")
func noEligibleProvider_errorContainsReasons() async throws {
    let error = ColonyModelRouterError.noEligibleProvider(reasons: [
        "provider1: rate limited",
        "provider2: cost exceeded"
    ])

    let description = error.localizedDescription
    #expect(description.contains("rate limited"))
    #expect(description.contains("cost exceeded"))
}

@Test("NoProvidersConfigured error has correct description")
func noProvidersConfigured_errorDescription() async throws {
    let error = ColonyModelRouterError.noProvidersConfigured
    #expect(error.localizedDescription.contains("No providers"))
}

// MARK: - Deprecation Shim Tests

@Test("Legacy ColonyProviderRouter is deprecated but functional")
func legacyProviderRouter_stillFunctional() async throws {
    let client = FixedResponseModel(content: "legacy", providerID: "legacy")
    let provider = ColonyProviderRouter.Provider(
        id: "test",
        client: client,
        priority: 0
    )

    let router = ColonyProviderRouter(providers: [provider])
    let response = try await router.generate(makeRequest())
    #expect(response.content.contains("legacy"))
}

@Test("Legacy ColonyOnDeviceModelRouter is deprecated but functional")
func legacyOnDeviceRouter_stillFunctional() async throws {
    let onDevice = FixedResponseModel(content: "local", providerID: "local")
    let fallback = FixedResponseModel(content: "cloud", providerID: "cloud")
    let router = ColonyOnDeviceModelRouter(
        onDevice: onDevice,
        fallback: fallback,
        policy: ColonyOnDeviceModelRouter.Policy()
    )
    let response = try await router.generate(makeRequest())
    #expect(response.content.contains("local"))
}

// MARK: - Test Helpers

private enum TestError: Error {
    case generic
    case provider1
    case provider2
}
