import Dispatch
import Foundation
import ColonyCore

// MARK: - Builder Error

/// Error thrown when ColonyBuilder configuration is invalid.
public struct ColonyBuilderError: Error, Sendable {
    /// A description of the error.
    public let message: String

    /// Creates a new builder error.
    ///
    /// - Parameter message: The error message.
    public init(message: String) {
        self.message = message
    }
}

/// Profile presets for Colony runtime configuration.
///
/// Use profiles to quickly configure Colony for different deployment scenarios.
/// Each profile sets appropriate token limits, compaction policies, and tool approval rules.
public enum ColonyProfile: Sendable {
    /// Optimize for on-device runtimes with smaller context windows.
    ///
    /// This profile uses:
    /// - Strict ~4k token budget
    /// - Compaction at 2,600 tokens
    /// - Tool result eviction at 700 tokens
    /// - Scratchbook enabled for state persistence
    /// - AllowList tool approval policy for built-in safe tools
    case device

    /// Optimize for larger context windows and cloud runtimes.
    ///
    /// This profile uses:
    /// - Generous token limits (compaction at 12k, eviction at 20k)
    /// - No scratchbook by default
    /// - No tool approval required (`.never` policy)
    case cloud
}

extension ColonyProfile {
    public static let onDevice4k: Self = .device
}

/// Deprecated type alias for backward compatibility. Use `AgentMode` instead.
public typealias ColonyLane = AgentMode

/// Configuration preset for specialized agent lanes.
///
/// Lanes provide focused configurations for specific task types
/// (coding, research, knowledge retrieval).
public struct ColonyLaneConfigurationPreset: Sendable {
    /// Capabilities required for this lane.
    public var requiredCapabilities: ColonyCapabilities

    /// Whether to include the tool list in the system prompt.
    public var includeToolListInSystemPrompt: Bool?

    /// Additional instructions appended to the system prompt.
    public var additionalSystemPrompt: String?

    /// Creates a new lane configuration preset.
    ///
    /// - Parameters:
    ///   - requiredCapabilities: Required agent capabilities.
    ///   - includeToolListInSystemPrompt: Whether to include tool list.
    ///   - additionalSystemPrompt: Additional system prompt content.
    public init(
        requiredCapabilities: ColonyCapabilities = [],
        includeToolListInSystemPrompt: Bool? = nil,
        additionalSystemPrompt: String? = nil
    ) {
        self.requiredCapabilities = requiredCapabilities
        self.includeToolListInSystemPrompt = includeToolListInSystemPrompt
        self.additionalSystemPrompt = additionalSystemPrompt
    }
}

/// System clock implementation using DispatchTime.
///
/// This clock provides monotonic time for runtime coordination.
package struct ColonySystemClock: SwarmClock, Sendable {
    public init() {}

    public func nowNanoseconds() -> UInt64 {
        DispatchTime.now().uptimeNanoseconds
    }

    public func sleep(nanoseconds: UInt64) async throws {
        try await Task.sleep(nanoseconds: nanoseconds)
    }
}

/// A no-op logger that discards all log messages.
///
/// Use this logger when logging is not needed or when running in production
/// with logging handled by external systems.
package struct ColonyNoopLogger: SwarmLogger, Sendable {
    public init() {}
    public func debug(_ message: String, metadata: [String: String]) {}
    public func info(_ message: String, metadata: [String: String]) {}
    public func error(_ message: String, metadata: [String: String]) {}
}

// MARK: - ColonyBuilder

/// Builder for configuring and creating Colony runtimes.
///
/// `ColonyBuilder` provides a fluent API for constructing `ColonyRuntime` instances
/// with custom configurations. Use the builder methods to set the model, profile,
/// capabilities, and backends, then call `build()` to create the runtime.
///
/// Example:
/// ```swift
/// let runtime = try ColonyBuilder()
///     .model(name: "llama3.2")
///     .profile(.device)
///     .capabilities([.planning, .filesystem, .subagents])
///     .build()
/// ```
///
/// Note: `ColonyAgentFactory` is a deprecated type alias for `ColonyBuilder`.
public struct ColonyBuilder: Sendable {
    private var configuration: ColonyConfiguration
    private var profile: ColonyProfile
    private var threadID: ColonyThreadID
    private var model: SwarmAnyModelClient?
    private var modelRouter: (any SwarmModelRouter)?
    private var inferenceHints: SwarmInferenceHints?
    private var tools: SwarmAnyToolRegistry?
    private var filesystem: (any ColonyFileSystemBackend)?
    private var shell: (any ColonyShellBackend)?
    private var git: (any ColonyGitService)?
    private var lsp: (any ColonyLSPBackend)?
    private var applyPatch: (any ColonyApplyPatchBackend)?
    private var webSearch: (any ColonyWebSearchBackend)?
    private var codeSearch: (any ColonyCodeSearchBackend)?
    private var mcp: (any ColonyMCPBackend)?
    private var memory: (any ColonyMemoryBackend)?
    private var plugins: (any ColonyPluginToolRegistry)?
    private var subagents: (any ColonySubagentRegistry)?
    private var checkpointStore: (any ColonyCheckpointStore)?
    private var durableCheckpointDirectoryURL: URL?
    private var clock: any SwarmClock
    private var logger: any SwarmLogger
    private var configureRunOptions: @Sendable (inout ColonyRun.Options) -> Void

