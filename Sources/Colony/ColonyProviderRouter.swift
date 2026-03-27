import Foundation
import ColonyCore

/// Errors that can occur during provider routing.
public enum ProviderRoutingError: Error, Sendable, CustomStringConvertible, Equatable {
    /// No providers were configured.
    case noProvidersConfigured

    /// No provider was eligible (e.g., rate limited, cost ceiling exceeded).
    case noEligibleProvider(reasons: [String])

    /// Operation was degraded with a fallback response.
    case degraded(message: String)

    public var description: String {
        switch self {
        case .noProvidersConfigured:
            return "No providers configured for routing."
        case .noEligibleProvider(let reasons):
            return "No eligible provider available: " + reasons.joined(separator: "; ")
        case .degraded(let message):
            return message
        }
    }
}

public typealias ColonyProviderRouterError = ProviderRoutingError

/// A router that selects among multiple providers based on priority and budget.
///
/// This router is deprecated. Use `ColonyModelRouter` with the `.prioritized` strategy instead.
public struct ColonyProviderRouter: ColonyModelClient, Sendable {
    /// A provider configuration for the router.
    public struct Provider: Sendable {
        /// Unique identifier for this provider.
        public let id: String

        /// The model client for this provider.
        public let client: any ColonyModelClient

        /// Priority (lower values = higher priority).
        public let priority: Int

        /// Maximum requests per minute, or nil for unlimited.
        public let maxRequestsPerMinute: Int?

        /// Cost per 1K tokens in USD, or nil if unknown.
        public let usdPer1KTokens: Double?

        /// Creates a new provider.
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

    /// Policy for graceful degradation when all providers fail.
    public enum GracefulDegradationPolicy: Sendable {
        /// Fail with an error.
        case fail
        /// Return a synthetic response with the given message.
        case syntheticResponse(String)
    }

    /// Configuration policy for provider routing.
    public struct Policy: Sendable {
        /// Maximum retry attempts per provider.
        public var maxAttemptsPerProvider: Int

        /// Initial backoff duration in nanoseconds.
        public var initialBackoffNanoseconds: UInt64

        /// Maximum backoff duration in nanoseconds.
        public var maxBackoffNanoseconds: UInt64

        /// Global rate limit (requests per minute).
        public var globalMaxRequestsPerMinute: Int?

        /// Cost ceiling in USD.
        public var costCeilingUSD: Double?

        /// Estimated output to input token ratio for cost estimation.
        public var estimatedOutputToInputRatio: Double

        /// Graceful degradation policy.
        public var gracefulDegradation: GracefulDegradationPolicy

        /// Creates a new routing policy.
        ///
        /// - Parameters:
        ///   - maxAttemptsPerProvider: Maximum attempts per provider.
        ///   - initialBackoffNanoseconds: Initial backoff duration.
        ///   - maxBackoffNanoseconds: Maximum backoff duration.
        ///   - globalMaxRequestsPerMinute: Optional global rate limit.
        ///   - costCeilingUSD: Optional cost ceiling.
        ///   - estimatedOutputToInputRatio: Token ratio for estimation.
        ///   - gracefulDegradation: Degradation policy.
        public init(
            maxAttemptsPerProvider: Int = 2,
            initialBackoffNanoseconds: UInt64 = 100_000_000,
            maxBackoffNanoseconds: UInt64 = 1_000_000_000,
            globalMaxRequestsPerMinute: Int? = nil,
            costCeilingUSD: Double? = nil,
            estimatedOutputToInputRatio: Double = 0.5,
            gracefulDegradation: GracefulDegradationPolicy = .fail
        ) {
            self.maxAttemptsPerProvider = max(1, maxAttemptsPerProvider)
            self.initialBackoffNanoseconds = max(1, initialBackoffNanoseconds)
            self.maxBackoffNanoseconds = max(self.initialBackoffNanoseconds, maxBackoffNanoseconds)
            self.globalMaxRequestsPerMinute = globalMaxRequestsPerMinute
            self.costCeilingUSD = costCeilingUSD
            self.estimatedOutputToInputRatio = max(0, estimatedOutputToInputRatio)
            self.gracefulDegradation = gracefulDegradation
        }
    }

    private struct SleepClock: Sendable {
        let now: @Sendable () -> Date
        let sleep: @Sendable (UInt64) async throws -> Void
    }

