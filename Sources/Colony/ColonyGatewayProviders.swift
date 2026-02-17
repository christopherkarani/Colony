import Foundation
import HiveCore

public struct ColonyProviderProfile: Sendable, Codable, Equatable {
    public var name: String
    public var model: String
    public var apiKey: String?
    public var apiBase: String?
    public var maxTokens: Int?
    public var temperature: Double?
    public var requestTimeoutMilliseconds: Int?
    public var connectTimeoutMilliseconds: Int?
    public var metadata: [String: String]

    public init(
        name: String,
        model: String,
        apiKey: String? = nil,
        apiBase: String? = nil,
        maxTokens: Int? = nil,
        temperature: Double? = nil,
        requestTimeoutMilliseconds: Int? = nil,
        connectTimeoutMilliseconds: Int? = nil,
        metadata: [String: String] = [:]
    ) {
        self.name = name
        self.model = model
        self.apiKey = apiKey
        self.apiBase = apiBase
        self.maxTokens = maxTokens
        self.temperature = temperature
        self.requestTimeoutMilliseconds = requestTimeoutMilliseconds
        self.connectTimeoutMilliseconds = connectTimeoutMilliseconds
        self.metadata = metadata
    }
}

public enum ColonyProviderError: Error, Sendable, Equatable, CustomStringConvertible {
    case missingConfiguration(String)
    case unknownProvider(String)
    case invalidAPIKey(String)
    case throttled(String)
    case malformedResponse(String)
    case underlying(provider: String, message: String)

    public var description: String {
        switch self {
        case .missingConfiguration(let details):
            return "Missing provider configuration: \(details)"
        case .unknownProvider(let name):
            return "Unknown provider: \(name)"
        case .invalidAPIKey(let name):
            return "Invalid API key for provider: \(name)"
        case .throttled(let name):
            return "Provider throttled: \(name)"
        case .malformedResponse(let name):
            return "Malformed provider response: \(name)"
        case .underlying(let provider, let message):
            return "Provider '\(provider)' failed: \(message)"
        }
    }
}

public struct ColonyProviderSelection: Sendable, Codable, Equatable {
    public var preferredProviderName: String?
    public var fallbackProviderNames: [String]
    public var modelOverride: String?

    public init(
        preferredProviderName: String? = nil,
        fallbackProviderNames: [String] = [],
        modelOverride: String? = nil
    ) {
        self.preferredProviderName = preferredProviderName
        self.fallbackProviderNames = fallbackProviderNames
        self.modelOverride = modelOverride
    }
}

public struct ColonyProviderRoutingConfiguration: Sendable {
    public var defaultProviderName: String
    public var fallbackProviderNames: [String]
    public var policy: ColonyProviderRouter.Policy

    public init(
        defaultProviderName: String,
        fallbackProviderNames: [String] = [],
        policy: ColonyProviderRouter.Policy = .init()
    ) {
        self.defaultProviderName = defaultProviderName
        self.fallbackProviderNames = fallbackProviderNames
        self.policy = policy
    }
}

public struct ColonyResolvedProvider: Sendable {
    public var profile: ColonyProviderProfile
    public var client: AnyHiveModelClient

    public init(profile: ColonyProviderProfile, client: AnyHiveModelClient) {
        self.profile = profile
        self.client = client
    }
}

public protocol ColonyProviderRegistry: Sendable {
    func upsert(
        profile: ColonyProviderProfile,
        clientFactory: @escaping @Sendable (ColonyProviderProfile) throws -> AnyHiveModelClient
    ) async

    func resolve(
        defaultProviderName: String,
        defaultFallbackProviderNames: [String],
        selection: ColonyProviderSelection?
    ) async throws -> [ColonyResolvedProvider]
}