    public init() {
        self.configuration = ColonyConfiguration(modelName: "")
        self.profile = .device
        self.threadID = .generate()
        self.model = nil
        self.modelRouter = nil
        self.inferenceHints = nil
        self.tools = nil
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
        self.checkpointStore = nil
        self.durableCheckpointDirectoryURL = nil
        self.clock = ColonySystemClock()
        self.logger = ColonyNoopLogger()
        self.configureRunOptions = { _ in }
    }

    private func copy(
        configuration: ColonyConfiguration? = nil,
        profile: ColonyProfile? = nil,
        threadID: ColonyThreadID? = nil,
        model: SwarmAnyModelClient?? = nil,
        modelRouter: ((any SwarmModelRouter)?)? = nil,
        inferenceHints: SwarmInferenceHints?? = nil,
        tools: SwarmAnyToolRegistry?? = nil,
        filesystem: ((any ColonyFileSystemBackend)?)? = nil,
        shell: ((any ColonyShellBackend)?)? = nil,
        git: ((any ColonyGitBackend)?)? = nil,
        lsp: ((any ColonyLSPBackend)?)? = nil,
        applyPatch: ((any ColonyApplyPatchBackend)?)? = nil,
        webSearch: ((any ColonyWebSearchBackend)?)? = nil,
        codeSearch: ((any ColonyCodeSearchBackend)?)? = nil,
        mcp: ((any ColonyMCPBackend)?)? = nil,
        memory: ((any ColonyMemoryBackend)?)? = nil,
        plugins: ((any ColonyPluginToolRegistry)?)? = nil,
        subagents: ((any ColonySubagentRegistry)?)? = nil,
        checkpointStore: ((any ColonyCheckpointStore)?)? = nil,
        durableCheckpointDirectoryURL: URL?? = nil,
        clock: (any SwarmClock)? = nil,
        logger: (any SwarmLogger)? = nil,
        configureRunOptions: (@Sendable (inout ColonyRun.Options) -> Void)? = nil
    ) -> ColonyBuilder {
        ColonyBuilder(
            configuration: configuration ?? self.configuration,
            profile: profile ?? self.profile,
            threadID: threadID ?? self.threadID,
            model: model ?? self.model,
            modelRouter: modelRouter ?? self.modelRouter,
            inferenceHints: inferenceHints ?? self.inferenceHints,
            tools: tools ?? self.tools,
            filesystem: filesystem ?? self.filesystem,
            shell: shell ?? self.shell,
            git: git ?? self.git,
            lsp: lsp ?? self.lsp,
            applyPatch: applyPatch ?? self.applyPatch,
            webSearch: webSearch ?? self.webSearch,
            codeSearch: codeSearch ?? self.codeSearch,
            mcp: mcp ?? self.mcp,
            memory: memory ?? self.memory,
            plugins: plugins ?? self.plugins,
            subagents: subagents ?? self.subagents,
            checkpointStore: checkpointStore ?? self.checkpointStore,
            durableCheckpointDirectoryURL: durableCheckpointDirectoryURL ?? self.durableCheckpointDirectoryURL,
            clock: clock ?? self.clock,
            logger: logger ?? self.logger,
            configureRunOptions: configureRunOptions ?? self.configureRunOptions
        )
    }

    private init(
        configuration: ColonyConfiguration,
        profile: ColonyProfile,
        threadID: ColonyThreadID,
        model: SwarmAnyModelClient?,
        modelRouter: (any SwarmModelRouter)?,
        inferenceHints: SwarmInferenceHints?,
        tools: SwarmAnyToolRegistry?,
        filesystem: (any ColonyFileSystemBackend)?,
        shell: (any ColonyShellBackend)?,
        git: (any ColonyGitBackend)?,
        lsp: (any ColonyLSPBackend)?,
        applyPatch: (any ColonyApplyPatchBackend)?,
        webSearch: (any ColonyWebSearchBackend)?,
        codeSearch: (any ColonyCodeSearchBackend)?,
        mcp: (any ColonyMCPBackend)?,
        memory: (any ColonyMemoryBackend)?,
        plugins: (any ColonyPluginToolRegistry)?,
        subagents: (any ColonySubagentRegistry)?,
        checkpointStore: (any ColonyCheckpointStore)?,
        durableCheckpointDirectoryURL: URL?,
        clock: any SwarmClock,
        logger: any SwarmLogger,
        configureRunOptions: @Sendable @escaping (inout ColonyRun.Options) -> Void
    ) {
        self.configuration = configuration
        self.profile = profile
        self.threadID = threadID
        self.model = model
        self.modelRouter = modelRouter
        self.inferenceHints = inferenceHints
        self.tools = tools
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
        self.checkpointStore = checkpointStore
        self.durableCheckpointDirectoryURL = durableCheckpointDirectoryURL
        self.clock = clock
        self.logger = logger
        self.configureRunOptions = configureRunOptions
    }

