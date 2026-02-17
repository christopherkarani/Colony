import Foundation
import HiveCore
import ColonyCore

/// Groups all optional backend protocols for ``ColonyAgentFactory/makeRuntime(profile:threadID:modelName:lane:intent:model:modelRouter:inferenceHints:backends:options:)``.
///
/// Most callers only provide a small subset of backends. Bundling them reduces
/// parameter noise at call sites while keeping each backend independently optional.
public struct ColonyBackendBundle: Sendable {
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
    public var tools: AnyHiveToolRegistry?
    public var checkpointStore: AnyHiveCheckpointStore<ColonySchema>?
    public var durableCheckpointDirectoryURL: URL?

    public init(
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
        tools: AnyHiveToolRegistry? = nil,
        checkpointStore: AnyHiveCheckpointStore<ColonySchema>? = nil,
        durableCheckpointDirectoryURL: URL? = nil
    ) {
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
        self.tools = tools
        self.checkpointStore = checkpointStore
        self.durableCheckpointDirectoryURL = durableCheckpointDirectoryURL
    }
}

/// Groups runtime configuration knobs for ``ColonyAgentFactory/makeRuntime(profile:threadID:modelName:lane:intent:model:modelRouter:inferenceHints:backends:options:)``.
///
/// Contains the "how to run" parameters that most callers never customize.
public struct ColonyRuntimeOptions: Sendable {
    public var clock: any HiveClock
    public var logger: any HiveLogger
    public var configure: @Sendable (inout ColonyConfiguration) -> Void
    public var configureRunOptions: @Sendable (inout HiveRunOptions) -> Void

    public init(
        clock: any HiveClock = ColonySystemClock(),
        logger: any HiveLogger = ColonyNoopLogger(),
        configure: @Sendable @escaping (inout ColonyConfiguration) -> Void = { _ in },
        configureRunOptions: @Sendable @escaping (inout HiveRunOptions) -> Void = { _ in }
    ) {
        self.clock = clock
        self.logger = logger
        self.configure = configure
        self.configureRunOptions = configureRunOptions
    }
}
