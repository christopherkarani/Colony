import Foundation
import ColonyCore
import MembraneCore
import Swarm
import struct Swarm.MembraneEnvironment
import struct Swarm.MembraneFeatureConfiguration

public struct ColonyFoundationModelConfiguration: Sendable, Equatable {
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

public struct ColonyOnDeviceModelPolicy: Sendable, Equatable {
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

public struct ColonyProvider: Sendable {
    public let id: String
    public let client: AnyColonyModelClient
    public let capabilities: ColonyModelCapabilities
    public let priority: Int
    public let maxRequestsPerMinute: Int?
    public let usdPer1KTokens: Double?

    public init(
        id: String,
        client: some ColonyModelClient,
        capabilities: ColonyModelCapabilities = [],
        priority: Int = 0,
        maxRequestsPerMinute: Int? = nil,
        usdPer1KTokens: Double? = nil
    ) {
        self.id = id
        self.client = AnyColonyModelClient(client)
        self.capabilities = capabilities
        self.priority = priority
        self.maxRequestsPerMinute = maxRequestsPerMinute
        self.usdPer1KTokens = usdPer1KTokens
    }
}

public struct ColonyProviderRoutingPolicy: Sendable, Equatable {
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

public struct ColonyModel: Sendable {
    package enum Storage: Sendable {
        case client(AnyColonyModelClient, ColonyModelCapabilities)
        case router(AnyColonyModelRouter, ColonyModelCapabilities?)
        case foundationModels(ColonyFoundationModelConfiguration)
        case onDeviceFallback(
            fallback: AnyColonyModelClient,
            fallbackCapabilities: ColonyModelCapabilities,
            policy: ColonyOnDeviceModelPolicy,
            foundationModels: ColonyFoundationModelConfiguration
        )
        case providerRouting([ColonyProvider], ColonyProviderRoutingPolicy)
    }

    package let storage: Storage

    public init(
        client: some ColonyModelClient,
        capabilities: ColonyModelCapabilities = []
    ) {
        self.storage = .client(AnyColonyModelClient(client), capabilities)
    }

    public init(
        router: some ColonyModelRouter,
        capabilities: ColonyModelCapabilities? = nil
    ) {
        self.storage = .router(AnyColonyModelRouter(router), capabilities)
    }

    public static func foundationModels(
        configuration: ColonyFoundationModelConfiguration = ColonyFoundationModelConfiguration()
    ) -> ColonyModel {
        ColonyModel(storage: .foundationModels(configuration))
    }

    public static func onDevice(
        fallback: some ColonyModelClient,
        fallbackCapabilities: ColonyModelCapabilities = [],
        policy: ColonyOnDeviceModelPolicy = ColonyOnDeviceModelPolicy(),
        foundationModels: ColonyFoundationModelConfiguration = ColonyFoundationModelConfiguration()
    ) -> ColonyModel {
        ColonyModel(
            storage: .onDeviceFallback(
                fallback: AnyColonyModelClient(fallback),
                fallbackCapabilities: fallbackCapabilities,
                policy: policy,
                foundationModels: foundationModels
            )
        )
    }

    public static func providerRouting(
        providers: [ColonyProvider],
        policy: ColonyProviderRoutingPolicy = ColonyProviderRoutingPolicy()
    ) -> ColonyModel {
        ColonyModel(storage: .providerRouting(providers, policy))
    }

    private init(storage: Storage) {
        self.storage = storage
    }
}

public struct ColonyRuntimeServices: Sendable {
    public var tools: AnyColonyToolRegistry?
    public var swarmTools: SwarmToolBridge?
    public var membrane: MembraneEnvironment?
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

    public init(
        tools: AnyColonyToolRegistry? = nil,
        swarmTools: SwarmToolBridge? = nil,
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

public struct ColonyRuntimeCreationOptions: Sendable {
    public var profile: ColonyProfile
    public var threadID: ColonyThreadID
    public var modelName: String
    public var lane: ColonyLane?
    public var intent: String?
    public var model: ColonyModel
    public var services: ColonyRuntimeServices
    public var checkpointing: ColonyCheckpointConfiguration
    public var configure: @Sendable (inout ColonyConfiguration) -> Void
    public var configureRunOptions: @Sendable (inout ColonyRunOptions) -> Void

    public init(
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

public struct ColonyBootstrapOptions: Sendable {
    public var runtime: ColonyRuntimeCreationOptions
    public var durableMemoryStoreURL: URL?
    public var membraneStoreURL: URL?
    public var membraneConfiguration: MembraneFeatureConfiguration
    public var membraneBudget: MembraneCore.ContextBudget

    public init(
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