    // MARK: - Fluent API Methods

    /// Sets the model name for this runtime.
    ///
    /// - Parameter name: The model name (e.g., "llama3.2").
    /// - Returns: A new builder with the model name set.
    public func model(name: String) -> ColonyBuilder {
        var newConfig = configuration
        newConfig.modelName = name
        return copy(configuration: newConfig)
    }

    /// Sets the profile for this runtime.
    ///
    /// - Parameter profile: The profile to use (`.device` or `.cloud`).
    /// - Returns: A new builder with the profile set.
    public func profile(_ profile: ColonyProfile) -> ColonyBuilder {
        copy(profile: profile)
    }

    /// Sets the capabilities for this runtime.
    ///
    /// - Parameter capabilities: The capabilities to enable.
    /// - Returns: A new builder with the capabilities set.
    public func capabilities(_ capabilities: ColonyCapabilities) -> ColonyBuilder {
        var newConfig = configuration
        newConfig.capabilities = capabilities
        return copy(configuration: newConfig)
    }

    public func threadID(_ threadID: ColonyThreadID) -> ColonyBuilder {
        copy(threadID: threadID)
    }

    package func threadID(_ threadID: SwarmThreadID) -> ColonyBuilder {
        copy(threadID: ColonyThreadID(threadID.rawValue))
    }

    public func model(_ model: any ColonyModelClient) -> ColonyBuilder {
        copy(model: SwarmAnyModelClient(ColonyModelClientBridge(client: model)))
    }

    package func model(_ model: SwarmAnyModelClient) -> ColonyBuilder {
        copy(model: model)
    }

    public func modelRouter(_ modelRouter: any ColonyModelClient) -> ColonyBuilder {
        model(modelRouter)
    }

    package func modelRouter(_ modelRouter: any SwarmModelRouter) -> ColonyBuilder {
        copy(modelRouter: modelRouter)
    }

    public func routingPolicy(_ policy: ColonyRoutingPolicy) -> ColonyBuilder {
        copy(modelRouter: Self.modelRouter(policy: policy))
    }

    package func inferenceHints(_ inferenceHints: SwarmInferenceHints?) -> ColonyBuilder {
        copy(inferenceHints: inferenceHints)
    }

    package func tools(_ tools: SwarmAnyToolRegistry?) -> ColonyBuilder {
        copy(tools: tools)
    }

    public func filesystem(_ filesystem: (any ColonyFileSystemBackend)?) -> ColonyBuilder {
        copy(filesystem: filesystem)
    }

    public func shell(_ shell: (any ColonyShellBackend)?) -> ColonyBuilder {
        copy(shell: shell)
    }

    public func git(_ git: (any ColonyGitBackend)?) -> ColonyBuilder {
        copy(git: git)
    }

    public func lsp(_ lsp: (any ColonyLSPBackend)?) -> ColonyBuilder {
        copy(lsp: lsp)
    }

    public func applyPatch(_ applyPatch: (any ColonyApplyPatchBackend)?) -> ColonyBuilder {
        copy(applyPatch: applyPatch)
    }

    public func webSearch(_ webSearch: (any ColonyWebSearchBackend)?) -> ColonyBuilder {
        copy(webSearch: webSearch)
    }

    public func codeSearch(_ codeSearch: (any ColonyCodeSearchBackend)?) -> ColonyBuilder {
        copy(codeSearch: codeSearch)
    }

    public func mcp(_ mcp: (any ColonyMCPBackend)?) -> ColonyBuilder {
        copy(mcp: mcp)
    }

    public func memory(_ memory: (any ColonyMemoryBackend)?) -> ColonyBuilder {
        copy(memory: memory)
    }

    public func plugins(_ plugins: (any ColonyPluginToolRegistry)?) -> ColonyBuilder {
        copy(plugins: plugins)
    }

    public func subagents(_ subagents: (any ColonySubagentRegistry)?) -> ColonyBuilder {
        copy(subagents: subagents)
    }

