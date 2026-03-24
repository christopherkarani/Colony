import Dispatch
import Foundation
import HiveCore
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
    @available(*, deprecated, renamed: "device")
    public static let onDevice4k: Self = .device
}

/// Deprecated type alias for backward compatibility. Use `AgentMode` instead.
@available(*, deprecated, renamed: "AgentMode")
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
public struct ColonySystemClock: HiveClock, Sendable {
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
public struct ColonyNoopLogger: HiveLogger, Sendable {
    public init() {}
    public func debug(_ message: String, metadata: [String: String]) {}
    public func info(_ message: String, metadata: [String: String]) {}
    public func error(_ message: String, metadata: [String: String]) {}
}

/// An in-memory checkpoint store for development and testing.
///
/// This store keeps all checkpoints in memory and does not persist
/// them across application restarts. Use `ColonyDurableCheckpointStore`
/// for production persistence.
public actor ColonyInMemoryCheckpointStore<Schema: HiveSchema>: HiveCheckpointStore {
    private var checkpoints: [HiveCheckpoint<Schema>] = []

    public init() {}

    public func save(_ checkpoint: HiveCheckpoint<Schema>) async throws {
        checkpoints.append(checkpoint)
    }

    public func loadLatest(threadID: HiveThreadID) async throws -> HiveCheckpoint<Schema>? {
        checkpoints
            .filter { $0.threadID == threadID }
            .max { lhs, rhs in
                if lhs.stepIndex == rhs.stepIndex { return lhs.id.rawValue < rhs.id.rawValue }
                return lhs.stepIndex < rhs.stepIndex
            }
    }
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
    private var threadID: HiveThreadID
    private var model: AnyHiveModelClient?
    private var modelRouter: (any HiveModelRouter)?
    private var inferenceHints: HiveInferenceHints?
    private var tools: AnyHiveToolRegistry?
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
    private var checkpointStore: AnyHiveCheckpointStore<ColonySchema>?
    private var durableCheckpointDirectoryURL: URL?
    private var clock: any HiveClock
    private var logger: any HiveLogger
    private var configureRunOptions: @Sendable (inout HiveRunOptions) -> Void

    public init() {
        self.configuration = ColonyConfiguration(modelName: "")
        self.profile = .device
        self.threadID = HiveThreadID("colony:" + UUID().uuidString)
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

    private init(
        configuration: ColonyConfiguration,
        profile: ColonyProfile,
        threadID: HiveThreadID,
        model: AnyHiveModelClient?,
        modelRouter: (any HiveModelRouter)?,
        inferenceHints: HiveInferenceHints?,
        tools: AnyHiveToolRegistry?,
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
        checkpointStore: AnyHiveCheckpointStore<ColonySchema>?,
        durableCheckpointDirectoryURL: URL?,
        clock: any HiveClock,
        logger: any HiveLogger,
        configureRunOptions: @Sendable @escaping (inout HiveRunOptions) -> Void
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
        return ColonyBuilder(
            configuration: newConfig,
            profile: profile,
            threadID: threadID,
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
            configureRunOptions: configureRunOptions
        )
    }

    /// Sets the profile for this runtime.
    ///
    /// - Parameter profile: The profile to use (`.device` or `.cloud`).
    /// - Returns: A new builder with the profile set.
    public func profile(_ profile: ColonyProfile) -> ColonyBuilder {
        ColonyBuilder(
            configuration: configuration,
            profile: profile,
            threadID: threadID,
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
            configureRunOptions: configureRunOptions
        )
    }

    /// Sets the capabilities for this runtime.
    ///
    /// - Parameter capabilities: The capabilities to enable.
    /// - Returns: A new builder with the capabilities set.
    public func capabilities(_ capabilities: ColonyCapabilities) -> ColonyBuilder {
        var newConfig = configuration
        newConfig.capabilities = capabilities
        return ColonyBuilder(
            configuration: newConfig,
            profile: profile,
            threadID: threadID,
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
            configureRunOptions: configureRunOptions
        )
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

        var config = Self.configuration(profile: profile, modelName: configuration.modelName)

        // Apply any custom configuration overrides
        config.capabilities = configuration.capabilities

        let resolvedSubagents: (any ColonySubagentRegistry)? = {
            if let subagents { return subagents }
            guard config.capabilities.contains(.subagents) else { return nil }
            guard let model else { return nil }
            return ColonyDefaultSubagentRegistry(
                profile: profile,
                modelName: configuration.modelName,
                model: model,
                clock: clock,
                logger: logger,
                filesystem: filesystem
            )
        }()

        // Ensure capability gating is consistent with configured backends.
        var capabilities = config.capabilities
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
        config.capabilities = capabilities

        let context = ColonyContext(
            configuration: config,
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

        let defaultCheckpointStore: AnyHiveCheckpointStore<ColonySchema>
        if let checkpointStore {
            defaultCheckpointStore = checkpointStore
        } else if let durableCheckpointDirectoryURL {
            defaultCheckpointStore = AnyHiveCheckpointStore(
                try ColonyDurableCheckpointStore<ColonySchema>(baseURL: durableCheckpointDirectoryURL)
            )
        } else {
            defaultCheckpointStore = AnyHiveCheckpointStore(ColonyInMemoryCheckpointStore<ColonySchema>())
        }

        let environment = HiveEnvironment<ColonySchema>(
            context: context,
            clock: clock,
            logger: logger,
            model: model,
            modelRouter: modelRouter,
            inferenceHints: inferenceHints,
            tools: tools,
            checkpointStore: defaultCheckpointStore
        )

        let graph = try ColonyAgent.compile()
        let runtime = try HiveRuntime(graph: graph, environment: environment)

        var options = Self.runOptions(profile: profile)
        configureRunOptions(&options)

        let runControl = ColonyRunControl(
            threadID: threadID,
            runtime: runtime,
            options: options
        )
        return ColonyRuntime(runControl: runControl)
    }

    // MARK: - Legacy makeRuntime method

    /// Creates a runtime using the legacy factory method.
    ///
    /// This method provides a more verbose API for backward compatibility.
    /// New code should use `build()` instead.
    ///
    /// - Note: This method is deprecated in favor of the fluent builder pattern.
    public func makeRuntime(
        profile: ColonyProfile = .device,
        threadID: HiveThreadID = HiveThreadID("colony:" + UUID().uuidString),
        modelName: String,
        lane: ColonyLane? = nil,
        intent: String? = nil,
        model: AnyHiveModelClient? = nil,
        modelRouter: (any HiveModelRouter)? = nil,
        inferenceHints: HiveInferenceHints? = nil,
        tools: AnyHiveToolRegistry? = nil,
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
        checkpointStore: AnyHiveCheckpointStore<ColonySchema>? = nil,
        durableCheckpointDirectoryURL: URL? = nil,
        clock: any HiveClock = ColonySystemClock(),
        logger: any HiveLogger = ColonyNoopLogger(),
        configure: @Sendable (inout ColonyConfiguration) -> Void = { _ in },
        configureRunOptions: @Sendable (inout HiveRunOptions) -> Void = { _ in }
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

        let defaultCheckpointStore: AnyHiveCheckpointStore<ColonySchema>
        if let checkpointStore {
            defaultCheckpointStore = checkpointStore
        } else if let durableCheckpointDirectoryURL {
            defaultCheckpointStore = AnyHiveCheckpointStore(
                try ColonyDurableCheckpointStore<ColonySchema>(baseURL: durableCheckpointDirectoryURL)
            )
        } else {
            defaultCheckpointStore = AnyHiveCheckpointStore(ColonyInMemoryCheckpointStore<ColonySchema>())
        }

        let environment = HiveEnvironment<ColonySchema>(
            context: context,
            clock: clock,
            logger: logger,
            model: model,
            modelRouter: modelRouter,
            inferenceHints: inferenceHints,
            tools: tools,
            checkpointStore: defaultCheckpointStore
        )

        let graph = try ColonyAgent.compile()
        let runtime = try HiveRuntime(graph: graph, environment: environment)

        var options = Self.runOptions(profile: profile)
        configureRunOptions(&options)

        let runControl = ColonyRunControl(
            threadID: threadID,
            runtime: runtime,
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

    public static func runOptions(profile: ColonyProfile) -> HiveRunOptions {
        switch profile {
        case .device:
            return HiveRunOptions(
                maxSteps: 200,
                maxConcurrentTasks: 4,
                checkpointPolicy: .onInterrupt
            )
        case .cloud:
            return HiveRunOptions(
                maxSteps: 1_000,
                maxConcurrentTasks: 8,
                checkpointPolicy: .onInterrupt
            )
        }
    }
}

// MARK: - Deprecation Shims

@available(*, deprecated, renamed: "ColonyBuilder")
public typealias ColonyAgentFactory = ColonyBuilder