public actor ColonyInMemoryProviderRegistry: ColonyProviderRegistry {
    private var profilesByName: [String: ColonyProviderProfile] = [:]
    private var clientFactoriesByName: [String: @Sendable (ColonyProviderProfile) throws -> AnyHiveModelClient] = [:]

    public init() {}

    public func upsert(
        profile: ColonyProviderProfile,
        clientFactory: @escaping @Sendable (ColonyProviderProfile) throws -> AnyHiveModelClient
    ) {
        profilesByName[profile.name] = profile
        clientFactoriesByName[profile.name] = clientFactory
    }

    public func resolve(
        defaultProviderName: String,
        defaultFallbackProviderNames: [String],
        selection: ColonyProviderSelection?
    ) throws -> [ColonyResolvedProvider] {
        let trimmedDefault = defaultProviderName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedDefault.isEmpty == false else {
            throw ColonyProviderError.missingConfiguration("default provider name")
        }

        var orderedNames: [String] = []
        orderedNames.reserveCapacity(1 + defaultFallbackProviderNames.count + (selection?.fallbackProviderNames.count ?? 0))

        if let preferred = selection?.preferredProviderName?.trimmingCharacters(in: .whitespacesAndNewlines),
           preferred.isEmpty == false
        {
            orderedNames.append(preferred)
        } else {
            orderedNames.append(trimmedDefault)
        }

        orderedNames.append(contentsOf: defaultFallbackProviderNames)
        orderedNames.append(contentsOf: selection?.fallbackProviderNames ?? [])

        var seen: Set<String> = []
        let dedupedNames = orderedNames.filter { name in
            guard seen.contains(name) == false else { return false }
            seen.insert(name)
            return true
        }

        let modelOverride = selection?.modelOverride?.trimmingCharacters(in: .whitespacesAndNewlines)

        var resolved: [ColonyResolvedProvider] = []
        resolved.reserveCapacity(dedupedNames.count)

        for (index, providerName) in dedupedNames.enumerated() {
            guard var profile = profilesByName[providerName] else {
                throw ColonyProviderError.unknownProvider(providerName)
            }
            guard let factory = clientFactoriesByName[providerName] else {
                throw ColonyProviderError.missingConfiguration("client factory for provider '\(providerName)'")
            }

            if index == 0, let modelOverride, modelOverride.isEmpty == false {
                profile.model = modelOverride
            }

            let trimmedModel = profile.model.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmedModel.isEmpty == false else {
                throw ColonyProviderError.missingConfiguration("model for provider '\(providerName)'")
            }

            if let apiKey = profile.apiKey,
               apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            {
                throw ColonyProviderError.invalidAPIKey(providerName)
            }

            let baseClient: AnyHiveModelClient
            do {
                baseClient = try factory(profile)
            } catch {
                throw ColonyProviderError.underlying(
                    provider: providerName,
                    message: error.localizedDescription
                )
            }

            let client = AnyHiveModelClient(
                ColonyProviderBoundModelClient(
                    providerName: providerName,
                    modelName: profile.model,
                    base: baseClient
                )
            )
            resolved.append(ColonyResolvedProvider(profile: profile, client: client))
        }

        guard resolved.isEmpty == false else {
            throw ColonyProviderError.missingConfiguration("resolved providers")
        }

        return resolved
    }
}

private struct ColonyProviderBoundModelClient: HiveModelClient, Sendable {
    let providerName: String
    let modelName: String
    let base: AnyHiveModelClient

    func complete(_ request: HiveChatRequest) async throws -> HiveChatResponse {
        do {
            return try await base.complete(rewrite(request))
        } catch {
            throw classify(error)
        }
    }

    func stream(_ request: HiveChatRequest) -> AsyncThrowingStream<HiveChatStreamChunk, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    for try await chunk in base.stream(rewrite(request)) {
                        continuation.yield(chunk)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: classify(error))
                }
            }
        }
    }

    private func rewrite(_ request: HiveChatRequest) -> HiveChatRequest {
        HiveChatRequest(
            model: modelName,
            messages: request.messages,
            tools: request.tools
        )
    }

    private func classify(_ error: Error) -> ColonyProviderError {
        if let providerError = error as? ColonyProviderError {
            return providerError
        }

        let message = error.localizedDescription.lowercased()
        if message.contains("401") || message.contains("invalid api key") || message.contains("unauthorized") {
            return .invalidAPIKey(providerName)
        }
        if message.contains("429") || message.contains("rate") || message.contains("throttl") {
            return .throttled(providerName)
        }
        if message.contains("decode") || message.contains("json") || message.contains("malformed") {
            return .malformedResponse(providerName)
        }
        return .underlying(provider: providerName, message: error.localizedDescription)
    }
}
