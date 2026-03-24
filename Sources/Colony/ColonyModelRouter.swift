import Foundation
import HiveCore
import ColonyCore

// MARK: - ColonyModelClient Protocol

/// Protocol for model clients that can generate responses to inference requests.
public protocol ColonyModelClient: Sendable {
    /// Generates a complete response for the given request.
    func generate(_ request: ColonyInferenceRequest) async throws -> ColonyInferenceResponse

    /// Streams incremental responses for the given request.
    func stream(_ request: ColonyInferenceRequest) -> AsyncThrowingStream<ColonyInferenceStreamChunk, Error>
}

// MARK: - Inference Request/Response Types

/// Request for model inference.
public struct ColonyInferenceRequest: Sendable {
    /// The messages in the conversation.
    public let messages: [HiveChatMessage]

    /// Available tools for the model to use.
    public let tools: [HiveToolDefinition]

    /// Desired complexity level for the task.
    public let complexity: Complexity

    /// Optional model name override.
    public let modelName: String?

    /// Creates a new inference request.
    public init(
        messages: [HiveChatMessage],
        tools: [HiveToolDefinition],
        complexity: Complexity = .automatic,
        modelName: String? = nil
    ) {
        self.messages = messages
        self.tools = tools
        self.complexity = complexity
        self.modelName = modelName
    }

    /// Complexity level for inference routing decisions.
    public enum Complexity: Sendable {
        /// Automatically determine complexity based on request.
        case automatic
        /// Simple task suitable for on-device models.
        case simple
        /// Complex task that may require cloud models.
        case complex
    }
}

/// Response from model inference.
public struct ColonyInferenceResponse: Sendable {
    /// The generated content.
    public let content: String

    /// Token usage information.
    public let usage: Usage?

    /// The provider that generated this response.
    public let providerID: String?

    /// Creates a new inference response.
    public init(
        content: String,
        usage: Usage? = nil,
        providerID: String? = nil
    ) {
        self.content = content
        self.usage = usage
        self.providerID = providerID
    }

    /// Token usage statistics.
    public struct Usage: Sendable {
        /// Number of tokens in the prompt.
        public let promptTokens: Int

        /// Number of tokens in the completion.
        public let completionTokens: Int

        /// Creates usage statistics.
        public init(promptTokens: Int, completionTokens: Int) {
            self.promptTokens = promptTokens
            self.completionTokens = completionTokens
        }

        /// Total tokens used.
        public var totalTokens: Int {
            promptTokens + completionTokens
        }
    }
}

/// Streaming chunk for inference responses.
public enum ColonyInferenceStreamChunk: Sendable {
    /// Incremental content token.
    case token(String)

    /// Final response with complete metadata.
    case final(ColonyInferenceResponse)
}

// MARK: - ColonyModelRouter

/// Unified model router that supports multiple routing strategies.
///
/// This router consolidates the functionality of `ColonyProviderRouter` and
/// `ColonyOnDeviceModelRouter` into a single, flexible routing component.
public struct ColonyModelRouter: ColonyModelClient, Sendable {
    /// The routing strategy to use.
    public enum Strategy: Sendable {
        /// Use a single client for all requests.
        case single(any ColonyModelClient)

        /// Try providers in priority order with retry policy.
        case prioritized([ProviderRoute], RetryPolicy)

        /// Use on-device when available, with fallback to cloud.
        case onDevice(
            onDevice: (any ColonyModelClient)?,
            fallback: any ColonyModelClient,
            privacy: PrivacyBehavior
        )

        /// Select provider based on cost optimization.
        case costOptimized([ProviderRoute], CostPolicy)
    }

    /// A route to a specific provider.
    public struct ProviderRoute: Sendable {
        /// The provider identifier.
        public let providerID: String

        /// The model client for this provider.
        public let client: any ColonyModelClient

        /// Weight for cost optimization (higher = more expensive).
        public let weight: Double

        /// Creates a new provider route.
        public init(
            providerID: String,
            client: any ColonyModelClient,
            weight: Double = 1.0
        ) {
            self.providerID = providerID
            self.client = client
            self.weight = weight
        }
    }

