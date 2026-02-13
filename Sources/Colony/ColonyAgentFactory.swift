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
        model: AnyHiveModelClient? = nil,
        modelRouter: (any HiveModelRouter)? = nil,
        inferenceHints: HiveInferenceHints? = nil,
        tools: AnyHiveToolRegistry? = nil,
        filesystem: (any ColonyFileSystemBackend)? = ColonyInMemoryFileSystemBackend(),
        shell: (any ColonyShellBackend)? = nil,
        subagents: (any ColonySubagentRegistry)? = nil,
        checkpointStore: AnyHiveCheckpointStore<ColonySchema>? = nil,
        clock: any HiveClock = ColonySystemClock(),
        logger: any HiveLogger = ColonyNoopLogger(),
        configure: @Sendable (inout ColonyConfiguration) -> Void = { _ in },
        configureRunOptions: @Sendable (inout HiveRunOptions) -> Void = { _ in }
    ) throws -> ColonyRuntime {
        var configuration = Self.configuration(profile: profile, modelName: modelName)
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
        if resolvedSubagents != nil { capabilities.insert(.subagents) } else { capabilities.remove(.subagents) }
        configuration.capabilities = capabilities

        let context = ColonyContext(
            configuration: configuration,
            filesystem: filesystem,
            shell: shell,
            subagents: resolvedSubagents
        )

        let defaultCheckpointStore: AnyHiveCheckpointStore<ColonySchema> = {
            if let checkpointStore { return checkpointStore }
            return AnyHiveCheckpointStore(ColonyInMemoryCheckpointStore<ColonySchema>())
        }()

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

        let runControl = ColonyRunControl(
            threadID: threadID,
            runtime: runtime,
            options: options
        )
        return ColonyRuntime(runControl: runControl)
    }
}
