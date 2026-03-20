import Foundation
import ColonyCore
import MembraneCore
import Swarm
import struct Swarm.MembraneEnvironment
import struct Swarm.MembraneFeatureConfiguration

public struct ColonyModel: Sendable {

    // MARK: - Nested Configuration Types

    public struct FoundationModelConfiguration: Sendable, Equatable {
        public enum ToolInstructionVerbosity: Sendable, Equatable {
            case compact
            case verbose
        }

        public var additionalInstructions: String?
        public var prewarmSession: Bool
        public var toolInstructionVerbosity: ToolInstructionVerbosity

        public init(
            additionalInstructions: String? = nil,
            prewarmSession: Bool = false,
            toolInstructionVerbosity: ToolInstructionVerbosity = .compact
        ) {
            self.additionalInstructions = additionalInstructions
            self.prewarmSession = prewarmSession
            self.toolInstructionVerbosity = toolInstructionVerbosity
        }
    }

    public struct OnDevicePolicy: Sendable, Equatable {
        public enum PrivacyBehavior: Sendable, Equatable {
            case preferOnDevice
            case requireOnDevice
        }

        public var privacyBehavior: PrivacyBehavior
        public var preferOnDeviceWhenOffline: Bool
        public var preferOnDeviceWhenMetered: Bool

        public init(
            privacyBehavior: PrivacyBehavior = .preferOnDevice,
            preferOnDeviceWhenOffline: Bool = true,
            preferOnDeviceWhenMetered: Bool = true
        ) {
            self.privacyBehavior = privacyBehavior
            self.preferOnDeviceWhenOffline = preferOnDeviceWhenOffline
            self.preferOnDeviceWhenMetered = preferOnDeviceWhenMetered
        }
    }

    /// Type-safe provider identifier with autocomplete for common providers.
    public struct ProviderID: Hashable, Codable, Sendable,
                              ExpressibleByStringLiteral,
                              CustomStringConvertible {
        public let rawValue: String
        public init(_ rawValue: String) { self.rawValue = rawValue }
        public init(stringLiteral value: String) { self.init(value) }
        public var description: String { rawValue }

        public static let anthropic: ProviderID = "anthropic"
        public static let openAI: ProviderID = "openai"
        public static let foundationModels: ProviderID = "foundation_models"
        public static let ollama: ProviderID = "ollama"
    }

    public struct Provider: Sendable {
        public let id: ProviderID
        public let client: any ColonyModelClient
        public let capabilities: ColonyModelCapabilities
        public let priority: Int
        public let maxRequestsPerMinute: Int?
        public let usdPer1KTokens: Double?

        public init(
            id: ProviderID,
            client: some ColonyModelClient,
            capabilities: ColonyModelCapabilities = [],
            priority: Int = 0,
            maxRequestsPerMinute: Int? = nil,
            usdPer1KTokens: Double? = nil
        ) {
            self.id = id
            self.client = client
            self.capabilities = capabilities
            self.priority = priority
            self.maxRequestsPerMinute = maxRequestsPerMinute
            self.usdPer1KTokens = usdPer1KTokens
        }
    }

    public struct RoutingPolicy: Sendable, Equatable {
        public enum GracefulDegradationPolicy: Sendable, Equatable {
            case fail
            case syntheticResponse(String)
        }

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

    // MARK: - Storage

    package enum Storage: Sendable {
        case client(any ColonyModelClient, ColonyModelCapabilities)
        case router(any ColonyModelRouter, ColonyModelCapabilities?)
        case foundationModels(FoundationModelConfiguration)
        case onDeviceFallback(
            fallback: any ColonyModelClient,
            fallbackCapabilities: ColonyModelCapabilities,
            policy: OnDevicePolicy,
            foundationModels: FoundationModelConfiguration
        )
        case providerRouting([Provider], RoutingPolicy)
    }

    package let storage: Storage

    // MARK: - Initializers

    public init(
        client: some ColonyModelClient,
        capabilities: ColonyModelCapabilities = []
    ) {
        self.storage = .client(client, capabilities)
    }

    public init(
        router: some ColonyModelRouter,
        capabilities: ColonyModelCapabilities? = nil
    ) {
        self.storage = .router(router, capabilities)
    }

    // MARK: - Factory Methods

    public static func foundationModels(
        configuration: FoundationModelConfiguration = FoundationModelConfiguration()
    ) -> ColonyModel {
        ColonyModel(storage: .foundationModels(configuration))
    }

    public static func onDevice(
        fallback: some ColonyModelClient,
        fallbackCapabilities: ColonyModelCapabilities = [],
        policy: OnDevicePolicy = OnDevicePolicy(),
        foundationModels: FoundationModelConfiguration = FoundationModelConfiguration()
    ) -> ColonyModel {
        ColonyModel(
            storage: .onDeviceFallback(
                fallback: fallback,
                fallbackCapabilities: fallbackCapabilities,
                policy: policy,
                foundationModels: foundationModels
            )
        )
    }

    public static func providerRouting(
        providers: [Provider],
        policy: RoutingPolicy = RoutingPolicy()
    ) -> ColonyModel {
        ColonyModel(storage: .providerRouting(providers, policy))
    }

