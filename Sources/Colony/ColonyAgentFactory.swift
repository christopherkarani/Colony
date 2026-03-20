import Dispatch
import Foundation
import HiveCore
import HiveCheckpointWax
import ColonyCore
import struct Swarm.MembraneEnvironment

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

package struct ColonyLaneConfigurationPreset: Sendable {
    package var requiredCapabilities: ColonyCapabilities
    package var toolPromptStrategy: ColonyToolPromptStrategy?
    package var additionalSystemPrompt: String?

    package init(
        requiredCapabilities: ColonyCapabilities = [],
        toolPromptStrategy: ColonyToolPromptStrategy? = nil,
        additionalSystemPrompt: String? = nil
    ) {
        self.requiredCapabilities = requiredCapabilities
        self.toolPromptStrategy = toolPromptStrategy
        self.additionalSystemPrompt = additionalSystemPrompt
    }
}

package struct ColonySystemClock: HiveClock, Sendable {
    package init() {}

    package func nowNanoseconds() -> UInt64 {
        DispatchTime.now().uptimeNanoseconds
    }

    package func sleep(nanoseconds: UInt64) async throws {
        try await Task.sleep(nanoseconds: nanoseconds)
    }
}

package struct ColonyNoopLogger: HiveLogger, Sendable {
    package init() {}
    package func debug(_ message: String, metadata: [String: String]) {}
    package func info(_ message: String, metadata: [String: String]) {}
    package func error(_ message: String, metadata: [String: String]) {}
}

package actor ColonyInMemoryCheckpointStore<Schema: HiveSchema>: HiveCheckpointStore {
    private var checkpoints: [HiveCheckpoint<Schema>] = []

    package init() {}

    package func save(_ checkpoint: HiveCheckpoint<Schema>) async throws {
        checkpoints.append(checkpoint)
    }

    package func loadLatest(threadID: HiveThreadID) async throws -> HiveCheckpoint<Schema>? {
        checkpoints
            .filter { $0.threadID == threadID }
            .max { lhs, rhs in
                if lhs.stepIndex == rhs.stepIndex { return lhs.id.rawValue < rhs.id.rawValue }
                return lhs.stepIndex < rhs.stepIndex
            }
    }
}