    /// Creates a new provider router.
    ///
    /// - Parameters:
    ///   - providers: List of providers (sorted by priority).
    ///   - policy: Routing policy.
    ///   - now: Clock for time measurements.
    ///   - sleep: Async sleep function.
    public init(
        providers: [Provider],
        policy: Policy = Policy(),
        now: @escaping @Sendable () -> Date = Date.init,
        sleep: @escaping @Sendable (UInt64) async throws -> Void = { try await Task.sleep(nanoseconds: $0) }
    ) {
        self.providers = providers.sorted { lhs, rhs in
            if lhs.priority != rhs.priority { return lhs.priority < rhs.priority }
            return lhs.id < rhs.id
        }
        self.policy = policy
        self.clock = SleepClock(now: now, sleep: sleep)
        self.state = ColonyProviderBudgetState()
    }

    public func generate(_ request: ColonyInferenceRequest) async throws -> ColonyInferenceResponse {
        let response = try await complete(request: request.swarmChatRequest, hints: nil)
        return ColonyInferenceResponse(response)
    }

    public func stream(_ request: ColonyInferenceRequest) -> AsyncThrowingStream<ColonyInferenceStreamChunk, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let response = try await generate(request)
                    if response.content.isEmpty == false {
                        continuation.yield(.token(response.content))
                    }
                    continuation.yield(.final(response))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    package func route(_ request: SwarmChatRequest, hints: SwarmInferenceHints?) -> SwarmAnyModelClient {
        SwarmAnyModelClient(ColonyProviderRoutingClient(router: self, hints: hints))
    }

    // MARK: - Private

    fileprivate func complete(request: SwarmChatRequest, hints: SwarmInferenceHints?) async throws -> SwarmChatResponse {
        _ = hints
        guard providers.isEmpty == false else {
            throw ProviderRoutingError.noProvidersConfigured
        }

        var failures: [String] = []

        for provider in providers {
            let estimate = estimatedRequestCostUSD(for: request, provider: provider)
            let reservation = await state.reserveIfEligible(
                provider: provider,
                estimatedCostUSD: estimate,
                policy: policy,
                now: clock.now()
            )

            guard case let .reserved(token) = reservation else {
                if case let .denied(reason) = reservation {
                    failures.append("\(provider.id):\(reason)")
                }
                continue
            }

            do {
                let response = try await attemptProvider(provider, request: request)
                await state.finalizeReservation(token, success: true, now: clock.now())
                return response
            } catch {
                await state.finalizeReservation(token, success: false, now: clock.now())
                failures.append("\(provider.id):\(String(describing: error))")
            }
        }

        switch policy.gracefulDegradation {
        case .fail:
            throw ProviderRoutingError.noEligibleProvider(reasons: failures)
        case .syntheticResponse(let message):
            return SwarmChatResponse(
                message: SwarmChatMessage(
                    id: "degraded-" + UUID().uuidString.lowercased(),
                    role: .assistant,
                    content: message
                )
            )
        }
    }

    private func attemptProvider(_ provider: Provider, request: SwarmChatRequest) async throws -> SwarmChatResponse {
        let maxAttempts = policy.maxAttemptsPerProvider
        var currentBackoff = policy.initialBackoffNanoseconds
        var lastError: Error?

        for attempt in 1 ... maxAttempts {
            do {
                return try await ColonyModelClientBridge(client: provider.client).complete(request)
            } catch {
                lastError = error
                guard attempt < maxAttempts else { break }
                try await clock.sleep(currentBackoff)
                currentBackoff = min(policy.maxBackoffNanoseconds, currentBackoff &* 2)
            }
        }

        throw lastError ?? ProviderRoutingError.noEligibleProvider(reasons: [provider.id + ":unknown failure"])
    }

    private func estimatedRequestCostUSD(for request: SwarmChatRequest, provider: Provider) -> Double {
        guard let usdPer1KTokens = provider.usdPer1KTokens else { return 0 }

        let tokenizer = ColonyApproximateTokenizer()
        let messageTokens = tokenizer.countTokens(request.messages)
        let toolDefinitionPayload = request.tools
            .map { "\($0.name)\n\($0.description)\n\($0.parametersJSONSchema)" }
            .joined(separator: "\n")
        let toolTokens = tokenizer.countTokens([
            SwarmChatMessage(id: "budget-tools", role: .system, content: toolDefinitionPayload),
        ])

        let inputTokens = messageTokens + toolTokens
        let outputTokens = Int((Double(inputTokens) * policy.estimatedOutputToInputRatio).rounded(.up))
        let totalTokens = inputTokens + max(0, outputTokens)
        return (Double(totalTokens) / 1_000.0) * usdPer1KTokens
    }