    private init(storage: Storage) {
        self.storage = storage
    }
}

// MARK: - Backward-Compatible Typealiases

@available(*, deprecated, renamed: "ColonyModel.FoundationModelConfiguration")
public typealias ColonyFoundationModelConfiguration = ColonyModel.FoundationModelConfiguration
@available(*, deprecated, renamed: "ColonyModel.OnDevicePolicy")
public typealias ColonyOnDeviceModelPolicy = ColonyModel.OnDevicePolicy
@available(*, deprecated, renamed: "ColonyModel.ProviderID")
public typealias ColonyProviderID = ColonyModel.ProviderID
@available(*, deprecated, renamed: "ColonyModel.Provider")
public typealias ColonyProvider = ColonyModel.Provider
@available(*, deprecated, renamed: "ColonyModel.RoutingPolicy")
public typealias ColonyProviderRoutingPolicy = ColonyModel.RoutingPolicy

public struct ColonyRuntimeServices: Sendable {
    public var tools: (any ColonyToolRegistry)?
    package var swarmTools: (any ColonySwarmToolBridging)?
    package var membrane: MembraneEnvironment?
    public var filesystem: (any ColonyFileSystemBackend)?
    public var shell: (any ColonyShellBackend)?
    public var git: (any ColonyGitBackend)?
    public var lsp: (any ColonyLSPBackend)?
    public var applyPatch: (any ColonyApplyPatchBackend)?
    public var webSearch: (any ColonyWebSearchBackend)?
    public var codeSearch: (any ColonyCodeSearchBackend)?
    public var mcp: (any ColonyMCPBackend)?
    public var memory: (any ColonyMemoryBackend)?
    public var plugins: (any ColonyPluginToolRegistry)?
    public var subagents: (any ColonySubagentRegistry)?

    public init() {
        self.tools = nil
        self.swarmTools = nil
        self.membrane = nil
        self.filesystem = ColonyInMemoryFileSystemBackend()
        self.shell = nil
        self.git = nil
        self.lsp = nil
        self.applyPatch = nil
        self.webSearch = nil
        self.codeSearch = nil
        self.mcp = nil
        self.memory = nil
        self.plugins = nil
        self.subagents = nil
    }

    package init(
        tools: (any ColonyToolRegistry)? = nil,
        swarmTools: (any ColonySwarmToolBridging)? = nil,
        membrane: MembraneEnvironment? = nil,
        filesystem: (any ColonyFileSystemBackend)? = ColonyInMemoryFileSystemBackend(),
        shell: (any ColonyShellBackend)? = nil,
        git: (any ColonyGitBackend)? = nil,
        lsp: (any ColonyLSPBackend)? = nil,
        applyPatch: (any ColonyApplyPatchBackend)? = nil,
        webSearch: (any ColonyWebSearchBackend)? = nil,
        codeSearch: (any ColonyCodeSearchBackend)? = nil,
        mcp: (any ColonyMCPBackend)? = nil,
        memory: (any ColonyMemoryBackend)? = nil,
        plugins: (any ColonyPluginToolRegistry)? = nil,
        subagents: (any ColonySubagentRegistry)? = nil
    ) {
        self.tools = tools
        self.swarmTools = swarmTools
        self.membrane = membrane
        self.filesystem = filesystem
        self.shell = shell
        self.git = git
        self.lsp = lsp
        self.applyPatch = applyPatch
        self.webSearch = webSearch
        self.codeSearch = codeSearch
        self.mcp = mcp
        self.memory = memory
        self.plugins = plugins
        self.subagents = subagents
    }
}

package struct ColonyRuntimeCreationOptions: Sendable {
    package var profile: ColonyProfile
    package var threadID: ColonyThreadID
    package var modelName: String
    package var lane: ColonyLane?
    package var intent: String?
    package var model: ColonyModel
    package var services: ColonyRuntimeServices
    package var checkpointing: ColonyCheckpointConfiguration
    package var configure: @Sendable (inout ColonyConfiguration) -> Void
    package var configureRunOptions: @Sendable (inout ColonyRunOptions) -> Void

    package init(
        profile: ColonyProfile = .onDevice4k,
        threadID: ColonyThreadID = ColonyThreadID("colony:" + UUID().uuidString),
        modelName: String,
        lane: ColonyLane? = nil,
        intent: String? = nil,
        model: ColonyModel,
        services: ColonyRuntimeServices = ColonyRuntimeServices(),
        checkpointing: ColonyCheckpointConfiguration = .inMemory,
        configure: @escaping @Sendable (inout ColonyConfiguration) -> Void = { _ in },
        configureRunOptions: @escaping @Sendable (inout ColonyRunOptions) -> Void = { _ in }
    ) {
        self.profile = profile
        self.threadID = threadID
        self.modelName = modelName
        self.lane = lane
        self.intent = intent
        self.model = model
        self.services = services
        self.checkpointing = checkpointing
        self.configure = configure
        self.configureRunOptions = configureRunOptions
    }
}

package struct ColonyBootstrapOptions: Sendable {
    package var runtime: ColonyRuntimeCreationOptions
    package var durableMemoryStoreURL: URL?
    package var membraneStoreURL: URL?
    package var membraneConfiguration: MembraneFeatureConfiguration
    package var membraneBudget: MembraneCore.ContextBudget

    package init(
        runtime: ColonyRuntimeCreationOptions,
        durableMemoryStoreURL: URL? = nil,
        membraneStoreURL: URL? = nil,
        membraneConfiguration: MembraneFeatureConfiguration = .default,
        membraneBudget: MembraneCore.ContextBudget = MembraneCore.ContextBudget(
            totalTokens: 4096,
            profile: .foundationModels4K
        )
    ) {
        self.runtime = runtime
        self.durableMemoryStoreURL = durableMemoryStoreURL
        self.membraneStoreURL = membraneStoreURL
        self.membraneConfiguration = membraneConfiguration
        self.membraneBudget = membraneBudget
    }
}