package struct ColonyAgentFactory: Sendable {
    package init() {}

    package static func configuration(
        profile: ColonyProfile,
        modelName: String
    ) -> ColonyConfiguration {
        switch profile {
        case .onDevice4k:
            var config = ColonyConfiguration(
                model: .init(
                    name: modelName,
                    capabilities: [.planning, .filesystem, .subagents, .scratchbook]
                ),
                safety: .init(
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
                    ])
                ),
                context: .init(
                    compactionPolicy: .maxTokens(2_600),
                    summarizationPolicy: ColonySummarizationPolicy(
                        triggerTokens: 3_200,
                        keepLastMessages: 8,
                        historyPathPrefix: try! ColonyVirtualPath("/conversation_history")
                    ),
                    requestHardTokenLimit: 4_000,
                    toolResultEvictionTokenLimit: 700
                ),
                prompts: .init(
                    toolPromptStrategy: .automatic,
                    additionalSystemPrompt: """
                    On-device runtime (~4k context window).
                    - Keep responses short. Write large outputs to files and reference them.
                    - Use the Scratchbook to persist state: track progress, key findings, and next actions.
                    - Plan before acting: outline steps with write_todos, then execute one at a time.
                    - After completing a step, update the Scratchbook before proceeding.
                    - When context is compacted, consult the Scratchbook to recover state.
                    - Prefer single focused tool calls over batching unrelated operations.
                    """,
                    systemPromptMemoryTokenLimit: 256,
                    systemPromptSkillsTokenLimit: 256
                )
            )
            config.context.scratchbookPolicy = ColonyScratchbookPolicy(
                pathPrefix: try! ColonyVirtualPath("/scratchbook"),
                viewTokenLimit: 700,
                maxRenderedItems: 20,
                autoCompact: true
            )
            return config

        case .cloud:
            return ColonyConfiguration(
                model: .init(
                    name: modelName,
                    capabilities: [.planning, .filesystem, .subagents]
                ),
                safety: .init(
                    toolApprovalPolicy: .never
                ),
                context: .init(
                    compactionPolicy: .maxTokens(12_000),
                    summarizationPolicy: ColonySummarizationPolicy(
                        triggerTokens: 170_000,
                        keepLastMessages: 20,
                        historyPathPrefix: try! ColonyVirtualPath("/conversation_history")
                    ),
                    toolResultEvictionTokenLimit: 20_000
                ),
                prompts: .init(
                    toolPromptStrategy: .automatic
                )
            )
        }
    }

    package static func configuration(
        profile: ColonyProfile,
        modelName: String,
        lane: ColonyLane
    ) -> ColonyConfiguration {
        var configuration = configuration(profile: profile, modelName: modelName)
        applyConfigurationPreset(configurationPreset(for: lane), to: &configuration)
        return configuration
    }

    package static func routeLane(forIntent intent: String) -> ColonyLane {
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

    package static func configurationPreset(for lane: ColonyLane) -> ColonyLaneConfigurationPreset {
        switch lane {
        case .general:
            return ColonyLaneConfigurationPreset()

        case .coding:
            return ColonyLaneConfigurationPreset(
                requiredCapabilities: [.planning, .filesystem, .shell, .shellSessions, .git, .lsp, .applyPatch],
                additionalSystemPrompt: "Coding lane: prioritize deterministic edits, precise diffs, and compile-safe changes."
            )

        case .research:
            return ColonyLaneConfigurationPreset(
                requiredCapabilities: [.planning, .webSearch, .codeSearch, .mcp],
                additionalSystemPrompt: "Research lane: gather evidence, compare alternatives, and surface concise findings."
            )

        case .memory:
            return ColonyLaneConfigurationPreset(
                requiredCapabilities: [.planning, .memory],
                additionalSystemPrompt: "Memory lane: use `wax_recall`/`wax_remember` tools to preserve and retrieve durable context."
            )
        }
    }

    package static func applyConfigurationPreset(
        _ preset: ColonyLaneConfigurationPreset,
        to configuration: inout ColonyConfiguration
    ) {
        configuration.model.capabilities.formUnion(preset.requiredCapabilities)

        if let toolPromptStrategy = preset.toolPromptStrategy {
            configuration.prompts.toolPromptStrategy = toolPromptStrategy
        }

        if let additional = preset.additionalSystemPrompt?.trimmingCharacters(in: .whitespacesAndNewlines),
           additional.isEmpty == false
        {
            if let existing = configuration.prompts.additionalSystemPrompt?.trimmingCharacters(in: .whitespacesAndNewlines),
               existing.isEmpty == false
            {
                configuration.prompts.additionalSystemPrompt = existing + "\n\n" + additional
            } else {
                configuration.prompts.additionalSystemPrompt = additional
            }
        }
    }

    package static func runOptions(profile: ColonyProfile) -> ColonyRunOptions {
        switch profile {
        case .onDevice4k:
            return ColonyRunOptions(
                maxSteps: 200,
                maxConcurrentTasks: 4,
                checkpointPolicy: .onInterrupt
            )
        case .cloud:
            return ColonyRunOptions(
                maxSteps: 1_000,
                maxConcurrentTasks: 8,
                checkpointPolicy: .onInterrupt
            )
        }
    }

    package func makeRuntime(
        _ options: ColonyRuntimeCreationOptions
    ) throws -> ColonyRuntime {
        let resolvedModel = Self.resolveModel(options.model)
        let checkpointStore: AnyHiveCheckpointStore<ColonySchema>? = switch options.checkpointing {
        case .inMemory:
            nil
        case .durable(let url):
            AnyHiveCheckpointStore(try Self.makeDurableCheckpointStore(at: url))
        }

        return try makeRuntime(
            profile: options.profile,
            threadID: options.threadID.hive,
            modelName: options.modelName,
            lane: options.lane,
            intent: options.intent,
            model: resolvedModel.model,
            modelCapabilities: resolvedModel.capabilities,
            modelRouter: resolvedModel.router,
            inferenceHints: nil,
            tools: options.services.tools.map { AnyHiveToolRegistry(ColonyHiveToolRegistryAdapter(base: $0)) },
            swarmTools: options.services.swarmTools,
            membrane: options.services.membrane,
            filesystem: options.services.filesystem,
            shell: options.services.shell,
            git: options.services.git,
            lsp: options.services.lsp,
            applyPatch: options.services.applyPatch,
            webSearch: options.services.webSearch,
            codeSearch: options.services.codeSearch,
            mcp: options.services.mcp,
            memory: options.services.memory,
            plugins: options.services.plugins,
            subagents: options.services.subagents,
            checkpointStore: checkpointStore,
            durableCheckpointDirectoryURL: nil,
            clock: ColonySystemClock(),
            logger: ColonyNoopLogger(),
            configure: options.configure,
            configureRunOptions: { raw in
                var publicOptions = ColonyRunOptions(raw)
                options.configureRunOptions(&publicOptions)
                raw = publicOptions.hive
            }
        )
    }

    package func makeRuntime(
        profile: ColonyProfile = .onDevice4k,
        threadID: HiveThreadID = HiveThreadID("colony:" + UUID().uuidString),
        modelName: String,
        lane: ColonyLane? = nil,
        intent: String? = nil,
        model: (any HiveModelClient)? = nil,
        modelCapabilities: ColonyModelCapabilities? = nil,
        modelRouter: (any HiveModelRouter)? = nil,
        inferenceHints: HiveInferenceHints? = nil,
        tools: AnyHiveToolRegistry? = nil,
        swarmTools: ColonySwarmToolBridge? = nil,
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
        subagents: (any ColonySubagentRegistry)? = nil,
        checkpointStore: AnyHiveCheckpointStore<ColonySchema>? = nil,
        durableCheckpointDirectoryURL: URL? = nil,
        clock: any HiveClock = ColonySystemClock(),
        logger: any HiveLogger = ColonyNoopLogger(),
        configure: @Sendable (inout ColonyConfiguration) -> Void = { _ in },
        configureRunOptions: @Sendable (inout HiveRunOptions) -> Void = { _ in }
    ) throws -> ColonyRuntime {
        var configuration = Self.configuration(profile: profile, modelName: modelName)
        let resolvedModel = model.map { AnyHiveModelClient(ExistentialHiveModelClient(base: $0)) }
        let resolvedModelCapabilities = modelCapabilities ?? Self.inferredModelCapabilities(from: model)

        if let lane {
            Self.applyConfigurationPreset(Self.configurationPreset(for: lane), to: &configuration)
        } else if let intent {
            let routedLane = Self.routeLane(forIntent: intent)
            if routedLane != .general {
                Self.applyConfigurationPreset(Self.configurationPreset(for: routedLane), to: &configuration)
            }
        }

        if filesystem != nil { configuration.model.capabilities.insert(.filesystem) }
        if shell != nil {
            configuration.model.capabilities.insert(.shell)
            configuration.model.capabilities.insert(.shellSessions)
        }
        if git != nil { configuration.model.capabilities.insert(.git) }
        if lsp != nil { configuration.model.capabilities.insert(.lsp) }
        if applyPatch != nil { configuration.model.capabilities.insert(.applyPatch) }
        if webSearch != nil { configuration.model.capabilities.insert(.webSearch) }
        if codeSearch != nil { configuration.model.capabilities.insert(.codeSearch) }
        if memory != nil { configuration.model.capabilities.insert(.memory) }
        if mcp != nil { configuration.model.capabilities.insert(.mcp) }
        if plugins != nil { configuration.model.capabilities.insert(.plugins) }
        if let swarmTools {
            configuration.model.capabilities.formUnion(swarmTools.requiredCapabilities)
        }

        configure(&configuration)

        // Merge Swarm tool risk-level overrides into the configuration so
        // ColonyToolSafetyPolicyEngine can assess Swarm tools correctly.
        if let swarmTools {
            for (name, level) in swarmTools.riskLevelOverrides {
                // Don't overwrite explicit user-provided overrides.
                if configuration.safety.toolRiskLevelOverrides[name] == nil {
                    configuration.safety.toolRiskLevelOverrides[name] = level
                }
            }
            for (name, metadata) in swarmTools.toolPolicyMetadataByName {
                if configuration.safety.toolPolicyMetadataByName[name] == nil {
                    configuration.safety.toolPolicyMetadataByName[name] = metadata
                }
            }
        }

        let resolvedSubagents: (any ColonySubagentRegistry)? = {
            if let subagents { return subagents }
            guard configuration.model.capabilities.contains(.subagents) else { return nil }
            guard let resolvedModel else { return nil }
            return ColonyDefaultSubagentRegistry(
                profile: profile,
                modelName: modelName,
                model: resolvedModel,
                clock: clock,
                logger: logger,
                filesystem: filesystem
            )
        }()

        // Ensure capability gating is consistent with configured backends.
        let requestedCapabilities = configuration.model.capabilities
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
        configuration.model.capabilities = capabilities

        let context = ColonyContext(
            configuration: configuration,
            modelCapabilities: resolvedModelCapabilities,
            membrane: membrane,
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
                try Self.makeDurableCheckpointStore(at: durableCheckpointDirectoryURL)
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
                    activeCapabilities: configuration.model.capabilities
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
            model: resolvedModel,
            modelRouter: modelRouter,
            inferenceHints: inferenceHints,
            tools: resolvedTools,
            checkpointStore: defaultCheckpointStore
        )

        let graph = try ColonyAgent.compile()
        let runtime = try HiveRuntime(graph: graph, environment: environment)

        var options = Self.runOptions(profile: profile).hive
        configureRunOptions(&options)

        let runControl = ColonyRunControl(
            threadID: threadID,
            runtime: runtime,
            options: options
        )
        return ColonyRuntime(runControl: runControl)
    }

    private static func inferredModelCapabilities(from model: (any HiveModelClient)?) -> ColonyModelCapabilities {
        guard let reporting = model as? ColonyCapabilityReportingHiveModelClient else {
            return []
        }
        return reporting.colonyModelCapabilities
    }

    private static func resolveModel(_ model: ColonyModel) -> ResolvedPublicModel {
        switch model.storage {
        case let .client(client, capabilities):
            return ResolvedPublicModel(
                model: AnyHiveModelClient(ColonyHiveModelClientAdapter(base: client)),
                capabilities: capabilities
            )

        case let .router(router, capabilities):
            return ResolvedPublicModel(
                router: ColonyHiveModelRouterAdapter(base: router),
                capabilities: capabilities ?? []
            )

        case .foundationModels(let configuration):
            let client = ColonyFoundationModelsClient(configuration: configuration)
            return ResolvedPublicModel(
                model: AnyHiveModelClient(ColonyHiveModelClientAdapter(base: client)),
                capabilities: client.colonyModelCapabilities
            )

        case let .onDeviceFallback(fallback, fallbackCapabilities, policy, foundationModels):
            let foundationClient = ColonyFoundationModelsClient(configuration: foundationModels)
            let privacyBehavior: ColonyOnDeviceModelRouter.PrivacyBehavior
            switch policy.privacyBehavior {
            case .preferOnDevice:
                privacyBehavior = .preferOnDevice
            case .requireOnDevice:
                privacyBehavior = .requireOnDevice
            }
            let router = ColonyOnDeviceModelRouter(
                onDevice: AnyHiveModelClient(
                    ColonyHiveModelClientAdapter(base: foundationClient)
                ),
                fallback: AnyHiveModelClient(ColonyHiveModelClientAdapter(base: fallback)),
                onDeviceCapabilities: foundationClient.colonyModelCapabilities,
                fallbackCapabilities: fallbackCapabilities,
                policy: ColonyOnDeviceModelRouter.Policy(
                    privacyBehavior: privacyBehavior,
                    preferOnDeviceWhenOffline: policy.preferOnDeviceWhenOffline,
                    preferOnDeviceWhenMetered: policy.preferOnDeviceWhenMetered
                ),
                isOnDeviceAvailable: { ColonyFoundationModelsClient.isAvailable }
            )

            return ResolvedPublicModel(
                router: router,
                capabilities: router.colonyModelCapabilities(hints: nil)
            )

        case let .providerRouting(providers, policy):
            let gracefulDegradation: ColonyProviderRouter.GracefulDegradationPolicy
            switch policy.gracefulDegradation {
            case .fail:
                gracefulDegradation = .fail
            case .syntheticResponse(let message):
                gracefulDegradation = .syntheticResponse(message)
            }
            let router = ColonyProviderRouter(
                providers: providers.map { provider in
                    ColonyProviderRouter.Provider(
                        id: provider.id.rawValue,
                        client: AnyHiveModelClient(ColonyHiveModelClientAdapter(base: provider.client)),
                        capabilities: provider.capabilities,
                        priority: provider.priority,
                        maxRequestsPerMinute: provider.maxRequestsPerMinute,
                        usdPer1KTokens: provider.usdPer1KTokens
                    )
                },
                policy: ColonyProviderRouter.Policy(
                    maxAttemptsPerProvider: policy.maxAttemptsPerProvider,
                    initialBackoffNanoseconds: policy.initialBackoffNanoseconds,
                    maxBackoffNanoseconds: policy.maxBackoffNanoseconds,
                    globalMaxRequestsPerMinute: policy.globalMaxRequestsPerMinute,
                    costCeilingUSD: policy.costCeilingUSD,
                    estimatedOutputToInputRatio: policy.estimatedOutputToInputRatio,
                    gracefulDegradation: gracefulDegradation
                )
            )

            return ResolvedPublicModel(
                router: router,
                capabilities: router.colonyModelCapabilities(hints: nil)
            )
        }
    }

    private static func makeDurableCheckpointStore(
        at url: URL
    ) throws -> HiveCheckpointWaxStore<ColonySchema> {
        try blocking {
            try await makeDurableCheckpointStoreAsync(at: url)
        }
    }

    private static func makeDurableCheckpointStoreAsync(
        at url: URL
    ) async throws -> HiveCheckpointWaxStore<ColonySchema> {
        let storeURL = resolvedCheckpointStoreURL(from: url)
        if FileManager.default.fileExists(atPath: storeURL.path) {
            return try await HiveCheckpointWaxStore.open(at: storeURL)
        }
        return try await HiveCheckpointWaxStore.create(at: storeURL)
    }

    private static func resolvedCheckpointStoreURL(from url: URL) -> URL {
        if url.pathExtension == "wax" {
            return url
        }
        return url.appendingPathComponent("colony-checkpoints.wax", isDirectory: false)
    }

    private static func blocking<T: Sendable>(
        _ operation: @escaping @Sendable () async throws -> T
    ) throws -> T {
        let semaphore = DispatchSemaphore(value: 0)
        let box = BlockingResultBox<T>()

        Task {
            do {
                box.write(Result<T, Error>.success(try await operation()))
            } catch {
                box.write(Result<T, Error>.failure(error))
            }
            semaphore.signal()
        }

        semaphore.wait()
        guard let result = box.read() else {
            throw ColonyBlockingMissingResult()
        }
        return try result.get()
    }
}