    private let providers: [Provider]
    private let policy: Policy
    private let clock: SleepClock
    private let state: ColonyProviderBudgetState
}

private struct ColonyProviderRoutingClient: SwarmModelClient, Sendable {
    let router: ColonyProviderRouter
    let hints: SwarmInferenceHints?

    func complete(_ request: SwarmChatRequest) async throws -> SwarmChatResponse {
        try await router.complete(request: request, hints: hints)
    }

    func stream(_ request: SwarmChatRequest) -> AsyncThrowingStream<SwarmChatStreamChunk, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let response = try await complete(request)
                    continuation.yield(.final(response))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}

private actor ColonyProviderBudgetState {
    struct ReservationToken: Sendable {
        let id: UUID
        let providerID: String
        let estimatedCostUSD: Double
    }

    enum ReservationResult: Sendable {
        case reserved(ReservationToken)
        case denied(String)
    }

    private var requestTimestampsByProvider: [String: [Date]] = [:]
    private var globalRequestTimestamps: [Date] = []
    private var spentCostUSD: Double = 0
    private var pendingByID: [UUID: ReservationToken] = [:]
    private var pendingCountByProvider: [String: Int] = [:]
    private var pendingCostUSD: Double = 0

    func reserveIfEligible(
        provider: ColonyProviderRouter.Provider,
        estimatedCostUSD: Double,
        policy: ColonyProviderRouter.Policy,
        now: Date
    ) -> ReservationResult {
        prune(now: now)

        let globalCount = globalRequestTimestamps.count + pendingByID.count
        if let globalLimit = policy.globalMaxRequestsPerMinute,
           globalLimit >= 0,
           globalCount >= globalLimit {
            return .denied("global rate ceiling exceeded")
        }

        let providerCount = (requestTimestampsByProvider[provider.id]?.count ?? 0)
            + (pendingCountByProvider[provider.id] ?? 0)
        if let providerLimit = provider.maxRequestsPerMinute,
           providerLimit >= 0,
           providerCount >= providerLimit {
            return .denied("provider rate ceiling exceeded")
        }

        if let ceiling = policy.costCeilingUSD,
           (spentCostUSD + pendingCostUSD + estimatedCostUSD) > ceiling {
            return .denied("cost ceiling exceeded")
        }

        let token = ReservationToken(id: UUID(), providerID: provider.id, estimatedCostUSD: estimatedCostUSD)
        pendingByID[token.id] = token
        pendingCountByProvider[provider.id, default: 0] += 1
        pendingCostUSD += estimatedCostUSD
        return .reserved(token)
    }

    func finalizeReservation(_ token: ReservationToken, success: Bool, now: Date) {
        prune(now: now)

        guard pendingByID.removeValue(forKey: token.id) != nil else {
            return
        }

        pendingCostUSD -= token.estimatedCostUSD
        if pendingCostUSD < 0 {
            pendingCostUSD = 0
        }

        if let providerCount = pendingCountByProvider[token.providerID] {
            let updated = max(0, providerCount - 1)
            if updated == 0 {
                pendingCountByProvider.removeValue(forKey: token.providerID)
            } else {
                pendingCountByProvider[token.providerID] = updated
            }
        }

        guard success else { return }
        globalRequestTimestamps.append(now)
        requestTimestampsByProvider[token.providerID, default: []].append(now)
        spentCostUSD += token.estimatedCostUSD
    }

    private func prune(now: Date) {
        let cutoff = now.addingTimeInterval(-60)
        globalRequestTimestamps.removeAll { $0 < cutoff }

        for providerID in requestTimestampsByProvider.keys {
            requestTimestampsByProvider[providerID]?.removeAll { $0 < cutoff }
            if requestTimestampsByProvider[providerID]?.isEmpty == true {
                requestTimestampsByProvider.removeValue(forKey: providerID)
            }
        }
    }
}