    package func checkpointStore(_ checkpointStore: (any ColonyCheckpointStore)?) -> ColonyBuilder {
        copy(checkpointStore: checkpointStore)
    }

    public func durableCheckpointDirectoryURL(_ url: URL?) -> ColonyBuilder {
        copy(durableCheckpointDirectoryURL: url)
    }

    package func clock(_ clock: any SwarmClock) -> ColonyBuilder {
        copy(clock: clock)
    }

    package func logger(_ logger: any SwarmLogger) -> ColonyBuilder {
        copy(logger: logger)
    }

    public func configure(_ configure: @Sendable (inout ColonyConfiguration) -> Void) -> ColonyBuilder {
        var updated = configuration
        configure(&updated)
        return copy(configuration: updated)
    }

    package func configureRunOptions(_ configure: @Sendable @escaping (inout ColonyRun.Options) -> Void) -> ColonyBuilder {
        copy(configureRunOptions: { options in
            self.configureRunOptions(&options)
            configure(&options)
        })
    }

    // MARK: - Build Method

    /// Builds and returns a configured `ColonyRuntime`.
    ///
    /// - Returns: A new `ColonyRuntime` configured with the builder's settings.
    /// - Throws: `ColonyBuilderError` if the configuration is invalid (e.g., no model name set).
    public func build() throws -> ColonyRuntime {
        guard !configuration.modelName.isEmpty else {
            throw ColonyBuilderError(message: "Model name must be set before building")
        }
        guard model != nil || modelRouter != nil else {
            throw ColonyBuilderError(message: "Configure a model client or routing policy before building")
        }

        let finalConfiguration = Self.mergedConfiguration(
            profile: profile,
            overrides: configuration
        )

        return try makeRuntime(
            profile: profile,
            threadID: threadID,
            modelName: finalConfiguration.modelName,
            model: model,
            modelRouter: modelRouter,
            inferenceHints: inferenceHints,
            tools: tools,
            filesystem: filesystem,
            shell: shell,
            git: git,
            lsp: lsp,
            applyPatch: applyPatch,
            webSearch: webSearch,
            codeSearch: codeSearch,
            mcp: mcp,
            memory: memory,
            plugins: plugins,
            subagents: subagents,
            checkpointStore: checkpointStore,
            durableCheckpointDirectoryURL: durableCheckpointDirectoryURL,
            clock: clock,
            logger: logger,
            configure: { config in
                config = finalConfiguration
            },
            configureRunOptions: configureRunOptions
        )
    }

    // MARK: - Legacy makeRuntime method

    /// Creates a runtime using the legacy factory method.
    ///
    /// This method provides a more verbose API for backward compatibility.
    /// New code should use `build()` instead.
    ///
    /// - Note: This method is deprecated in favor of the fluent builder pattern.
    package func makeRuntime(
        profile: ColonyProfile = .device,
        threadID: SwarmThreadID,
        modelName: String,
        lane: ColonyLane? = nil,
        intent: String? = nil,
        model: SwarmAnyModelClient? = nil,
        modelRouter: (any SwarmModelRouter)? = nil,
        inferenceHints: SwarmInferenceHints? = nil,
        tools: SwarmAnyToolRegistry? = nil,
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
        subagents: (any ColonySubagentRegistry)? = nil,
        checkpointStore: (any ColonyCheckpointStore)? = nil,
        durableCheckpointDirectoryURL: URL? = nil,
        clock: any SwarmClock = ColonySystemClock(),
        logger: any SwarmLogger = ColonyNoopLogger(),
        configure: @Sendable (inout ColonyConfiguration) -> Void = { _ in },
        configureRunOptions: @Sendable (inout ColonyRun.Options) -> Void = { _ in }
    ) throws -> ColonyRuntime {
        try makeRuntime(
            profile: profile,
            threadID: ColonyThreadID(threadID.rawValue),
            modelName: modelName,
            lane: lane,
            intent: intent,
            model: model,
            modelRouter: modelRouter,
            inferenceHints: inferenceHints,
            tools: tools,
            filesystem: filesystem,
            shell: shell,
            git: git,
            lsp: lsp,
            applyPatch: applyPatch,
            webSearch: webSearch,
            codeSearch: codeSearch,
            mcp: mcp,
            memory: memory,
            plugins: plugins,
            subagents: subagents,
            checkpointStore: checkpointStore,
            durableCheckpointDirectoryURL: durableCheckpointDirectoryURL,
            clock: clock,
            logger: logger,
            configure: configure,
            configureRunOptions: configureRunOptions
        )
    }

