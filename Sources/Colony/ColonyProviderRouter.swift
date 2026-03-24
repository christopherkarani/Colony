import Foundation
import HiveCore
import ColonyCore

public enum ProviderRoutingError: Error, Sendable, CustomStringConvertible, Equatable {
    case noProvidersConfigured
    case noEligibleProvider(reasons: [String])
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

@available(*, deprecated, renamed: "ProviderRoutingError")
public typealias ColonyProviderRouterError = ProviderRoutingError

@available(*, deprecated, message: "Use ColonyModelRouter with .prioritized strategy instead")
public struct ColonyProviderRouter: HiveModelRouter, Sendable {
    public struct Provider: Sendable {
        public let id: String
        public let client: AnyHiveModelClient
        public let priority: Int
        public let maxRequestsPerMinute: Int?
        public let usdPer1KTokens: Double?

        public init(
            id: String,
            client: AnyHiveModelClient,
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

    public enum GracefulDegradationPolicy: Sendable {
        case fail
        case syntheticResponse(String)
    }

    public struct Policy: Sendable {
        public var maxAttemptsPerProvider: Int
        public var initialBackoffNanoseconds: UInt64
        public var maxBackoffNanoseconds: UInt64
        public var globalMaxRequestsPerMinute: Int?
        public var costCeilingUSD: Double?
        public var estimatedOutputToInputRatio: Double
        public var gracefulDegradation: GracefulDegradationPolicy

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

    public func route(_ request: HiveChatRequest, hints: HiveInferenceHints?) -> AnyHiveModelClient {
        AnyHiveModelClient(ColonyProviderRoutingClient(router: self, hints: hints))
    }

    fileprivate func complete(request: HiveChatRequest, hints: HiveInferenceHints?) async throws -> HiveChatResponse {
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
            return HiveChatResponse(
                message: HiveChatMessage(
                    id: "degraded-" + UUID().uuidString.lowercased(),
                    role: .assistant,
                    content: message
                )
            )
        }
    }

    private func attemptProvider(_ provider: Provider, request: HiveChatRequest) async throws -> HiveChatResponse {
        let maxAttempts = policy.maxAttemptsPerProvider
        var currentBackoff = policy.initialBackoffNanoseconds
        var lastError: Error?

        for attempt in 1 ... maxAttempts {
            do {
                return try await provider.client.complete(request)
            } catch {
                lastError = error
                guard attempt < maxAttempts else { break }
                try await clock.sleep(currentBackoff)
                currentBackoff = min(policy.maxBackoffNanoseconds, currentBackoff &* 2)
            }
        }

        throw lastError ?? ProviderRoutingError.noEligibleProvider(reasons: [provider.id + ":unknown failure"])
    }

    private func estimatedRequestCostUSD(for request: HiveChatRequest, provider: Provider) -> Double {
        guard let usdPer1KTokens = provider.usdPer1KTokens else { return 0 }

        let tokenizer = ColonyApproximateTokenizer()
        let messageTokens = tokenizer.countTokens(request.messages)
        let toolDefinitionPayload = request.tools
            .map { "\($0.name)\n\($0.description)\n\($0.parametersJSONSchema)" }
            .joined(separator: "\n")
        let toolTokens = tokenizer.countTokens([
            HiveChatMessage(id: "budget-tools", role: .system, content: toolDefinitionPayload),
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

private struct ColonyProviderRoutingClient: HiveModelClient, Sendable {
    let router: ColonyProviderRouter
    let hints: HiveInferenceHints?

    func complete(_ request: HiveChatRequest) async throws -> HiveChatResponse {
        try await router.complete(request: request, hints: hints)
    }

    func stream(_ request: HiveChatRequest) -> AsyncThrowingStream<HiveChatStreamChunk, Error> {
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
