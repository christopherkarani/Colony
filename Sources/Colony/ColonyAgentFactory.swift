import Dispatch
import Foundation
import HiveCore
import ColonyCore

public enum ColonyProfile: Sendable {
    /// Optimize for a ~4k token context window (on-device).
    case onDevice4k
    /// Optimize for larger context windows and cloud runtimes.
    case cloud
}

public enum ColonyLane: String, Sendable, CaseIterable {
    case general
    case coding
    case research
    case memory
}

public struct ColonyLaneConfigurationPreset: Sendable {
    public var requiredCapabilities: ColonyCapabilities
    public var includeToolListInSystemPrompt: Bool?
    public var additionalSystemPrompt: String?

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

public struct ColonySystemClock: HiveClock, Sendable {
    public init() {}

    public func nowNanoseconds() -> UInt64 {
        DispatchTime.now().uptimeNanoseconds
    }

    public func sleep(nanoseconds: UInt64) async throws {
        try await Task.sleep(nanoseconds: nanoseconds)
    }
}

public struct ColonyNoopLogger: HiveLogger, Sendable {
    public init() {}
    public func debug(_ message: String, metadata: [String: String]) {}
    public func info(_ message: String, metadata: [String: String]) {}
    public func error(_ message: String, metadata: [String: String]) {}
}

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

public struct ColonyAgentFactory: Sendable {
    public init() {}

    public static func configuration(
        profile: ColonyProfile,
        modelName: String
    ) -> ColonyConfiguration {
        switch profile {
        case .onDevice4k:
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
                    "wax_recall",
                    "wax_remember",
                ]),
                compactionPolicy: .maxTokens(2_600),
                summarizationPolicy: ColonySummarizationPolicy(
                    triggerTokens: 3_200,
                    keepLastMessages: 8,
                    historyPathPrefix: try! ColonyVirtualPath("/conversation_history")
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
                pathPrefix: try! ColonyVirtualPath("/scratchbook"),
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
                    historyPathPrefix: try! ColonyVirtualPath("/conversation_history")
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
        guard normalized.isEmpty == false else { return .general }
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
            (.coding, codingScore),
            (.research, researchScore),
            (.memory, memoryScore),
        ]

        guard let best = ranked.max(by: { lhs, rhs in lhs.1 < rhs.1 }), best.1 > 0 else {
            return .general
        }
        return best.0
    }

