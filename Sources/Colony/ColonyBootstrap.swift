import Foundation
import HiveCore
import HiveCheckpointWax
import ColonyCore
import MembraneCore
import MembraneWax
import Swarm
import struct Swarm.MembraneEnvironment
import struct Swarm.MembraneFeatureConfiguration

package struct ColonyBootstrapResult: Sendable {
    package let runtime: ColonyRuntime
    package let membraneEnvironment: MembraneEnvironment
    package let memoryBackend: any ColonyMemoryBackend

    package init(
        runtime: ColonyRuntime,
        membraneEnvironment: MembraneEnvironment,
        memoryBackend: any ColonyMemoryBackend
    ) {
        self.runtime = runtime
        self.membraneEnvironment = membraneEnvironment
        self.memoryBackend = memoryBackend
    }
}

package struct ColonyBootstrap: Sendable {
    package init() {}

    package func makeMemoryBackend(at url: URL) async throws -> ColonyWaxMemoryBackend {
        try await ColonyWaxMemoryBackend.create(at: url)
    }

    package func makeDefaultModelClient(modelName: String) -> ColonyDefaultConduitModelClient {
        ColonyDefaultConduitModelClient(modelName: modelName)
    }

    package func makeMembraneEnvironment(
        memoryStoreURL: URL,
        configuration: MembraneFeatureConfiguration = .default,
        budget: MembraneCore.ContextBudget = MembraneCore.ContextBudget(
            totalTokens: 4096,
            profile: .foundationModels4K
        )
    ) async throws -> MembraneEnvironment {
        let storage = try await WaxStorageBackend.create(at: memoryStoreURL)
        return MembraneEnvironment.contextCoreSession(
            configuration: configuration,
            budget: budget,
            recallStore: storage,
            pointerStore: storage,
            initialSnapshot: initialMembraneSnapshot(totalTokens: budget.totalTokens)
        )
    }

    package func makeRuntime(
        options: ColonyRuntimeCreationOptions
    ) async throws -> ColonyRuntime {
        let resolvedMemoryURL = defaultMemoryStoreURL(for: options.threadID.hive)
        let resolvedMembraneURL = defaultMembraneStoreURL(for: options.threadID.hive)
        var runtimeOptions = options

        if runtimeOptions.services.memory == nil {
            runtimeOptions.services.memory = try await makeMemoryBackend(at: resolvedMemoryURL)
        }

        if runtimeOptions.services.membrane == nil {
            runtimeOptions.services.membrane = try await makeMembraneEnvironment(memoryStoreURL: resolvedMembraneURL)
        }

        if case .inMemory = runtimeOptions.checkpointing {
            runtimeOptions.checkpointing = .durable(defaultCheckpointStoreURL(for: options.threadID.hive))
        }

        return try ColonyAgentFactory().makeRuntime(runtimeOptions)
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
        durableMemoryStoreURL: URL? = nil,
        plugins: (any ColonyPluginToolRegistry)? = nil,
        subagents: (any ColonySubagentRegistry)? = nil,
        checkpointStore: AnyHiveCheckpointStore<ColonySchema>? = nil,
        durableCheckpointStoreURL: URL? = nil,
        clock: any HiveClock = ColonySystemClock(),
        logger: any HiveLogger = ColonyNoopLogger(),
        configure: @Sendable (inout ColonyConfiguration) -> Void = { _ in },
        configureRunOptions: @Sendable (inout HiveRunOptions) -> Void = { _ in }
    ) async throws -> ColonyRuntime {
        let resolvedModel: (any HiveModelClient)? = if let model {
            model
        } else if modelRouter == nil {
            makeDefaultModelClient(modelName: modelName)
        } else {
            nil
        }
        let resolvedMemoryStoreURL = durableMemoryStoreURL ?? defaultMemoryStoreURL(for: threadID)
        let resolvedCheckpointStoreURL = durableCheckpointStoreURL ?? defaultCheckpointStoreURL(for: threadID)
        let resolvedMembraneStoreURL = defaultMembraneStoreURL(for: threadID)

        let resolvedMemory: any ColonyMemoryBackend = if let memory {
            memory
        } else {
            try await makeMemoryBackend(at: resolvedMemoryStoreURL)
        }

        let resolvedMembraneEnvironment = if let membrane {
            membrane
        } else {
            try await makeMembraneEnvironment(
                memoryStoreURL: resolvedMembraneStoreURL
            )
        }

        let resolvedCheckpointStore: AnyHiveCheckpointStore<ColonySchema> = if let checkpointStore {
            checkpointStore
        } else {
            try await makeCheckpointStore(at: resolvedCheckpointStoreURL)
        }

        return try ColonyAgentFactory().makeRuntime(
            profile: profile,
            threadID: threadID,
            modelName: modelName,
            lane: lane,
            intent: intent,
            model: resolvedModel,
            modelCapabilities: modelCapabilities ?? Self.inferredModelCapabilities(from: resolvedModel),
            modelRouter: modelRouter,
            inferenceHints: inferenceHints,
            tools: tools,
            swarmTools: swarmTools,
            membrane: resolvedMembraneEnvironment,
            filesystem: filesystem,
            shell: shell,
            git: git,
            lsp: lsp,
            applyPatch: applyPatch,
            webSearch: webSearch,
            codeSearch: codeSearch,
            mcp: mcp,
            memory: resolvedMemory,
            plugins: plugins,
            subagents: subagents,
            checkpointStore: resolvedCheckpointStore,
            durableCheckpointDirectoryURL: nil,
            clock: clock,
            logger: logger,
            configure: configure,
            configureRunOptions: configureRunOptions
        )
    }

    package func bootstrap(
        options: ColonyBootstrapOptions
    ) async throws -> ColonyBootstrapResult {
        var runtimeOptions = options.runtime
        let resolvedMemoryStoreURL = options.durableMemoryStoreURL ?? defaultMemoryStoreURL(for: runtimeOptions.threadID.hive)
        let resolvedMembraneStoreURL = options.membraneStoreURL ?? defaultMembraneStoreURL(for: runtimeOptions.threadID.hive)

        let resolvedMemory: any ColonyMemoryBackend = if let memory = runtimeOptions.services.memory {
            memory
        } else {
            try await makeMemoryBackend(at: resolvedMemoryStoreURL)
        }
        let resolvedMembraneEnvironment: MembraneEnvironment = if let membrane = runtimeOptions.services.membrane {
            membrane
        } else {
            try await makeMembraneEnvironment(
                memoryStoreURL: resolvedMembraneStoreURL,
                configuration: options.membraneConfiguration,
                budget: options.membraneBudget
            )
        }
        runtimeOptions.services.memory = resolvedMemory
        runtimeOptions.services.membrane = resolvedMembraneEnvironment

        if case .inMemory = runtimeOptions.checkpointing {
            runtimeOptions.checkpointing = .durable(defaultCheckpointStoreURL(for: runtimeOptions.threadID.hive))
        }

        let runtime = try ColonyAgentFactory().makeRuntime(runtimeOptions)

        return ColonyBootstrapResult(
            runtime: runtime,
            membraneEnvironment: resolvedMembraneEnvironment,
            memoryBackend: resolvedMemory
        )
    }

    package func bootstrap(
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
        swarmTools: (any ColonySwarmToolBridging)? = nil,
        filesystem: (any ColonyFileSystemBackend)? = ColonyInMemoryFileSystemBackend(),
        shell: (any ColonyShellBackend)? = nil,
        git: (any ColonyGitBackend)? = nil,
        lsp: (any ColonyLSPBackend)? = nil,
        applyPatch: (any ColonyApplyPatchBackend)? = nil,
        webSearch: (any ColonyWebSearchBackend)? = nil,
        codeSearch: (any ColonyCodeSearchBackend)? = nil,
        mcp: (any ColonyMCPBackend)? = nil,
        memory: (any ColonyMemoryBackend)? = nil,
        durableMemoryStoreURL: URL? = nil,
        membraneStoreURL: URL? = nil,
        membraneConfiguration: MembraneFeatureConfiguration = .default,
        membraneBudget: MembraneCore.ContextBudget = MembraneCore.ContextBudget(
            totalTokens: 4096,
            profile: .foundationModels4K
        ),
        plugins: (any ColonyPluginToolRegistry)? = nil,
        subagents: (any ColonySubagentRegistry)? = nil,
        checkpointStore: AnyHiveCheckpointStore<ColonySchema>? = nil,
        durableCheckpointStoreURL: URL? = nil,
        clock: any HiveClock = ColonySystemClock(),
        logger: any HiveLogger = ColonyNoopLogger(),
        configure: @Sendable (inout ColonyConfiguration) -> Void = { _ in },
        configureRunOptions: @Sendable (inout HiveRunOptions) -> Void = { _ in }
    ) async throws -> ColonyBootstrapResult {
        let resolvedMemoryStoreURL = durableMemoryStoreURL ?? defaultMemoryStoreURL(for: threadID)
        let resolvedCheckpointStoreURL = durableCheckpointStoreURL ?? defaultCheckpointStoreURL(for: threadID)
        let resolvedMembraneStoreURL = membraneStoreURL ?? defaultMembraneStoreURL(for: threadID)

        let resolvedMemory: any ColonyMemoryBackend = if let memory {
            memory
        } else {
            try await makeMemoryBackend(at: resolvedMemoryStoreURL)
        }

        let resolvedMembraneEnvironment = try await makeMembraneEnvironment(
            memoryStoreURL: resolvedMembraneStoreURL,
            configuration: membraneConfiguration,
            budget: membraneBudget
        )

        let runtime = try await makeRuntime(
            profile: profile,
            threadID: threadID,
            modelName: modelName,
            lane: lane,
            intent: intent,
            model: model,
            modelCapabilities: modelCapabilities,
            modelRouter: modelRouter,
            inferenceHints: inferenceHints,
            tools: tools,
            swarmTools: swarmTools,
            membrane: resolvedMembraneEnvironment,
            filesystem: filesystem,
            shell: shell,
            git: git,
            lsp: lsp,
            applyPatch: applyPatch,
            webSearch: webSearch,
            codeSearch: codeSearch,
            mcp: mcp,
            memory: resolvedMemory,
            durableMemoryStoreURL: nil,
            plugins: plugins,
            subagents: subagents,
            checkpointStore: checkpointStore,
            durableCheckpointStoreURL: resolvedCheckpointStoreURL,
            clock: clock,
            logger: logger,
            configure: configure,
            configureRunOptions: configureRunOptions
        )

        return ColonyBootstrapResult(
            runtime: runtime,
            membraneEnvironment: resolvedMembraneEnvironment,
            memoryBackend: resolvedMemory
        )
    }

    private func makeCheckpointStore(
        at url: URL
    ) async throws -> AnyHiveCheckpointStore<ColonySchema> {
        let storeURL = resolvedCheckpointStoreURL(from: url)
        let store: HiveCheckpointWaxStore<ColonySchema>
        if FileManager.default.fileExists(atPath: storeURL.path) {
            store = try await HiveCheckpointWaxStore.open(at: storeURL)
        } else {
            store = try await HiveCheckpointWaxStore.create(at: storeURL)
        }
        return AnyHiveCheckpointStore(store)
    }

    private func resolvedCheckpointStoreURL(from url: URL) -> URL {
        if url.pathExtension == "wax" {
            return url
        }
        return url.appendingPathComponent("colony-checkpoints.wax", isDirectory: false)
    }

    private func defaultMemoryStoreURL(for threadID: HiveThreadID) -> URL {
        defaultStorageRoot(for: threadID).appendingPathComponent("colony-memory.wax", isDirectory: false)
    }

    private func defaultCheckpointStoreURL(for threadID: HiveThreadID) -> URL {
        defaultStorageRoot(for: threadID).appendingPathComponent("colony-checkpoints.wax", isDirectory: false)
    }

    private func defaultMembraneStoreURL(for threadID: HiveThreadID) -> URL {
        defaultStorageRoot(for: threadID).appendingPathComponent("colony-membrane-context.wax", isDirectory: false)
    }

    private func defaultStorageRoot(for threadID: HiveThreadID) -> URL {
        let baseDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let root = baseDirectory
            .appendingPathComponent("AIStack", isDirectory: true)
            .appendingPathComponent("Colony", isDirectory: true)
            .appendingPathComponent(sanitizedPathComponent(threadID.rawValue), isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func initialMembraneSnapshot(totalTokens: Int) -> MembraneCore.ContextSnapshot {
        MembraneCore.ContextSnapshot(
            budget: .init(totalTokens: totalTokens),
            toolState: .init(
                mode: .allowAll,
                loadedToolNames: [],
                allowListToolNames: [],
                usageCounts: []
            ),
            backendID: "contextcore"
        )
    }

    private func sanitizedPathComponent(_ rawValue: String) -> String {
        let sanitized = rawValue.map { character -> Character in
            if character.isLetter || character.isNumber || character == "-" || character == "_" {
                return character
            }
            return "-"
        }
        let collapsed = String(sanitized).trimmingCharacters(in: CharacterSet(charactersIn: "-_"))
        return collapsed.isEmpty ? "default" : collapsed
    }

    private static func inferredModelCapabilities(from model: (any HiveModelClient)?) -> ColonyModelCapabilities {
        guard let reporting = model as? ColonyCapabilityReportingHiveModelClient else {
            return []
        }
        return reporting.colonyModelCapabilities
    }
}
