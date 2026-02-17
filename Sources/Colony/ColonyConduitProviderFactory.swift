import Foundation
import HiveCore
import HiveConduit
import Conduit

public enum ColonyConduitProviderKind: String, Sendable, Codable, Equatable {
    case openAI = "openai"
    case openRouter = "openrouter"
    case ollama
    case anthropic
    case foundationModels = "foundation_models"
}

public enum ColonyConduitProviderFactoryError: Error, Sendable, Equatable, CustomStringConvertible {
    case unsupportedProvider(String)
    case missingAPIKey(String)
    case invalidAPIBase(String)

    public var description: String {
        switch self {
        case .unsupportedProvider(let provider):
            return "Unsupported Conduit provider: \(provider)"
        case .missingAPIKey(let provider):
            return "Missing API key for provider: \(provider)"
        case .invalidAPIBase(let value):
            return "Invalid provider apiBase URL: \(value)"
        }
    }
}

public struct ColonyConduitProviderFactory: Sendable {
    public init() {}

    public func providerKind(for profile: ColonyProviderProfile) -> ColonyConduitProviderKind {
        if let explicit = profile.metadata["provider"]?.lowercased().trimmingCharacters(in: .whitespacesAndNewlines),
           let kind = ColonyConduitProviderKind(rawValue: explicit)
        {
            return kind
        }

        let normalizedName = profile.name.lowercased()
        if normalizedName.contains("anthropic") {
            return .anthropic
        }
        if normalizedName.contains("openrouter") {
            return .openRouter
        }
        if normalizedName.contains("ollama") {
            return .ollama
        }
        if normalizedName.contains("foundation") || normalizedName.contains("apple") {
            return .foundationModels
        }
        return .openAI
    }

    public func makeClient(profile: ColonyProviderProfile) throws -> AnyHiveModelClient {
        let kind = providerKind(for: profile)
        switch kind {
        case .openAI, .openRouter, .ollama:
            return try makeOpenAICompatibleClient(profile: profile, kind: kind)
        case .anthropic:
            return try makeAnthropicClient(profile: profile)
        case .foundationModels:
            return try makeFoundationModelsClient(profile: profile)
        }
    }

    public func register(
        profiles: [ColonyProviderProfile],
        in registry: any ColonyProviderRegistry
    ) async throws {
        for profile in profiles {
            let client = try makeClient(profile: profile)
            await registry.upsert(profile: profile) { _ in
                client
            }
        }
    }

    private func makeGenerateConfig(profile: ColonyProviderProfile) -> GenerateConfig {
        var config = GenerateConfig.default
        if let maxTokens = profile.maxTokens {
            config = config.maxTokens(maxTokens)
        }
        if let temperature = profile.temperature {
            config = config.temperature(Float(temperature))
        }
        return config
    }

    private func makeOpenAICompatibleClient(
        profile: ColonyProviderProfile,
        kind: ColonyConduitProviderKind
    ) throws -> AnyHiveModelClient {
        if kind != .ollama,
           profile.apiKey?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false
        {
            throw ColonyConduitProviderFactoryError.missingAPIKey(profile.name)
        }

        let endpoint: OpenAIEndpoint = {
            if let apiBase = profile.apiBase?.trimmingCharacters(in: .whitespacesAndNewlines),
               apiBase.isEmpty == false
            {
                guard let url = URL(string: apiBase) else {
                    return .custom(URL(fileURLWithPath: "/invalid-url"))
                }
                return .custom(url)
            }

            switch kind {
            case .openRouter:
                return .openRouter
            case .ollama:
                return .ollama()
            case .openAI, .anthropic, .foundationModels:
                return .openAI
            }
        }()

        if case .custom(let url) = endpoint, url.isFileURL {
            throw ColonyConduitProviderFactoryError.invalidAPIBase(profile.apiBase ?? "")
        }

        let provider = OpenAIProvider(
            endpoint: endpoint,
            apiKey: profile.apiKey
        )
        let client = ConduitModelClient(
            provider: provider,
            config: makeGenerateConfig(profile: profile),
            modelIDForName: { modelName in
                OpenAIModelID(modelName)
            }
        )
        return AnyHiveModelClient(client)
    }

