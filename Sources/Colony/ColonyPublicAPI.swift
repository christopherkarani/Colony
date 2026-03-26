import Foundation
@_spi(ColonyInternal) import Swarm
import ColonyCore

// MARK: - ColonyModel

/// Represents a model configuration for Colony agents.
///
/// Use `ColonyModel` to specify how the agent should access language models.
/// This enum provides type-safe configuration for different model backends.
///
/// Example:
/// ```swift
/// let model = ColonyModel.foundationModels(configuration: .default)
/// ```
public indirect enum ColonyModel: Sendable {
    /// Use Apple Foundation Models (on-device).
    case foundationModels(configuration: ColonyFoundationModelsConfiguration)

    /// Use on-device models with cloud fallback.
    case onDevice(
        fallback: ColonyModel?,
        policy: ColonyOnDevicePolicy,
        foundationModels: ColonyFoundationModelsConfiguration
    )

    /// Use provider routing for multi-provider setups.
    case providerRouting(
        providers: [ColonyProviderConfiguration],
        policy: ColonyProviderPolicy
    )

    /// Creates a simple Foundation Models configuration.
    public static func foundationModels(
        modelName: String = "llama3.2"
    ) -> ColonyModel {
        .foundationModels(configuration: ColonyFoundationModelsConfiguration(modelName: modelName))
    }
}

// MARK: - Supporting Configuration Types

/// Configuration for Apple Foundation Models.
public struct ColonyFoundationModelsConfiguration: Sendable {
    /// The name of the model to use.
    public var modelName: String

    /// Optional custom endpoint URL.
    public var endpointURL: URL?

    /// Creates a new Foundation Models configuration.
    ///
    /// - Parameters:
    ///   - modelName: The model name to use.
    ///   - endpointURL: Optional custom endpoint URL.
    public init(modelName: String, endpointURL: URL? = nil) {
        self.modelName = modelName
        self.endpointURL = endpointURL
    }

    /// Default configuration.
    public static let `default` = ColonyFoundationModelsConfiguration(modelName: "llama3.2")
}

/// Policy for on-device model routing.
public struct ColonyOnDevicePolicy: Sendable {
    /// When to use on-device vs cloud models.
    public enum RoutingStrategy: Sendable {
        /// Always use on-device models.
        case onDeviceOnly
        /// Prefer on-device, fallback to cloud on failure.
        case preferOnDevice
        /// Use cloud for complex tasks, on-device for simple ones.
        case adaptive
    }

    /// The routing strategy.
    public var strategy: RoutingStrategy

    /// Maximum tokens for on-device inference.
    public var maxOnDeviceTokens: Int?

    /// Creates a new on-device policy.
    ///
    /// - Parameters:
    ///   - strategy: The routing strategy. Defaults to `.preferOnDevice`.
    ///   - maxOnDeviceTokens: Maximum tokens for on-device inference.
    public init(strategy: RoutingStrategy = .preferOnDevice, maxOnDeviceTokens: Int? = 4_000) {
        self.strategy = strategy
        self.maxOnDeviceTokens = maxOnDeviceTokens
    }

    /// Default policy.
    public static let `default` = ColonyOnDevicePolicy()

    /// On-device only policy.
    public static let onDeviceOnly = ColonyOnDevicePolicy(strategy: .onDeviceOnly)

    /// Prefer on-device with cloud fallback.
    public static let preferOnDevice = ColonyOnDevicePolicy(strategy: .preferOnDevice)
}

/// Configuration for a single provider in a routing setup.
public struct ColonyProviderConfiguration: Sendable {
    /// Unique identifier for this provider.
    public var id: String

    /// The model client for this provider.
    public var client: any ColonyModelClient

    /// Priority (lower values = higher priority).
    public var priority: Int

    /// Maximum requests per minute.
    public var maxRequestsPerMinute: Int?

    /// Cost per 1K tokens in USD.
    public var usdPer1KTokens: Double?

    /// Creates a new provider configuration.
    ///
    /// - Parameters:
    ///   - id: Provider identifier.
    ///   - client: Model client for this provider.
    ///   - priority: Priority (lower = higher priority).
    ///   - maxRequestsPerMinute: Optional rate limit.
    ///   - usdPer1KTokens: Optional cost per 1K tokens.
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

/// Policy for provider routing.
public struct ColonyProviderPolicy: Sendable {
    /// Maximum attempts per provider.
    public var maxAttemptsPerProvider: Int

    /// Initial backoff in nanoseconds.
    public var initialBackoffNanoseconds: UInt64

    /// Maximum backoff in nanoseconds.
    public var maxBackoffNanoseconds: UInt64

    /// Global rate limit (requests per minute).
    public var globalMaxRequestsPerMinute: Int?

    /// Cost ceiling in USD.
    public var costCeilingUSD: Double?

    /// Graceful degradation policy.
    public var gracefulDegradation: ColonyGracefulDegradationPolicy

    /// Creates a new provider policy.
    ///
    /// - Parameters:
    ///   - maxAttemptsPerProvider: Maximum attempts per provider.
    ///   - initialBackoffNanoseconds: Initial backoff duration.
    ///   - maxBackoffNanoseconds: Maximum backoff duration.
    ///   - globalMaxRequestsPerMinute: Optional global rate limit.
    ///   - costCeilingUSD: Optional cost ceiling.
    ///   - gracefulDegradation: Degradation policy.
    public init(
        maxAttemptsPerProvider: Int = 2,
        initialBackoffNanoseconds: UInt64 = 100_000_000,
        maxBackoffNanoseconds: UInt64 = 1_000_000_000,
        globalMaxRequestsPerMinute: Int? = nil,
        costCeilingUSD: Double? = nil,
        gracefulDegradation: ColonyGracefulDegradationPolicy = .fail
    ) {
        self.maxAttemptsPerProvider = max(1, maxAttemptsPerProvider)
        self.initialBackoffNanoseconds = max(1, initialBackoffNanoseconds)
        self.maxBackoffNanoseconds = max(self.initialBackoffNanoseconds, maxBackoffNanoseconds)
        self.globalMaxRequestsPerMinute = globalMaxRequestsPerMinute
        self.costCeilingUSD = costCeilingUSD
        self.gracefulDegradation = gracefulDegradation
    }

    /// Default policy.
    public static let `default` = ColonyProviderPolicy()
}

/// Graceful degradation policy for provider routing.
public enum ColonyGracefulDegradationPolicy: Sendable {
    /// Fail when no provider is available.
    case fail

    /// Return a synthetic response when degraded.
    case syntheticResponse(String)
}
