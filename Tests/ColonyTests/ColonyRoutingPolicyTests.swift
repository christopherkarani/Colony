import Foundation
@_spi(ColonyInternal) import Swarm
import Testing
@testable import ColonyCore

// MARK: - Test Fixtures

private struct MockModelClient: ColonyModelClient, Sendable {
    let id: String

    func generate(_ request: ColonyInferenceRequest) async throws -> ColonyInferenceResponse {
        ColonyInferenceResponse(
            message: ColonyMessage(
                id: UUID().uuidString,
                role: .assistant,
                content: "response-\(id)"
            )
        )
    }

    func stream(_ request: ColonyInferenceRequest) -> AsyncThrowingStream<ColonyInferenceStreamChunk, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(
                .final(
                    ColonyInferenceResponse(
                        message: ColonyMessage(
                            id: UUID().uuidString,
                            role: .assistant,
                            content: "response-\(id)"
                        )
                    )
                )
            )
            continuation.finish()
        }
    }
}

// MARK: - RetryPolicy Tests

@Test("RetryPolicy default values are correct")
func retryPolicy_defaultValues() {
    let policy = ColonyCore.RetryPolicy.default

    #expect(policy.maxAttempts == 3)
    #expect(policy.baseDelay == .milliseconds(100))
    #expect(policy.maxDelay == .seconds(10))
}

@Test("RetryPolicy can be initialized with custom values")
func retryPolicy_customValues() {
    let policy = ColonyCore.RetryPolicy(
        maxAttempts: 5,
        baseDelay: .milliseconds(200),
        maxDelay: .seconds(30)
    )

    #expect(policy.maxAttempts == 5)
    #expect(policy.baseDelay == .milliseconds(200))
    #expect(policy.maxDelay == .seconds(30))
}

// MARK: - RoutingStrategy Tests

@Test("RoutingStrategy single holds a model client")
func routingStrategy_single() {
    let client = MockModelClient(id: "test")
    let strategy: RoutingStrategy = .single(client)
    _ = strategy

    // Verify the strategy is created without crashing
    // The actual routing behavior is tested via the router
}

@Test("RoutingStrategy prioritized holds provider routes and retry policy")
func routingStrategy_prioritized() {
    let routes = [
        ProviderRoute(id: "primary", client: MockModelClient(id: "primary"), priority: 1),
        ProviderRoute(id: "secondary", client: MockModelClient(id: "secondary"), priority: 2)
    ]
    let strategy: RoutingStrategy = .prioritized(routes, .default)
    _ = strategy

    // Verify the strategy is created
}

@Test("RoutingStrategy onDevice holds on-device, fallback, and privacy behavior")
func routingStrategy_onDevice() {
    let onDevice = MockModelClient(id: "on-device")
    let fallback = MockModelClient(id: "fallback")
    let strategy: RoutingStrategy = .onDevice(
        onDevice: onDevice,
        fallback: fallback,
        privacy: .preferOnDevice
    )
    _ = strategy

    // Verify the strategy is created
}

@Test("RoutingStrategy costOptimized holds routes and cost policy")
func routingStrategy_costOptimized() {
    let routes = [
        ProviderRoute(id: "cheap", client: MockModelClient(id: "cheap"), priority: 1),
        ProviderRoute(id: "expensive", client: MockModelClient(id: "expensive"), priority: 2)
    ]
    let costPolicy = CostPolicy(
        maxCostPerRequest: Decimal(0.01),
        budgetPeriod: .daily,
        providerPreferences: [:]
    )
    let strategy: RoutingStrategy = .costOptimized(routes, costPolicy)
    _ = strategy

    // Verify the strategy is created
}

// MARK: - ProviderRoute Tests

@Test("ProviderRoute can be initialized with all properties")
func providerRoute_fullInitialization() {
    let client = MockModelClient(id: "test")
    let route = ProviderRoute(
        id: "test-route",
        client: client,
        priority: 1,
        maxRequestsPerMinute: 100,
        usdPer1KTokens: 0.002
    )

    #expect(route.id == "test-route")
    #expect(route.priority == 1)
    #expect(route.maxRequestsPerMinute == 100)
    #expect(route.usdPer1KTokens == 0.002)
}

@Test("ProviderRoute can be initialized with minimal properties")
func providerRoute_minimalInitialization() {
    let client = MockModelClient(id: "test")
    let route = ProviderRoute(
        id: "test-route",
        client: client
    )

    #expect(route.id == "test-route")
    #expect(route.priority == 0)
    #expect(route.maxRequestsPerMinute == nil)
    #expect(route.usdPer1KTokens == nil)
}

// MARK: - CostPolicy Tests

@Test("CostPolicy can be initialized with all properties")
func costPolicy_fullInitialization() {
    let preferences: [ProviderID: CostPreference] = [
        "provider1": CostPreference(maxCostPerRequest: Decimal(0.01))
    ]
    let policy = CostPolicy(
        maxCostPerRequest: Decimal(0.05),
        budgetPeriod: .hourly,
        providerPreferences: preferences
    )

    #expect(policy.maxCostPerRequest == Decimal(0.05))
    #expect(policy.budgetPeriod == .hourly)
    #expect(policy.providerPreferences.count == 1)
}