    public static func configurationPreset(for lane: ColonyLane) -> ColonyLaneConfigurationPreset {
        switch lane {
        case .general:
            return ColonyLaneConfigurationPreset()

        case .coding:
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

        case .memory:
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
        case .onDevice4k:
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

    public func makeRuntime(
        profile: ColonyProfile = .onDevice4k,
        threadID: HiveThreadID = HiveThreadID("colony:" + UUID().uuidString),
        modelName: String,
        lane: ColonyLane? = nil,
        intent: String? = nil,
        model: AnyHiveModelClient? = nil,
        modelRouter: (any HiveModelRouter)? = nil,
        inferenceHints: HiveInferenceHints? = nil,
        tools: AnyHiveToolRegistry? = nil,
        swarmTools: SwarmToolBridge? = nil,
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
            if routedLane != .general {
                Self.applyConfigurationPreset(Self.configurationPreset(for: routedLane), to: &configuration)
            }
        }

        if filesystem != nil { configuration.capabilities.insert(.filesystem) }
        if shell != nil {
            configuration.capabilities.insert(.shell)
            configuration.capabilities.insert(.shellSessions)
        }
        if git != nil { configuration.capabilities.insert(.git) }
        if lsp != nil { configuration.capabilities.insert(.lsp) }
        if applyPatch != nil { configuration.capabilities.insert(.applyPatch) }
        if webSearch != nil { configuration.capabilities.insert(.webSearch) }
        if codeSearch != nil { configuration.capabilities.insert(.codeSearch) }
        if memory != nil { configuration.capabilities.insert(.memory) }
        if mcp != nil { configuration.capabilities.insert(.mcp) }
        if plugins != nil { configuration.capabilities.insert(.plugins) }
        if let swarmTools {
            configuration.capabilities.formUnion(swarmTools.requiredCapabilities)
        }

        configure(&configuration)

        // Merge Swarm tool risk-level overrides into the configuration so
        // ColonyToolSafetyPolicyEngine can assess Swarm tools correctly.
        if let swarmTools {
            for (name, level) in swarmTools.riskLevelOverrides {
                // Don't overwrite explicit user-provided overrides.
                if configuration.toolRiskLevelOverrides[name] == nil {
                    configuration.toolRiskLevelOverrides[name] = level
                }
            }
        }

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
        let requestedCapabilities = configuration.capabilities
        let swarmCapabilities = swarmTools?.requiredCapabilities ?? []
        var capabilities: ColonyCapabilities = []

        func retainIfRequested(_ capability: ColonyCapabilities, available: Bool) {
            guard requestedCapabilities.contains(capability), available else { return }
            capabilities.insert(capability)
        }

        retainIfRequested(.planning, available: true)
        retainIfRequested(.scratchbook, available: true)
        retainIfRequested(.filesystem, available: filesystem != nil || swarmCapabilities.contains(.filesystem))
        retainIfRequested(.shell, available: shell != nil || swarmCapabilities.contains(.shell))
        retainIfRequested(.shellSessions, available: shell != nil || swarmCapabilities.contains(.shellSessions))
        retainIfRequested(.git, available: git != nil || swarmCapabilities.contains(.git))
        retainIfRequested(.lsp, available: lsp != nil || swarmCapabilities.contains(.lsp))
        retainIfRequested(.applyPatch, available: applyPatch != nil || swarmCapabilities.contains(.applyPatch))
        retainIfRequested(.webSearch, available: webSearch != nil || swarmCapabilities.contains(.webSearch))
        retainIfRequested(.codeSearch, available: codeSearch != nil || swarmCapabilities.contains(.codeSearch))
        retainIfRequested(.mcp, available: mcp != nil || swarmCapabilities.contains(.mcp))
        retainIfRequested(.plugins, available: plugins != nil || swarmCapabilities.contains(.plugins))
        retainIfRequested(.memory, available: memory != nil || swarmCapabilities.contains(.memory))
        retainIfRequested(.subagents, available: resolvedSubagents != nil)
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

        // Compose Swarm tools with any externally-provided tool registry.
        // Swarm tools are filtered by active capabilities before they are exposed
        // to the runtime model request path.
        let capabilityFilteredSwarmTools: AnyHiveToolRegistry? = {
            guard let swarmTools else { return nil }
            return AnyHiveToolRegistry(
                CapabilityFilteredSwarmToolRegistry(
                    base: swarmTools,
                    activeCapabilities: configuration.capabilities
                )
            )
        }()

        // Compose capability-filtered Swarm tools with any externally-provided tool registry.
        let resolvedTools: AnyHiveToolRegistry? = {
            switch (tools, capabilityFilteredSwarmTools) {
            case let (existing?, bridge?):
                return AnyHiveToolRegistry(CompositeToolRegistry(primary: existing, secondary: bridge))
            case let (nil, bridge?):
                return bridge
            case let (existing?, nil):
                return existing
            case (nil, nil):
                return nil
            }
        }()

        let environment = HiveEnvironment<ColonySchema>(
            context: context,
            clock: clock,
            logger: logger,
            model: model,
            modelRouter: modelRouter,
            inferenceHints: inferenceHints,
            tools: resolvedTools,
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
}

/// Filters Swarm tools by active Colony capabilities.
struct CapabilityFilteredSwarmToolRegistry: HiveToolRegistry, Sendable {
    let base: SwarmToolBridge
    let activeCapabilities: ColonyCapabilities

    func listTools() -> [HiveToolDefinition] {
        base.listTools(filteredBy: activeCapabilities)
    }

    func invoke(_ call: HiveToolCall) async throws -> HiveToolResult {
        try await base.invoke(call)
    }
}

/// Merges two `HiveToolRegistry` implementations.
/// Primary tools take precedence when names collide (deduplication happens in ColonyAgent).
struct CompositeToolRegistry: HiveToolRegistry, Sendable {
    let primary: AnyHiveToolRegistry
    let secondary: AnyHiveToolRegistry

    func listTools() -> [HiveToolDefinition] {
        // Colony deduplication keeps the last definition by name.
        // Listing secondary first preserves primary precedence under collisions.
        secondary.listTools() + primary.listTools()
    }

    func invoke(_ call: HiveToolCall) async throws -> HiveToolResult {
        let primaryNames = Set(primary.listTools().map(\.name))
        if primaryNames.contains(call.name) {
            return try await primary.invoke(call)
        }
        return try await secondary.invoke(call)
    }
}