    package func makeRuntime(
        profile: ColonyProfile = .device,
        threadID: ColonyThreadID = .generate(),
        modelName: String,
        lane: ColonyLane? = nil,
        intent: String? = nil,
        model: SwarmAnyModelClient? = nil,
        modelRouter: (any SwarmModelRouter)? = nil,
        inferenceHints: SwarmInferenceHints? = nil,
        tools: SwarmAnyToolRegistry? = nil,
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
        subagents: (any ColonySubagentRegistry)? = nil,
        checkpointStore: (any ColonyCheckpointStore)? = nil,
        durableCheckpointDirectoryURL: URL? = nil,
        clock: any SwarmClock = ColonySystemClock(),
        logger: any SwarmLogger = ColonyNoopLogger(),
        configure: @Sendable (inout ColonyConfiguration) -> Void = { _ in },
        configureRunOptions: @Sendable (inout ColonyRun.Options) -> Void = { _ in }
    ) throws -> ColonyRuntime {
        var configuration = Self.configuration(profile: profile, modelName: modelName)

        if let lane {
            Self.applyConfigurationPreset(Self.configurationPreset(for: lane), to: &configuration)
        } else if let intent {
            let routedLane = Self.routeLane(forIntent: intent)
            if routedLane != .generalPurpose {
                Self.applyConfigurationPreset(Self.configurationPreset(for: routedLane), to: &configuration)
            }
        }

        configure(&configuration)

        let resolvedSubagents: (any ColonySubagentRegistry)? = {
            if let subagents { return subagents }
            guard configuration.capabilities.contains(.subagents) else { return nil }
            guard let model else { return nil }
            return ColonyDefaultSubagentRegistry(
                profile: profile,
                modelName: modelName,
                model: model,
                clock: clock,
                logger: logger,
                filesystem: filesystem
            )
        }()

        // Ensure capability gating is consistent with configured backends.
        var capabilities = configuration.capabilities
        if filesystem != nil { capabilities.insert(.filesystem) } else { capabilities.remove(.filesystem) }
        if shell != nil { capabilities.insert(.shell) } else { capabilities.remove(.shell) }
        if shell != nil { capabilities.insert(.shellSessions) } else { capabilities.remove(.shellSessions) }
        if git != nil { capabilities.insert(.git) } else { capabilities.remove(.git) }
        if lsp != nil { capabilities.insert(.lsp) } else { capabilities.remove(.lsp) }
        if applyPatch != nil { capabilities.insert(.applyPatch) } else { capabilities.remove(.applyPatch) }
        if webSearch != nil { capabilities.insert(.webSearch) } else { capabilities.remove(.webSearch) }
        if codeSearch != nil { capabilities.insert(.codeSearch) } else { capabilities.remove(.codeSearch) }
        if memory != nil { capabilities.insert(.memory) } else { capabilities.remove(.memory) }
        if mcp != nil { capabilities.insert(.mcp) } else { capabilities.remove(.mcp) }
        if plugins != nil { capabilities.insert(.plugins) } else { capabilities.remove(.plugins) }
        if resolvedSubagents != nil { capabilities.insert(.subagents) } else { capabilities.remove(.subagents) }
        configuration.capabilities = capabilities

        let context = ColonyContext(
            configuration: configuration,
            filesystem: filesystem,
            shell: shell,
            git: git,
            lsp: lsp,
            applyPatch: applyPatch,
            webSearch: webSearch,
            codeSearch: codeSearch,
            mcp: mcp,
            memory: memory,
            plugins: plugins,
            subagents: resolvedSubagents
        )

        let defaultCheckpointStore: any ColonyCheckpointStore
        if let checkpointStore {
            defaultCheckpointStore = checkpointStore
        } else if let durableCheckpointDirectoryURL {
            defaultCheckpointStore = try ColonyDurableCheckpointStore(baseURL: durableCheckpointDirectoryURL)
        } else {
            defaultCheckpointStore = ColonyInMemoryCheckpointStore()
        }

        let environment = SwarmExecutionEnvironment(
            clock: clock,
            logger: logger,
            model: model,
            modelRouter: modelRouter,
            inferenceHints: inferenceHints,
            tools: tools
        )
        let runtime = ColonyRuntimeEngine(
            threadID: threadID,
            context: context,
            environment: environment,
            checkpointStore: defaultCheckpointStore
        )

        var options = Self.runOptions(profile: profile)
        configureRunOptions(&options)

        let runControl = ColonyRunControl(
            threadID: threadID,
            engine: runtime,
            options: options
        )
        return ColonyRuntime(runControl: runControl)
    }

    // MARK: - Static Helpers