    /// Privacy behavior for on-device routing.
    public enum PrivacyBehavior: Sendable {
        /// Always prefer on-device execution.
        case preferOnDevice
        /// Allow cloud for complex tasks when on-device may struggle.
        case allowCloudForComplexTasks
        /// Always use cloud models regardless of on-device availability.
        case alwaysCloud
    }

    /// Retry policy for failed requests.
    public struct RetryPolicy: Sendable {
        /// Maximum number of attempts per provider.
        public let maxAttempts: Int

        /// Initial backoff duration.
        public let initialBackoff: Duration

        /// Maximum backoff duration.
        public let maxBackoff: Duration

        /// Creates a new retry policy.
        public init(
            maxAttempts: Int = 3,
            initialBackoff: Duration = .milliseconds(100),
            maxBackoff: Duration = .seconds(5)
        ) {
            self.maxAttempts = max(1, maxAttempts)
            self.initialBackoff = initialBackoff
            self.maxBackoff = maxBackoff
        }
    }

    /// Cost optimization policy.
    public struct CostPolicy: Sendable {
        /// Maximum cost ceiling in USD.
        public let costCeilingUSD: Double?

        /// Whether to prefer lower cost providers.
        public let preferLowerCost: Bool

        /// Creates a new cost policy.
        public init(
            costCeilingUSD: Double? = nil,
            preferLowerCost: Bool = true
        ) {
            self.costCeilingUSD = costCeilingUSD
            self.preferLowerCost = preferLowerCost
        }
    }

    private let strategy: Strategy

    /// Creates a new model router with the specified strategy.
    public init(strategy: Strategy) {
        self.strategy = strategy
    }

    // MARK: - ColonyModelClient

    public func generate(_ request: ColonyInferenceRequest) async throws -> ColonyInferenceResponse {
        switch strategy {
        case .single(let client):
            return try await client.generate(request)

        case .prioritized(let routes, let policy):
            return try await generateWithPrioritizedRoutes(request, routes: routes, policy: policy)

        case .onDevice(let onDevice, let fallback, let privacy):
            return try await generateWithOnDevice(
                request,
                onDevice: onDevice,
                fallback: fallback,
                privacy: privacy
            )

        case .costOptimized(let routes, let costPolicy):
            return try await generateWithCostOptimization(
                request,
                routes: routes,
                costPolicy: costPolicy
            )
        }
    }

