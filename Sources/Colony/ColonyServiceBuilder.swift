import ColonyCore

/// A single service registration for the Colony runtime.
///
/// Use with `@ColonyServiceBuilder` to declaratively compose services:
/// ```swift
/// let runtime = try await Colony.agent(model: .foundationModels()) {
///     .filesystem(myFS)
///     .memory(waxMemory)
///     if enableGit { .git(gitBackend) }
/// }
/// ```
public enum ColonyService: Sendable {
    /// Filesystem backend for file operations (enables `.filesystem` capability)
    case filesystem(any ColonyFileSystemBackend)

    /// Shell execution backend for running system commands (enables `.shell` capability)
    case shell(any ColonyShellBackend)

    /// Git operations backend for version control tasks (enables `.git` capability)
    case git(any ColonyGitBackend)

    /// Language Server Protocol backend for code intelligence (enables `.lsp` capability)
    case lsp(any ColonyLSPBackend)

    /// Unified diff patch backend for applying code changes (enables `.applyPatch` capability)
    case applyPatch(any ColonyApplyPatchBackend)

    /// Web search backend for internet searches (enables `.webSearch` capability)
    case webSearch(any ColonyWebSearchBackend)

    /// Code search backend for searching across codebases (enables `.codeSearch` capability)
    case codeSearch(any ColonyCodeSearchBackend)

    /// Model Context Protocol backend for AI model integration (enables `.mcp` capability)
    case mcp(any ColonyMCPBackend)

    /// Memory/persistence backend for Wax long-term memory (enables `.memory` capability)
    case memory(any ColonyMemoryBackend)

    /// Plugin tool registry for external plugin integrations (enables `.plugins` capability)
    case plugins(any ColonyPluginToolRegistry)

    /// Subagent registry for managing child agents (enables `.subagents` capability)
    case subagents(any ColonySubagentRegistry)

    /// Custom tool registry for user-defined tools (enables `.tools` capability)
    case tools(any ColonyToolRegistry)
}

/// Result builder for composing Colony service registrations.
@resultBuilder
public struct ColonyServiceBuilder {
    public static func buildBlock(_ components: [ColonyService]...) -> [ColonyService] {
        components.flatMap { $0 }
    }

    public static func buildOptional(_ services: [ColonyService]?) -> [ColonyService] {
        services ?? []
    }

    public static func buildEither(first services: [ColonyService]) -> [ColonyService] {
        services
    }

    public static func buildEither(second services: [ColonyService]) -> [ColonyService] {
        services
    }

    public static func buildArray(_ components: [[ColonyService]]) -> [ColonyService] {
        components.flatMap { $0 }
    }

    public static func buildExpression(_ service: ColonyService) -> [ColonyService] {
        [service]
    }
}

// MARK: - ColonyRuntimeServices + Builder DSL

extension ColonyRuntimeServices {
    /// Creates a `ColonyRuntimeServices` instance using a builder DSL with result builder syntax.
    ///
    /// This initializer allows declarative service registration using trailing closure syntax.
    /// Services are registered by calling builder methods (`.filesystem()`, `.memory()`, etc.)
    /// within the closure. Each service type can only be registered once; subsequent
    /// registrations of the same type will overwrite the previous value.
    ///
    /// Example usage:
    /// ```swift
    /// let services = ColonyRuntimeServices {
    ///     .filesystem(myFS)
    ///     .shell(myShell)
    ///     .memory(waxMemory)
    ///     if featureEnabled { .git(gitBackend) }
    /// }
    /// ```
    ///
    /// - Parameter build: A trailing closure containing service registration expressions
    ///                   built using the `@ColonyServiceBuilder` result builder.
    public init(@ColonyServiceBuilder _ build: @Sendable () -> [ColonyService]) {
        self.init()
        for service in build() {
            switch service {
            case .filesystem(let backend): self.filesystem = backend
            case .shell(let backend): self.shell = backend
            case .git(let backend): self.git = backend
            case .lsp(let backend): self.lsp = backend
            case .applyPatch(let backend): self.applyPatch = backend
            case .webSearch(let backend): self.webSearch = backend
            case .codeSearch(let backend): self.codeSearch = backend
            case .mcp(let backend): self.mcp = backend
            case .memory(let backend): self.memory = backend
            case .plugins(let backend): self.plugins = backend
            case .subagents(let backend): self.subagents = backend
            case .tools(let registry): self.tools = registry
            }
        }
    }
}
