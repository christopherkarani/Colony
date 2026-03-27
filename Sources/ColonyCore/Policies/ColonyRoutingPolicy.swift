import Foundation

// MARK: - RetryPolicy

/// Configuration for retry behavior when model requests fail.
public struct RetryPolicy: Sendable {
    /// Maximum number of retry attempts before giving up.
    public var maxAttempts: Int

    /// Initial delay between retry attempts.
    public var baseDelay: Duration

    /// Maximum delay between retry attempts (caps exponential backoff).
    public var maxDelay: Duration

    /// Creates a new retry policy with the specified parameters.
    ///
    /// - Parameters:
    ///   - maxAttempts: Maximum number of retry attempts (default: 3)
    ///   - baseDelay: Initial delay between retries (default: 100ms)
    ///   - maxDelay: Maximum delay between retries (default: 10s)
    public init(
        maxAttempts: Int = 3,
        baseDelay: Duration = .milliseconds(100),
        maxDelay: Duration = .seconds(10)
    ) {
        self.maxAttempts = max(1, maxAttempts)
        self.baseDelay = baseDelay
        self.maxDelay = maxDelay
    }

    /// The default retry policy with sensible defaults.
    public static let `default` = RetryPolicy()
}

// MARK: - ProviderRoute

/// A single provider route in a routing strategy.
public struct ProviderRoute: Sendable {
    /// Unique identifier for this provider route.
    public let id: String

    /// The model client for this route.
    public let client: any ColonyModelClient

    /// Priority for this route (lower numbers = higher priority).
    public let priority: Int

    /// Maximum requests per minute for this provider (nil = unlimited).
    public let maxRequestsPerMinute: Int?

    /// Cost per 1K tokens in USD (nil = unknown).
    public let usdPer1KTokens: Double?

    /// Creates a new provider route.
    ///
    /// - Parameters:
    ///   - id: Unique identifier for this route
    ///   - client: The model client to use
    ///   - priority: Priority for routing (lower = higher priority, default: 0)
    ///   - maxRequestsPerMinute: Rate limit for this provider (default: nil)
    ///   - usdPer1KTokens: Cost per 1K tokens in USD (default: nil)
    public init(
        id: String,
        client: any ColonyModelClient,
        priority: Int = 0,
        maxRequestsPerMinute: Int? = nil,
        usdPer1KTokens: Double? = nil
    ) {
        self.id = id
        self.client = client
        self.priority = priority
        self.maxRequestsPerMinute = maxRequestsPerMinute
        self.usdPer1KTokens = usdPer1KTokens
    }
}

// MARK: - PrivacyBehavior

/// Controls behavior when on-device execution is preferred or required.
public enum PrivacyBehavior: Sendable {
    /// Prefer on-device, but allow fallback when unavailable.
    case preferOnDevice

    /// Require on-device; when unavailable, the routed model client fails deterministically.
    case requireOnDevice
}

// MARK: - BudgetPeriod

/// Time period for budget tracking.
public enum BudgetPeriod: Sendable {
    case hourly
    case daily
    case weekly
    case monthly
}

// MARK: - ProviderID

/// Type alias for provider identifiers in cost policies.
public typealias ProviderID = String

// MARK: - CostPreference

/// Cost preferences for a specific provider.
public struct CostPreference: Sendable {
    /// Maximum cost per request for this provider.
    public var maxCostPerRequest: Decimal?

    /// Creates cost preferences for a provider.
    ///
    /// - Parameter maxCostPerRequest: Maximum cost per request (nil = no limit)
    public init(maxCostPerRequest: Decimal? = nil) {
        self.maxCostPerRequest = maxCostPerRequest
    }
}

// MARK: - CostPolicy

/// Configuration for cost-aware routing and budget management.
public struct CostPolicy: Sendable {
    /// Maximum cost per request across all providers.
    public var maxCostPerRequest: Decimal?

    /// Budget period for tracking costs.
    public var budgetPeriod: BudgetPeriod?

    /// Provider-specific cost preferences.
    public var providerPreferences: [ProviderID: CostPreference]

    /// Creates a new cost policy.
    ///
    /// - Parameters:
    ///   - maxCostPerRequest: Maximum cost per request (default: nil)
    ///   - budgetPeriod: Budget tracking period (default: nil)
    ///   - providerPreferences: Provider-specific preferences (default: empty)
    public init(
        maxCostPerRequest: Decimal? = nil,
        budgetPeriod: BudgetPeriod? = nil,
        providerPreferences: [ProviderID: CostPreference] = [:]
    ) {
        self.maxCostPerRequest = maxCostPerRequest
        self.budgetPeriod = budgetPeriod
        self.providerPreferences = providerPreferences
    }

    /// Empty cost policy with no restrictions.
    public static let `default` = CostPolicy()
}

// MARK: - RoutingStrategy

/// Strategy for routing model requests to appropriate providers.
public enum RoutingStrategy: Sendable {
    /// Use a single model client for all requests.
    case single(any ColonyModelClient)

    /// Try providers in priority order with retry policy.
    case prioritized([ProviderRoute], RetryPolicy)

    /// Use on-device when available, with fallback and privacy controls.
    case onDevice(
        onDevice: (any ColonyModelClient)?,
        fallback: any ColonyModelClient,
        privacy: PrivacyBehavior
    )

    /// Optimize for cost across multiple providers.
    case costOptimized([ProviderRoute], CostPolicy)
}

// MARK: - ColonyRoutingPolicy

/// Unified policy for model routing, retry behavior, and cost management.
///
/// This struct combines routing strategy, retry policy, and cost controls into a single
/// configuration type that can be used by the unified ColonyModelRouter.
///
/// Example usage:
/// ```swift
/// // Single provider with default retry
/// let policy = ColonyRoutingPolicy(
///     strategy: .single(myClient),
///     retryPolicy: .default
/// )
///
/// // Prioritized providers with custom retry
/// let policy = ColonyRoutingPolicy(
///     strategy: .prioritized(routes, customRetry),
///     retryPolicy: customRetry
/// )
///
/// // On-device with fallback
/// let policy = ColonyRoutingPolicy(
///     strategy: .onDevice(
///         onDevice: onDeviceClient,
///         fallback: cloudClient,
///         privacy: .preferOnDevice
///     ),
///     retryPolicy: .default
/// )
///
/// // Cost-optimized routing
/// let policy = ColonyRoutingPolicy(
///     strategy: .costOptimized(routes, costPolicy),
///     retryPolicy: .default,
///     costPolicy: costPolicy
/// )
/// ```
public struct ColonyRoutingPolicy: Sendable {
    /// The routing strategy to use.
    public var strategy: RoutingStrategy

    /// The retry policy for failed requests.
    public var retryPolicy: RetryPolicy

    /// Optional cost policy for budget management (required for costOptimized strategy).
    public var costPolicy: CostPolicy?

    /// Creates a new routing policy.
    ///
    /// - Parameters:
    ///   - strategy: The routing strategy to use
    ///   - retryPolicy: The retry policy for failed requests
    ///   - costPolicy: Optional cost policy for budget management
    public init(
        strategy: RoutingStrategy,
        retryPolicy: RetryPolicy,
        costPolicy: CostPolicy? = nil
    ) {
        self.strategy = strategy
        self.retryPolicy = retryPolicy
        self.costPolicy = costPolicy
    }
}