@Test("CostPolicy can be initialized with no properties")
func costPolicy_minimalInitialization() {
    let policy = CostPolicy()

    #expect(policy.maxCostPerRequest == nil)
    #expect(policy.budgetPeriod == nil)
    #expect(policy.providerPreferences.isEmpty)
}

// MARK: - PrivacyBehavior Tests

@Test("PrivacyBehavior has correct cases")
func privacyBehavior_cases() {
    let prefer: PrivacyBehavior = .preferOnDevice
    let require: PrivacyBehavior = .requireOnDevice

    // Verify both cases can be created
    _ = prefer
    _ = require
}

// MARK: - BudgetPeriod Tests

@Test("BudgetPeriod has correct cases")
func budgetPeriod_cases() {
    let hourly: BudgetPeriod = .hourly
    let daily: BudgetPeriod = .daily
    let weekly: BudgetPeriod = .weekly
    let monthly: BudgetPeriod = .monthly

    // Verify all cases can be created
    _ = hourly
    _ = daily
    _ = weekly
    _ = monthly
}

// MARK: - ColonyRoutingPolicy Tests

@Test("ColonyRoutingPolicy can be initialized with single strategy")
func routingPolicy_singleStrategy() {
    let client = MockModelClient(id: "test")
    let policy = ColonyRoutingPolicy(
        strategy: .single(client),
        retryPolicy: .default
    )
    _ = policy

    // Verify the policy is created
}

@Test("ColonyRoutingPolicy can be initialized with prioritized strategy")
func routingPolicy_prioritizedStrategy() {
    let routes = [
        ProviderRoute(id: "primary", client: MockModelClient(id: "primary"), priority: 1),
        ProviderRoute(id: "secondary", client: MockModelClient(id: "secondary"), priority: 2)
    ]
    let policy = ColonyRoutingPolicy(
        strategy: .prioritized(routes, .default),
        retryPolicy: ColonyCore.RetryPolicy(maxAttempts: 2, baseDelay: .milliseconds(50), maxDelay: .seconds(5))
    )
    _ = policy

    // Verify the policy is created
}

@Test("ColonyRoutingPolicy can be initialized with onDevice strategy")
func routingPolicy_onDeviceStrategy() {
    let onDevice = MockModelClient(id: "on-device")
    let fallback = MockModelClient(id: "fallback")
    let policy = ColonyRoutingPolicy(
        strategy: .onDevice(
            onDevice: onDevice,
            fallback: fallback,
            privacy: .requireOnDevice
        ),
        retryPolicy: .default
    )
    _ = policy

    // Verify the policy is created
}

@Test("ColonyRoutingPolicy can be initialized with costOptimized strategy")
func routingPolicy_costOptimizedStrategy() {
    let routes = [
        ProviderRoute(id: "cheap", client: MockModelClient(id: "cheap"), priority: 1),
        ProviderRoute(id: "expensive", client: MockModelClient(id: "expensive"), priority: 2)
    ]
    let costPolicy = CostPolicy(
        maxCostPerRequest: Decimal(0.01),
        budgetPeriod: .daily,
        providerPreferences: [:]
    )
    let policy = ColonyRoutingPolicy(
        strategy: .costOptimized(routes, costPolicy),
        retryPolicy: .default,
        costPolicy: costPolicy
    )
    _ = policy

    // Verify the policy is created
}

// MARK: - Sendable Conformance Tests

@Test("RetryPolicy is Sendable")
func retryPolicy_sendable() {
    let policy: ColonyCore.RetryPolicy = .default

    // If this compiles, RetryPolicy is Sendable
    Task {
        let _ = policy
    }
}

@Test("RoutingStrategy is Sendable")
func routingStrategy_sendable() {
    let client = MockModelClient(id: "test")
    let strategy: RoutingStrategy = .single(client)

    // If this compiles, RoutingStrategy is Sendable
    Task {
        let _ = strategy
    }
}

@Test("ProviderRoute is Sendable")
func providerRoute_sendable() {
    let client = MockModelClient(id: "test")
    let route = ProviderRoute(id: "test", client: client)

    // If this compiles, ProviderRoute is Sendable
    Task {
        let _ = route
    }
}

@Test("CostPolicy is Sendable")
func costPolicy_sendable() {
    let policy = CostPolicy()

    // If this compiles, CostPolicy is Sendable
    Task {
        let _ = policy
    }
}

@Test("PrivacyBehavior is Sendable")
func privacyBehavior_sendable() {
    let behavior: PrivacyBehavior = .preferOnDevice

    // If this compiles, PrivacyBehavior is Sendable
    Task {
        let _ = behavior
    }
}

@Test("BudgetPeriod is Sendable")
func budgetPeriod_sendable() {
    let period: BudgetPeriod = .daily

    // If this compiles, BudgetPeriod is Sendable
    Task {
        let _ = period
    }
}

@Test("ColonyRoutingPolicy is Sendable")
func routingPolicy_sendable() {
    let client = MockModelClient(id: "test")
    let policy = ColonyRoutingPolicy(strategy: .single(client), retryPolicy: .default)

    // If this compiles, ColonyRoutingPolicy is Sendable
    Task {
        let _ = policy
    }
}