    private func makeAnthropicClient(profile: ColonyProviderProfile) throws -> AnyHiveModelClient {
        guard let apiKey = profile.apiKey?.trimmingCharacters(in: .whitespacesAndNewlines),
              apiKey.isEmpty == false
        else {
            throw ColonyConduitProviderFactoryError.missingAPIKey(profile.name)
        }

        var config = AnthropicConfiguration.standard(apiKey: apiKey)
        if let requestTimeoutMilliseconds = profile.requestTimeoutMilliseconds,
           requestTimeoutMilliseconds > 0
        {
            config = config.timeout(Double(requestTimeoutMilliseconds) / 1_000.0)
        }

        if let apiBase = profile.apiBase?.trimmingCharacters(in: .whitespacesAndNewlines),
           apiBase.isEmpty == false
        {
            guard let url = URL(string: apiBase) else {
                throw ColonyConduitProviderFactoryError.invalidAPIBase(apiBase)
            }
            config = try config.baseURL(url)
        }

        let provider = AnthropicProvider(configuration: config)
        let client = ConduitModelClient(
            provider: provider,
            config: makeGenerateConfig(profile: profile),
            modelIDForName: { modelName in
                AnthropicModelID(modelName)
            }
        )
        return AnyHiveModelClient(client)
    }

    private func makeFoundationModelsClient(profile: ColonyProviderProfile) throws -> AnyHiveModelClient {
        guard #available(iOS 26.0, macOS 26.0, visionOS 26.0, *) else {
            throw ColonyConduitProviderFactoryError.unsupportedProvider(profile.name)
        }

        let provider = FoundationModelsProvider()
        let client = ConduitModelClient(
            provider: provider,
            config: makeGenerateConfig(profile: profile),
            modelIDForName: { _ in
                ModelIdentifier.foundationModels
            }
        )
        return AnyHiveModelClient(client)
    }
}

public extension ColonyGatewayRuntime {
    static func makeBatteriesIncludedConduitRuntime(
        providerProfiles: [ColonyProviderProfile],
        defaultProviderName: String,
        fallbackProviderNames: [String] = [],
        profile: ColonyProfile = .onDevice4k,
        lane: ColonyLane? = nil,
        agentID: String = "colony-agent",
        executionPolicy: ColonyExecutionPolicy = ColonyExecutionPolicy(),
        providerPolicy: ColonyProviderRouter.Policy = ColonyProviderRouter.Policy(),
        sessionStore: any ColonyRuntimeSessionStore = ColonyInMemoryRuntimeSessionStore(),
        checkpointStore: (any ColonyRuntimeCheckpointStore)? = nil,
        toolRegistry: ColonyRuntimeToolRegistry? = nil,
        messageSink: (any ColonyMessageSink)? = nil,
        runOptionsOverride: HiveRunOptions? = nil,
        backends: ColonyGatewayBackends = ColonyGatewayBackends()
    ) async throws -> ColonyGatewayRuntime {
        let registry = ColonyInMemoryProviderRegistry()
        let factory = ColonyConduitProviderFactory()
        try await factory.register(profiles: providerProfiles, in: registry)

        return ColonyGatewayRuntime(
            configuration: ColonyGatewayRuntimeConfiguration(
                profile: profile,
                lane: lane,
                agentID: agentID,
                providers: ColonyProviderRoutingConfiguration(
                    defaultProviderName: defaultProviderName,
                    fallbackProviderNames: fallbackProviderNames,
                    policy: providerPolicy
                ),
                defaultExecutionPolicy: executionPolicy,
                providerRegistry: registry,
                sessionStore: sessionStore,
                checkpointStore: checkpointStore,
                toolRegistry: toolRegistry,
                messageSink: messageSink,
                runOptionsOverride: runOptionsOverride
            ),
            backends: backends
        )
    }
}