    /// Creates a configuration for the given profile and model name.
    ///
    /// - Parameters:
    ///   - profile: The profile to use.
    ///   - modelName: The model name.
    /// - Returns: A configured `ColonyConfiguration`.
    public static func configuration(
        profile: ColonyProfile,
        modelName: String
    ) -> ColonyConfiguration {
        switch profile {
        case .device:
            var config = ColonyConfiguration(
                capabilities: [.planning, .filesystem, .subagents, .scratchbook],
                modelName: modelName,
                toolApprovalPolicy: .allowList([
                    "ls",
                    "read_file",
                    "glob",
                    "grep",
                    "read_todos",
                    "write_todos",
                    "scratch_read",
                    "scratch_add",
                    "scratch_update",
                    "scratch_complete",
                    "scratch_pin",
                    "scratch_unpin",
                    "workspace_read",
                    "workspace_add",
                    "workspace_update",
                    "workspace_complete",
                    "workspace_pin",
                    "workspace_unpin",
                    "wax_recall",
                    "wax_remember",
                ]),
                compactionPolicy: .maxTokens(2_600),
                summarizationPolicy: ColonySummarizationPolicy(
                    triggerTokens: 3_200,
                    keepLastMessages: 8,
                    historyPathPrefix: .conversationHistoryRoot
                ),
                requestHardTokenLimit: 4_000,
                toolResultEvictionTokenLimit: 700,
                systemPromptMemoryTokenLimit: 256,
                systemPromptSkillsTokenLimit: 256
            )
            config.additionalSystemPrompt = """
            On-device runtime (~4k context window).
            - Keep responses short. Write large outputs to files and reference them.
            - Use the Scratchbook to persist state: track progress, key findings, and next actions.
            - Plan before acting: outline steps with write_todos, then execute one at a time.
            - After completing a step, update the Scratchbook before proceeding.
            - When context is compacted, consult the Scratchbook to recover state.
            - Prefer single focused tool calls over batching unrelated operations.
            """
            config.scratchbookPolicy = ColonyScratchbookPolicy(
                pathPrefix: .scratchbookRoot,
                viewTokenLimit: 700,
                maxRenderedItems: 20,
                autoCompact: true
            )
            config.includeToolListInSystemPrompt = false
            return config

        case .cloud:
            var config = ColonyConfiguration(
                capabilities: [.planning, .filesystem, .subagents],
                modelName: modelName,
                toolApprovalPolicy: .never,
                compactionPolicy: .maxTokens(12_000),
                summarizationPolicy: ColonySummarizationPolicy(
                    triggerTokens: 170_000,
                    keepLastMessages: 20,
                    historyPathPrefix: .conversationHistoryRoot
                ),
                requestHardTokenLimit: nil,
                toolResultEvictionTokenLimit: 20_000,
                systemPromptMemoryTokenLimit: nil,
                systemPromptSkillsTokenLimit: nil
            )
            config.includeToolListInSystemPrompt = true
            return config
        }
    }

    private static func mergedConfiguration(
        profile: ColonyProfile,
        overrides: ColonyConfiguration
    ) -> ColonyConfiguration {
        var configuration = Self.configuration(
            profile: profile,
            modelName: overrides.modelName
        )
        configuration = overrides.mergingOnto(configuration)
        return configuration
    }

    private static func modelRouter(policy: ColonyRoutingPolicy) -> any SwarmModelRouter {
        BuilderRoutingPolicyAdapter(policy: policy)
    }

    public static func configuration(
        profile: ColonyProfile,
        modelName: String,
        lane: ColonyLane
    ) -> ColonyConfiguration {
        var configuration = configuration(profile: profile, modelName: modelName)
        applyConfigurationPreset(configurationPreset(for: lane), to: &configuration)
        return configuration
    }

    public static func routeLane(forIntent intent: String) -> ColonyLane {
        let normalized = intent.lowercased()
        guard normalized.isEmpty == false else { return .generalPurpose }
        let tokenized = Set(
            normalized
                .split { $0.isLetter == false && $0.isNumber == false }
                .map(String.init)
                .filter { $0.isEmpty == false }
        )

        let codingSignals = [
            "code", "swift", "xcode", "bug", "debug", "fix", "refactor",
            "compile", "build", "test", "stack trace", "error", "crash",
        ]
        let researchSignals = [
            "research", "investigate", "analyze", "analysis", "sources", "compare",
            "summarize", "literature", "benchmark", "market",
        ]
        let memorySignals = [
            "remember", "recall", "memory", "stored context", "past note",
            "what did we decide", "previous decision",
        ]

        func containsSignal(_ signal: String) -> Bool {
            if signal.contains(" ") {
                return normalized.contains(signal)
            }
            return tokenized.contains(signal)
        }

        let codingScore = codingSignals.reduce(into: 0) { score, signal in
            if containsSignal(signal) { score += 1 }
        }
        let researchScore = researchSignals.reduce(into: 0) { score, signal in
            if containsSignal(signal) { score += 1 }
        }
        let memoryScore = memorySignals.reduce(into: 0) { score, signal in
            if containsSignal(signal) { score += 1 }
        }

        let ranked: [(ColonyLane, Int)] = [
            (.code, codingScore),
            (.research, researchScore),
            (.knowledge, memoryScore),
        ]

        guard let best = ranked.max(by: { lhs, rhs in lhs.1 < rhs.1 }), best.1 > 0 else {
            return .generalPurpose
        }
        return best.0
    }

