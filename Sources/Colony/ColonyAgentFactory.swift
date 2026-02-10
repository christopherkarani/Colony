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
            config.additionalSystemPrompt = "On-device runtime: keep context tight (~4k). Prefer writing large outputs to files and referencing them."
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
        let runtime = HiveRuntime(graph: graph, environment: environment)

        var options = Self.runOptions(profile: profile)
        configureRunOptions(&options)

        return ColonyRuntime(threadID: threadID, runtime: runtime, options: options)
    }
}
