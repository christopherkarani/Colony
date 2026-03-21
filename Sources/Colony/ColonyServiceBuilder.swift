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
    case filesystem(any ColonyFileSystemBackend)
    case shell(any ColonyShellBackend)
    case git(any ColonyGitBackend)
    case lsp(any ColonyLSPBackend)
    case applyPatch(any ColonyApplyPatchBackend)
    case webSearch(any ColonyWebSearchBackend)
    case codeSearch(any ColonyCodeSearchBackend)
    case mcp(any ColonyMCPBackend)
    case memory(any ColonyMemoryBackend)
    case plugins(any ColonyPluginToolRegistry)
    case subagents(any ColonySubagentRegistry)
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
    /// Create services from a builder DSL.
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
