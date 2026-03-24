/// A bitmask set representing the capabilities enabled for a Colony agent.
///
/// Use `ColonyCapabilities` to configure which features and tools are available
/// at runtime. Each capability gates a family of related tools - for example,
/// `.filesystem` enables file operations like `ls`, `read_file`, `write_file`, etc.
///
/// Example:
/// ```swift
/// // Enable all capabilities
/// let allCaps = ColonyCapabilities(rawValue: UInt32.max)
///
/// // Enable default capabilities (planning + filesystem)
/// let defaults = ColonyCapabilities.default
///
/// // Check if a capability is enabled
/// if defaults.contains(.planning) { ... }
/// ```
///
/// - Note: Capabilities only control tool availability. A capability being enabled
///   does not guarantee the corresponding backend is wired. For example, `.shell`
///   requires a `ColonyShellBackend` implementation to be injected.
public struct ColonyCapabilities: OptionSet, Sendable {
    public let rawValue: UInt32

    public init(rawValue: UInt32) {
        self.rawValue = rawValue
    }

    /// Enables planning tools (`write_todos`, `read_todos`).
    ///
    /// Built-in capability with no external backend required.
    public static let planning = ColonyCapabilities(rawValue: 1 << 0)

    /// Enables filesystem tools (`ls`, `read_file`, `write_file`, `edit_file`, `glob`, `grep`).
    ///
    /// Requires a `ColonyFileSystemBackend` implementation to be injected.
    public static let filesystem = ColonyCapabilities(rawValue: 1 << 1)

    /// Enables shell execution tools (`execute`).
    ///
    /// Requires a `ColonyShellBackend` implementation to be injected.
    public static let shell = ColonyCapabilities(rawValue: 1 << 2)

    /// Enables subagent delegation tools (`task`).
    ///
    /// Requires a `ColonySubagentRegistry` implementation to be injected.
    public static let subagents = ColonyCapabilities(rawValue: 1 << 3)

    /// Enables scratchpad tools (`scratch_read`, `scratch_add`, `scratch_update`, `scratch_complete`, `scratch_pin`, `scratch_unpin`).
    ///
    /// Built-in capability backed by filesystem storage.
    public static let scratchbook = ColonyCapabilities(rawValue: 1 << 4)

    /// Enables git tools (`git_status`, `git_diff`, `git_commit`, `git_branch`, `git_push`, `git_prepare_pr`).
    ///
    /// Requires a `ColonyGitService` implementation to be injected.
    public static let git = ColonyCapabilities(rawValue: 1 << 5)

    /// Enables Language Server Protocol tools (`lsp_symbols`, `lsp_diagnostics`, `lsp_references`, `lsp_apply_edit`).
    ///
    /// Requires a `ColonyLSPService` implementation to be injected.
    public static let lsp = ColonyCapabilities(rawValue: 1 << 6)

    /// Enables patch application tool (`apply_patch`).
    ///
    /// Built-in capability with no external backend required.
    public static let applyPatch = ColonyCapabilities(rawValue: 1 << 7)

    /// Enables web search tool (`web_search`).
    ///
    /// Requires an appropriate backend to be wired.
    public static let webSearch = ColonyCapabilities(rawValue: 1 << 8)

    /// Enables code search tool (`code_search`).
    ///
    /// Requires an appropriate backend to be wired.
    public static let codeSearch = ColonyCapabilities(rawValue: 1 << 9)

    /// Enables Model Context Protocol tools (`mcp_*`).
    ///
    /// Requires an MCP backend to be configured.
    public static let mcp = ColonyCapabilities(rawValue: 1 << 10)

    /// Enables plugin tools (`plugin_list_tools`, `plugin_invoke`).
    ///
    /// Requires a plugin system to be configured.
    public static let plugins = ColonyCapabilities(rawValue: 1 << 11)

    /// Enables persistent shell session tools (`shell_open`, `shell_read`, `shell_write`, `shell_close`).
    ///
    /// Requires a `ColonyShellBackend` that supports sessions.
    public static let shellSessions = ColonyCapabilities(rawValue: 1 << 12)

    /// Enables memory tools (`memory_recall`, `memory_remember`).
    ///
    /// Requires a `ColonyMemoryService` implementation to be injected.
    public static let memory = ColonyCapabilities(rawValue: 1 << 13)

    /// Default capabilities for a new Colony agent.
    ///
    /// Includes `.planning` and `.filesystem` as these are safe, built-in capabilities.
    public static let `default`: ColonyCapabilities = [.planning, .filesystem]
}