    public static func configurationPreset(for lane: ColonyLane) -> ColonyLaneConfigurationPreset {
        switch lane {
        case .generalPurpose:
            return ColonyLaneConfigurationPreset()

        case .code:
            return ColonyLaneConfigurationPreset(
                requiredCapabilities: [.planning, .filesystem, .shell, .shellSessions, .git, .lsp, .applyPatch],
                includeToolListInSystemPrompt: true,
                additionalSystemPrompt: "Coding lane: prioritize deterministic edits, precise diffs, and compile-safe changes."
            )

        case .research:
            return ColonyLaneConfigurationPreset(
                requiredCapabilities: [.planning, .webSearch, .codeSearch, .mcp],
                includeToolListInSystemPrompt: true,
                additionalSystemPrompt: "Research lane: gather evidence, compare alternatives, and surface concise findings."
            )

        case .knowledge:
            return ColonyLaneConfigurationPreset(
                requiredCapabilities: [.planning, .memory],
                includeToolListInSystemPrompt: true,
                additionalSystemPrompt: "Memory lane: use `wax_recall`/`wax_remember` tools to preserve and retrieve durable context."
            )
        }
    }

    public static func applyConfigurationPreset(
        _ preset: ColonyLaneConfigurationPreset,
        to configuration: inout ColonyConfiguration
    ) {
        configuration.capabilities.formUnion(preset.requiredCapabilities)

        if let includeToolListInSystemPrompt = preset.includeToolListInSystemPrompt {
            configuration.includeToolListInSystemPrompt = includeToolListInSystemPrompt
        }

        if let additional = preset.additionalSystemPrompt?.trimmingCharacters(in: .whitespacesAndNewlines),
           additional.isEmpty == false
        {
            if let existing = configuration.additionalSystemPrompt?.trimmingCharacters(in: .whitespacesAndNewlines),
               existing.isEmpty == false
            {
                configuration.additionalSystemPrompt = existing + "\n\n" + additional
            } else {
                configuration.additionalSystemPrompt = additional
            }
        }
    }

    package static func runOptions(profile: ColonyProfile) -> ColonyRun.Options {
        switch profile {
        case .device:
            return ColonyRun.Options(
                maxSteps: 200,
                maxConcurrentTasks: 4,
                checkpointPolicy: .onInterrupt
            )
        case .cloud:
            return ColonyRun.Options(
                maxSteps: 1_000,
                maxConcurrentTasks: 8,
                checkpointPolicy: .onInterrupt
            )
        }
    }
}

private struct BuilderRoutingPolicyAdapter: SwarmModelRouter, Sendable {
    private let policy: ColonyRoutingPolicy

    init(policy: ColonyRoutingPolicy) {
        self.policy = policy
    }

    func route(_ request: SwarmChatRequest, hints: SwarmInferenceHints?) -> SwarmAnyModelClient {
        switch policy.strategy {
        case .onDevice(let onDevice, let fallback, let privacy):
            let router = ColonyOnDeviceModelRouter(
                onDevice: onDevice.map { SwarmAnyModelClient(ColonyModelClientBridge(client: $0)) },
                fallback: SwarmAnyModelClient(ColonyModelClientBridge(client: fallback)),
                policy: .init(
                    privacyBehavior: privacy == .requireOnDevice ? .requireOnDevice : .preferOnDevice
                )
            )
            return router.route(request, hints: hints)
        default:
            return SwarmAnyModelClient(ColonyModelClientBridge(client: ColonyModelRouter(strategy: Self.strategy(from: policy))))
        }
    }

    private static func strategy(from policy: ColonyRoutingPolicy) -> ColonyModelRouter.Strategy {
        switch policy.strategy {
        case .single(let client):
            return .single(client)
        case .prioritized(let routes, let retryPolicy):
            return .prioritized(
                routes.map {
                    .init(
                        providerID: $0.id,
                        client: $0.client,
                        weight: Self.weight(for: $0)
                    )
                },
                .init(
                    maxAttempts: retryPolicy.maxAttempts,
                    initialBackoff: retryPolicy.baseDelay,
                    maxBackoff: retryPolicy.maxDelay
                )
            )
        case .onDevice(let onDevice, let fallback, let privacy):
            return .onDevice(
                onDevice: onDevice,
                fallback: fallback,
                privacy: privacy == .requireOnDevice ? .preferOnDevice : .allowCloudForComplexTasks
            )
        case .costOptimized(let routes, let costPolicy):
            return .costOptimized(
                routes.map {
                    .init(
                        providerID: $0.id,
                        client: $0.client,
                        weight: Self.weight(for: $0)
                    )
                },
                .init(
                    costCeilingUSD: costPolicy.maxCostPerRequest.map { NSDecimalNumber(decimal: $0).doubleValue },
                    preferLowerCost: true
                )
            )
        }
    }