    public func stream(_ request: ColonyInferenceRequest) -> AsyncThrowingStream<ColonyInferenceStreamChunk, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    switch strategy {
                    case .single(let client):
                        for try await chunk in client.stream(request) {
                            continuation.yield(chunk)
                        }

                    case .prioritized(let routes, let policy):
                        let chunk = try await streamWithPrioritizedRoutes(
                            request,
                            routes: routes,
                            policy: policy,
                            continuation: continuation
                        )
                        if let chunk { continuation.yield(chunk) }

                    case .onDevice(let onDevice, let fallback, let privacy):
                        let chunk = try await streamWithOnDevice(
                            request,
                            onDevice: onDevice,
                            fallback: fallback,
                            privacy: privacy,
                            continuation: continuation
                        )
                        if let chunk { continuation.yield(chunk) }

                    case .costOptimized(let routes, let costPolicy):
                        let chunk = try await streamWithCostOptimization(
                            request,
                            routes: routes,
                            costPolicy: costPolicy,
                            continuation: continuation
                        )
                        if let chunk { continuation.yield(chunk) }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    // MARK: - Private Implementation

    private func generateWithPrioritizedRoutes(
        _ request: ColonyInferenceRequest,
        routes: [ProviderRoute],
        policy: RetryPolicy
    ) async throws -> ColonyInferenceResponse {
        guard !routes.isEmpty else {
            throw ColonyModelRouterError.noProvidersConfigured
        }

        var failureReasons: [String] = []

        for route in routes {
            do {
                return try await attemptWithRetry(request, client: route.client, policy: policy)
            } catch {
                failureReasons.append("\(route.providerID): \(error.localizedDescription)")
            }
        }

        throw ColonyModelRouterError.noEligibleProvider(reasons: failureReasons)
    }

    private func streamWithPrioritizedRoutes(
        _ request: ColonyInferenceRequest,
        routes: [ProviderRoute],
        policy: RetryPolicy,
        continuation: AsyncThrowingStream<ColonyInferenceStreamChunk, Error>.Continuation
    ) async throws -> ColonyInferenceStreamChunk? {
        guard !routes.isEmpty else {
            throw ColonyModelRouterError.noProvidersConfigured
        }

        var failureReasons: [String] = []

        for route in routes {
            do {
                var finalChunk: ColonyInferenceStreamChunk?
                for try await chunk in route.client.stream(request) {
                    continuation.yield(chunk)
                    if case .final = chunk {
                        finalChunk = chunk
                    }
                }
                return finalChunk
            } catch {
                failureReasons.append("\(route.providerID): \(error.localizedDescription)")
            }
        }

        throw ColonyModelRouterError.noEligibleProvider(reasons: failureReasons)
    }

    private func generateWithOnDevice(
        _ request: ColonyInferenceRequest,
        onDevice: (any ColonyModelClient)?,
        fallback: any ColonyModelClient,
        privacy: PrivacyBehavior
    ) async throws -> ColonyInferenceResponse {
        let shouldUseOnDevice = shouldUseOnDeviceFor(request, onDevice: onDevice != nil, privacy: privacy)

        if shouldUseOnDevice, let onDevice {
            return try await onDevice.generate(request)
        }

        return try await fallback.generate(request)
    }

    private func streamWithOnDevice(
        _ request: ColonyInferenceRequest,
        onDevice: (any ColonyModelClient)?,
        fallback: any ColonyModelClient,
        privacy: PrivacyBehavior,
        continuation: AsyncThrowingStream<ColonyInferenceStreamChunk, Error>.Continuation
    ) async throws -> ColonyInferenceStreamChunk? {
        let shouldUseOnDevice = shouldUseOnDeviceFor(request, onDevice: onDevice != nil, privacy: privacy)

        let client = shouldUseOnDevice ? onDevice : fallback
        guard let selectedClient = client else {
            throw ColonyModelRouterError.noEligibleProvider(reasons: ["No on-device client available and fallback disabled"])
        }

        var finalChunk: ColonyInferenceStreamChunk?
        for try await chunk in selectedClient.stream(request) {
            continuation.yield(chunk)
            if case .final = chunk {
                finalChunk = chunk
            }
        }
        return finalChunk
    }

    private func shouldUseOnDeviceFor(
        _ request: ColonyInferenceRequest,
        onDevice available: Bool,
        privacy: PrivacyBehavior
    ) -> Bool {
        switch privacy {
        case .preferOnDevice:
            return available
        case .allowCloudForComplexTasks:
            switch request.complexity {
            case .automatic:
                // Heuristic: simple requests go on-device
                return available && request.messages.count < 10
            case .simple:
                return available
            case .complex:
                return false
            }
        case .alwaysCloud:
            return false
        }
    }

    private func generateWithCostOptimization(
        _ request: ColonyInferenceRequest,
        routes: [ProviderRoute],
        costPolicy: CostPolicy
    ) async throws -> ColonyInferenceResponse {
        guard !routes.isEmpty else {
            throw ColonyModelRouterError.noProvidersConfigured
        }

        let sortedRoutes = costPolicy.preferLowerCost
            ? routes.sorted { $0.weight < $1.weight }
            : routes

        var failureReasons: [String] = []

        for route in sortedRoutes {
            // Skip if exceeds cost ceiling
            if let ceiling = costPolicy.costCeilingUSD {
                let estimatedCost = estimateCost(for: request, weight: route.weight)
                if estimatedCost > ceiling {
                    failureReasons.append("\(route.providerID): cost ceiling exceeded")
                    continue
                }
            }

            do {
                return try await route.client.generate(request)
            } catch {
                failureReasons.append("\(route.providerID): \(error.localizedDescription)")
            }
        }

        throw ColonyModelRouterError.noEligibleProvider(reasons: failureReasons)
    }

    private func streamWithCostOptimization(
        _ request: ColonyInferenceRequest,
        routes: [ProviderRoute],
        costPolicy: CostPolicy,
        continuation: AsyncThrowingStream<ColonyInferenceStreamChunk, Error>.Continuation
    ) async throws -> ColonyInferenceStreamChunk? {
        guard !routes.isEmpty else {
            throw ColonyModelRouterError.noProvidersConfigured
        }

        let sortedRoutes = costPolicy.preferLowerCost
            ? routes.sorted { $0.weight < $1.weight }
            : routes

        var failureReasons: [String] = []

        for route in sortedRoutes {
            // Skip if exceeds cost ceiling
            if let ceiling = costPolicy.costCeilingUSD {
                let estimatedCost = estimateCost(for: request, weight: route.weight)
                if estimatedCost > ceiling {
                    failureReasons.append("\(route.providerID): cost ceiling exceeded")
                    continue
                }
            }

            do {
                var finalChunk: ColonyInferenceStreamChunk?
                for try await chunk in route.client.stream(request) {
                    continuation.yield(chunk)
                    if case .final = chunk {
                        finalChunk = chunk
                    }
                }
                return finalChunk
            } catch {
                failureReasons.append("\(route.providerID): \(error.localizedDescription)")
            }
        }

        throw ColonyModelRouterError.noEligibleProvider(reasons: failureReasons)
    }

    private func attemptWithRetry(
        _ request: ColonyInferenceRequest,
        client: any ColonyModelClient,
        policy: RetryPolicy
    ) async throws -> ColonyInferenceResponse {
        var lastError: Error?
        var currentBackoff = policy.initialBackoff

        for attempt in 1...policy.maxAttempts {
            do {
                return try await client.generate(request)
            } catch {
                lastError = error
                guard attempt < policy.maxAttempts else { break }
                let nanoseconds = currentBackoff.components.seconds * 1_000_000_000 + Int64(currentBackoff.components.attoseconds / 1_000_000_000)
                try await Task.sleep(nanoseconds: UInt64(max(0, nanoseconds)))
                currentBackoff = min(policy.maxBackoff, currentBackoff * 2)
            }
        }

        throw lastError ?? ColonyModelRouterError.noEligibleProvider(reasons: ["Unknown failure"])
    }

    private func estimateCost(for request: ColonyInferenceRequest, weight: Double) -> Double {
        // Simple estimation based on message count and weight
        let messageCount = Double(request.messages.count)
        return messageCount * weight * 0.001  // Rough estimate per message
    }
}

// MARK: - Errors

/// Errors that can occur during model routing.
public enum ColonyModelRouterError: Error, CustomStringConvertible {
    /// No providers were configured for routing.
    case noProvidersConfigured

