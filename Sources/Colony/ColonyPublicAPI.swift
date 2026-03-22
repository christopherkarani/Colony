import Foundation
import ColonyCore
import MembraneCore
import Swarm
import struct Swarm.MembraneEnvironment
import struct Swarm.MembraneFeatureConfiguration

/// Configuration for the AI model used by Colony runtime.
///
/// `ColonyModel` is created using factory methods and passed to `Colony.agent()`.
/// It configures which AI model to use and how to route between providers.
///
/// ## Factory Methods
///
/// ```swift
/// // Apple Foundation Models (on-device)
/// let model = ColonyModel.foundationModels()
///
/// // On-device with cloud fallback
/// let model = ColonyModel.onDevice(fallback: myClient)
///
/// // Multi-provider routing
/// let model = ColonyModel.providerRouting([
///     Provider(id: .ollama, client: ollamaClient, priority: 1),
///     Provider(id: .foundationModels, client: fmClient, priority: 2),
/// ])
/// ```
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

        public enum NetworkBehavior: Sendable, Equatable {
            /// Always fall back to cloud when on-device is unavailable.
            case alwaysFallback
            /// Prefer on-device when the network is offline.
            case preferOnDeviceWhenOffline
            /// Prefer on-device when the network is metered.
            case preferOnDeviceWhenMetered
            /// Prefer on-device when either offline or metered (default).
            case preferOnDeviceWhenOfflineOrMetered
        }

        public var privacyBehavior: PrivacyBehavior
        public var networkBehavior: NetworkBehavior

        public init(
            privacyBehavior: PrivacyBehavior = .preferOnDevice,
            networkBehavior: NetworkBehavior = .preferOnDeviceWhenOfflineOrMetered
        ) {
            self.privacyBehavior = privacyBehavior
            self.networkBehavior = networkBehavior
        }

        /// Deprecated: Use `init(privacyBehavior:networkBehavior:)` instead.
        @available(*, deprecated, message: "Use init(privacyBehavior:networkBehavior:) instead")
        public init(
            privacyBehavior: PrivacyBehavior = .preferOnDevice,
            preferOnDeviceWhenOffline: Bool = true,
            preferOnDeviceWhenMetered: Bool = true
        ) {
            self.privacyBehavior = privacyBehavior
            switch (preferOnDeviceWhenOffline, preferOnDeviceWhenMetered) {
            case (true, true):
                self.networkBehavior = .preferOnDeviceWhenOfflineOrMetered
            case (true, false):
                self.networkBehavior = .preferOnDeviceWhenOffline
            case (false, true):
                self.networkBehavior = .preferOnDeviceWhenMetered
            case (false, false):
                self.networkBehavior = .alwaysFallback
            }
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
        public let usdPer1KTokens: ColonyCost?

        public init(
            id: ProviderID,
            client: some ColonyModelClient,
            capabilities: ColonyModelCapabilities = [],
            priority: Int = 0,
            maxRequestsPerMinute: Int? = nil,
            usdPer1KTokens: ColonyCost? = nil
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
        public var initialBackoff: Duration
        public var maxBackoff: Duration
        public var globalMaxRequestsPerMinute: Int?
        public var costCeilingUSD: ColonyCost?
        public var estimatedOutputToInputRatio: Double
        public var gracefulDegradation: GracefulDegradationPolicy

        public init(
            maxAttemptsPerProvider: Int = 2,
            initialBackoff: Duration = .milliseconds(100),
            maxBackoff: Duration = .seconds(1),
            globalMaxRequestsPerMinute: Int? = nil,
            costCeilingUSD: ColonyCost? = nil,
            estimatedOutputToInputRatio: Double = 0.5,
            gracefulDegradation: GracefulDegradationPolicy = .fail
        ) {
            self.maxAttemptsPerProvider = max(1, maxAttemptsPerProvider)
            self.initialBackoff = initialBackoff
            self.maxBackoff = max(initialBackoff, maxBackoff)
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

/// Container for all service backends registered with a Colony runtime.
///
/// `ColonyRuntimeServices` holds the backend implementations that power Colony's tools.
/// Services are registered via `ColonyRuntimeServices.init(@ColonyServiceBuilder)` using
/// the `@ColonyServiceBuilder` DSL:
///
/// ```swift
/// let services = ColonyRuntimeServices {
///     .filesystem(ColonyFileSystem.DiskBackend(root: projectURL))
///     .shell(ColonyHardenedShellBackend())
///     .memory(waxMemory)
/// }
/// ```
///
/// Each service type maps to a `ColonyAgentCapabilities` flag:
/// - `.filesystem` → `ColonyFileSystemBackend`
/// - `.shell` → `ColonyShellBackend`
/// - `.git` → `ColonyGitBackend`
/// - `.memory` → `ColonyMemoryBackend`
/// - etc.
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
    package var modelName: ColonyModelName
    package var lane: ColonyLane?
    package var intent: String?
    package var model: ColonyModel
    package var services: ColonyRuntimeServices
    package var checkpointing: ColonyRun.CheckpointConfiguration
    package var configure: @Sendable (inout ColonyConfiguration) -> Void
    package var configureRunOptions: @Sendable (inout ColonyRun.Options) -> Void

    package init(
        profile: ColonyProfile = .onDevice4k,
        threadID: ColonyThreadID = ColonyThreadID("colony:" + UUID().uuidString),
        modelName: ColonyModelName,
        lane: ColonyLane? = nil,
        intent: String? = nil,
        model: ColonyModel,
        services: ColonyRuntimeServices = ColonyRuntimeServices(),
        checkpointing: ColonyRun.CheckpointConfiguration = .inMemory,
        configure: @escaping @Sendable (inout ColonyConfiguration) -> Void = { _ in },
        configureRunOptions: @escaping @Sendable (inout ColonyRun.Options) -> Void = { _ in }
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