private final class BlockingResultBox<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var result: Result<Value, Error>?

    func write(_ value: Result<Value, Error>) {
        lock.lock()
        result = value
        lock.unlock()
    }

    func read() -> Result<Value, Error>? {
        lock.lock()
        defer { lock.unlock() }
        return result
    }
}

private struct ColonyBlockingMissingResult: Error {}

private struct ResolvedPublicModel: Sendable {
    var model: AnyHiveModelClient?
    var router: (any HiveModelRouter)?
    var capabilities: ColonyModelCapabilities

    init(
        model: AnyHiveModelClient? = nil,
        router: (any HiveModelRouter)? = nil,
        capabilities: ColonyModelCapabilities = []
    ) {
        self.model = model
        self.router = router
        self.capabilities = capabilities
    }
}

private struct ExistentialHiveModelClient: HiveModelClient, Sendable {
    let base: any HiveModelClient

    func complete(_ request: HiveChatRequest) async throws -> HiveChatResponse {
        try await base.complete(request)
    }

    func stream(_ request: HiveChatRequest) -> AsyncThrowingStream<HiveChatStreamChunk, Error> {
        base.stream(request)
    }
}

/// Filters Swarm tools by active Colony capabilities.
struct CapabilityFilteredSwarmToolRegistry: HiveToolRegistry, Sendable {
    let base: ColonySwarmToolBridge
    let activeCapabilities: ColonyCapabilities

    func listTools() -> [HiveToolDefinition] {
        base.listHiveTools(filteredBy: activeCapabilities)
    }

    func invoke(_ call: HiveToolCall) async throws -> HiveToolResult {
        try await base.invokeHive(call)
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