    /// No eligible provider was available for the request.
    case noEligibleProvider(reasons: [String])

    public var description: String {
        switch self {
        case .noProvidersConfigured:
            return "No providers configured for routing."
        case .noEligibleProvider(let reasons):
            return "No eligible provider available: \(reasons.joined(separator: "; "))"
        }
    }

    public var localizedDescription: String {
        description
    }
}

// MARK: - HiveModelClient Conformance for ColonyModelRouter

extension ColonyModelRouter: HiveModelClient {
    public func complete(_ request: HiveChatRequest) async throws -> HiveChatResponse {
        let inferenceRequest = ColonyInferenceRequest(
            messages: request.messages,
            tools: request.tools
        )
        let response = try await generate(inferenceRequest)
        return HiveChatResponse(
            message: HiveChatMessage(
                id: UUID().uuidString,
                role: .assistant,
                content: response.content
            )
        )
    }

    public func stream(_ request: HiveChatRequest) -> AsyncThrowingStream<HiveChatStreamChunk, Error> {
        let inferenceRequest = ColonyInferenceRequest(
            messages: request.messages,
            tools: request.tools
        )

        return AsyncThrowingStream { continuation in
            Task {
                do {
                    for try await chunk in self.stream(inferenceRequest) {
                        switch chunk {
                        case .token(let text):
                            continuation.yield(.token(text))
                        case .final(let response):
                            continuation.yield(.final(HiveChatResponse(
                                message: HiveChatMessage(
                                    id: UUID().uuidString,
                                    role: .assistant,
                                    content: response.content
                                )
                            )))
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}