    private static func weight(for route: ProviderRoute) -> Double {
        route.usdPer1KTokens ?? Double(route.priority + 1)
    }
}

private extension ColonyConfiguration {
    func mergingOnto(_ base: ColonyConfiguration, defaults: ColonyConfiguration = ColonyConfiguration(modelName: "")) -> ColonyConfiguration {
        ColonyConfiguration(
            capabilities: capabilities != defaults.capabilities ? capabilities : base.capabilities,
            modelName: modelName.isEmpty == false ? modelName : base.modelName,
            toolApprovalPolicy: toolApprovalPolicy.isMeaningfullyDifferent(from: defaults.toolApprovalPolicy) ? toolApprovalPolicy : base.toolApprovalPolicy,
            toolApprovalRuleStore: toolApprovalRuleStore ?? base.toolApprovalRuleStore,
            toolRiskLevelOverrides: toolRiskLevelOverrides.isEmpty == false ? toolRiskLevelOverrides : base.toolRiskLevelOverrides,
            mandatoryApprovalRiskLevels: mandatoryApprovalRiskLevels != defaults.mandatoryApprovalRiskLevels ? mandatoryApprovalRiskLevels : base.mandatoryApprovalRiskLevels,
            defaultToolRiskLevel: defaultToolRiskLevel != defaults.defaultToolRiskLevel ? defaultToolRiskLevel : base.defaultToolRiskLevel,
            toolAuditRecorder: toolAuditRecorder ?? base.toolAuditRecorder,
            compactionPolicy: compactionPolicy.isMeaningfullyDifferent(from: defaults.compactionPolicy) ? compactionPolicy : base.compactionPolicy,
            scratchbookPolicy: scratchbookPolicy.isMeaningfullyDifferent(from: defaults.scratchbookPolicy) ? scratchbookPolicy : base.scratchbookPolicy,
            includeToolListInSystemPrompt: includeToolListInSystemPrompt != defaults.includeToolListInSystemPrompt ? includeToolListInSystemPrompt : base.includeToolListInSystemPrompt,
            additionalSystemPrompt: additionalSystemPrompt ?? base.additionalSystemPrompt,
            memorySources: memorySources.isEmpty ? base.memorySources : memorySources,
            skillSources: skillSources.isEmpty ? base.skillSources : skillSources,
            summarizationPolicy: summarizationPolicy ?? base.summarizationPolicy,
            requestHardTokenLimit: requestHardTokenLimit ?? base.requestHardTokenLimit,
            toolResultEvictionTokenLimit: toolResultEvictionTokenLimit ?? base.toolResultEvictionTokenLimit,
            systemPromptMemoryTokenLimit: systemPromptMemoryTokenLimit ?? base.systemPromptMemoryTokenLimit,
            systemPromptSkillsTokenLimit: systemPromptSkillsTokenLimit ?? base.systemPromptSkillsTokenLimit
        )
    }
}

private extension ColonyToolApprovalPolicy {
    func isMeaningfullyDifferent(from other: ColonyToolApprovalPolicy) -> Bool {
        switch (self, other) {
        case (.never, .never), (.always, .always):
            return false
        case (.allowList(let lhs), .allowList(let rhs)):
            return lhs != rhs
        default:
            return true
        }
    }
}

private extension ColonyCompactionPolicy {
    func isMeaningfullyDifferent(from other: ColonyCompactionPolicy) -> Bool {
        switch (self, other) {
        case (.disabled, .disabled):
            return false
        case let (.maxMessages(lhs), .maxMessages(rhs)):
            return lhs != rhs
        case let (.maxTokens(lhs), .maxTokens(rhs)):
            return lhs != rhs
        default:
            return true
        }
    }
}

private extension ColonyScratchbookPolicy {
    func isMeaningfullyDifferent(from other: ColonyScratchbookPolicy) -> Bool {
        pathPrefix != other.pathPrefix
            || viewTokenLimit != other.viewTokenLimit
            || maxRenderedItems != other.maxRenderedItems
            || autoCompact != other.autoCompact
    }
}

// MARK: - Deprecation Shims

public typealias ColonyAgentFactory = ColonyBuilder
