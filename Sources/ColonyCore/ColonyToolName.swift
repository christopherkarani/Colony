/// Namespace for tool-related types including names, definitions, calls, and safety policies.
///
/// Tools are the primary interface through which the agent interacts with the external world.
/// Each tool is identified by a type-safe `ColonyTool.Name` constant and has an associated
/// risk level that determines whether human approval is required before execution.
///
/// ## Tool Name Constants
///
/// Colony provides 39 built-in tool name constants organized by capability:
///
/// | Capability | Tools |
/// |---|---|
/// | Planning | `.writeTodos`, `.readTodos` |
/// | Filesystem | `.ls`, `.readFile`, `.writeFile`, `.editFile`, `.glob`, `.grep` |
/// | Shell | `.execute`, `.shellOpen`, `.shellWrite`, `.shellRead`, `.shellClose` |
/// | Git | `.gitStatus`, `.gitDiff`, `.gitCommit`, `.gitBranch`, `.gitPush`, `.gitPreparePR` |
/// | LSP | `.lspSymbols`, `.lspDiagnostics`, `.lspReferences`, `.lspApplyEdit` |
/// | Memory | `.memoryRecall`, `.memoryRemember` |
/// | Scratchbook | `.scratchRead`, `.scratchAdd`, `.scratchUpdate`, `.scratchComplete`, `.scratchPin`, `.scratchUnpin` |
/// | Web | `.webSearch`, `.codeSearch` |
/// | MCP | `.mcpListResources`, `.mcpReadResource` |
/// | Plugins | `.pluginListTools`, `.pluginInvoke` |
/// | Subagents | `.task` |
///
/// ## Risk Levels
///
/// Each built-in tool has a default risk level:
///
/// - **`.readOnly`** (lowest risk): `.ls`, `.readFile`, `.glob`, `.grep`, `.readTodos`, `.scratchRead`, `.gitStatus`, `.gitDiff`, `.lspSymbols`, `.lspDiagnostics`, `.lspReferences`, `.shellRead`, `.mcpListResources`, `.mcpReadResource`, `.pluginListTools`, `.memoryRecall`
/// - **`.stateMutation`**: `.writeTodos`, `.scratchAdd`, `.scratchUpdate`, `.scratchComplete`, `.scratchPin`, `.scratchUnpin`, `.memoryRemember`
/// - **`.mutation`**: `.writeFile`, `.editFile`, `.gitCommit`, `.gitBranch`, `.lspApplyEdit`, `.applyPatch`
/// - **`.execution`**: `.execute`, `.shellOpen`, `.shellWrite`, `.shellClose`, `.task`
/// - **`.network`** (highest risk): `.gitPush`, `.gitPreparePR`, `.webSearch`, `.codeSearch`, `.pluginInvoke`
public enum ColonyTool {}

// MARK: - ColonyTool.Name

extension ColonyTool {
    /// A type-safe wrapper for tool names that provides autocomplete for built-in tools.
    ///
    /// ```swift
    /// config.safety.toolRiskLevelOverrides[.writeFile] = .mutation
    /// config.safety.toolRiskLevelOverrides["my_custom_tool"] = .network
    /// ```
    public struct Name: Hashable, Codable, Sendable,
                        ExpressibleByStringLiteral,
                        RawRepresentable,
                        CustomStringConvertible {
        public let rawValue: String

        public init(rawValue: String) {
            self.rawValue = rawValue
        }

        public init(stringLiteral value: String) {
            self.init(rawValue: value)
        }

        public var description: String { rawValue }
    }
}

// MARK: - Built-in Tool Names

extension ColonyTool.Name {
    /** List directory contents (read-only). Risk level: .readOnly. Capability: .filesystem. */
    public static let ls: ColonyTool.Name = "ls"
    /** Read file contents (read-only). Risk level: .readOnly. Capability: .filesystem. */
    public static let readFile: ColonyTool.Name = "read_file"
    /** Create or overwrite a file (mutation). Risk level: .mutation. Capability: .filesystem. */
    public static let writeFile: ColonyTool.Name = "write_file"
    /** Edit file contents in-place (mutation). Risk level: .mutation. Capability: .filesystem. */
    public static let editFile: ColonyTool.Name = "edit_file"
    /** Find files by glob pattern (read-only). Risk level: .readOnly. Capability: .filesystem. */
    public static let glob: ColonyTool.Name = "glob"
    /** Search file contents with regex (read-only). Risk level: .readOnly. Capability: .filesystem. */
    public static let grep: ColonyTool.Name = "grep"
    /** Write/update the todo list (state mutation). Risk level: .stateMutation. Capability: .planning. */
    public static let writeTodos: ColonyTool.Name = "write_todos"
    /** Read the current todo list (read-only). Risk level: .readOnly. Capability: .planning. */
    public static let readTodos: ColonyTool.Name = "read_todos"
    /** Execute a shell command (execution). Risk level: .execution. Capability: .shell. */
    public static let execute: ColonyTool.Name = "execute"
    /** Open a URL in the default browser (execution). Risk level: .execution. Capability: .shell. */
    public static let shellOpen: ColonyTool.Name = "shell_open"
    /** Write to an open shell session (execution). Risk level: .execution. Capability: .shellSessions. */
    public static let shellWrite: ColonyTool.Name = "shell_write"
    /** Read from an open shell session (read-only). Risk level: .readOnly. Capability: .shellSessions. */
    public static let shellRead: ColonyTool.Name = "shell_read"
    /** Close an open shell session (execution). Risk level: .execution. Capability: .shellSessions. */
    public static let shellClose: ColonyTool.Name = "shell_close"
    /** Apply a unified diff patch to a file (mutation). Risk level: .mutation. Capability: .applyPatch. */
    public static let applyPatch: ColonyTool.Name = "apply_patch"
    /** Search the web for information (network). Risk level: .network. Capability: .webSearch. */
    public static let webSearch: ColonyTool.Name = "web_search"
    /** Search code across the codebase (network). Risk level: .network. Capability: .codeSearch. */
    public static let codeSearch: ColonyTool.Name = "code_search"
    /** Recall memories from the long-term memory store (read-only). Risk level: .readOnly. Capability: .memory. */
    public static let memoryRecall: ColonyTool.Name = "wax_recall"
    /** Store new information in long-term memory (state mutation). Risk level: .stateMutation. Capability: .memory. */
    public static let memoryRemember: ColonyTool.Name = "wax_remember"
    /** List available MCP resources (read-only). Risk level: .readOnly. Capability: .mcp. */
    public static let mcpListResources: ColonyTool.Name = "mcp_list_resources"
    /** Read a specific MCP resource (read-only). Risk level: .readOnly. Capability: .mcp. */
    public static let mcpReadResource: ColonyTool.Name = "mcp_read_resource"
    /** List tools available via plugins (read-only). Risk level: .readOnly. Capability: .plugins. */
    public static let pluginListTools: ColonyTool.Name = "plugin_list_tools"
    /** Invoke a plugin tool by name (network). Risk level: .network. Capability: .plugins. */
    public static let pluginInvoke: ColonyTool.Name = "plugin_invoke"
    /** Show working tree status (read-only). Risk level: .readOnly. Capability: .git. */
    public static let gitStatus: ColonyTool.Name = "git_status"
    /** Show uncommitted changes (read-only). Risk level: .readOnly. Capability: .git. */
    public static let gitDiff: ColonyTool.Name = "git_diff"
    /** Create a commit with the staged changes (mutation). Risk level: .mutation. Capability: .git. */
    public static let gitCommit: ColonyTool.Name = "git_commit"
    /** List, create, or delete branches (mutation). Risk level: .mutation. Capability: .git. */
    public static let gitBranch: ColonyTool.Name = "git_branch"
    /** Push commits to a remote (network). Risk level: .network. Capability: .git. */
    public static let gitPush: ColonyTool.Name = "git_push"
    /** Prepare a pull request (network). Risk level: .network. Capability: .git. */
    public static let gitPreparePR: ColonyTool.Name = "git_prepare_pr"
    /** List symbols in a source file (read-only). Risk level: .readOnly. Capability: .lsp. */
    public static let lspSymbols: ColonyTool.Name = "lsp_symbols"
    /** Show LSP diagnostics for a file (read-only). Risk level: .readOnly. Capability: .lsp. */
    public static let lspDiagnostics: ColonyTool.Name = "lsp_diagnostics"
    /** Find references to a symbol (read-only). Risk level: .readOnly. Capability: .lsp. */
    public static let lspReferences: ColonyTool.Name = "lsp_references"
    /** Apply a workspace edit via LSP (mutation). Risk level: .mutation. Capability: .lsp. */
    public static let lspApplyEdit: ColonyTool.Name = "lsp_apply_edit"
    /** Read items from the scratchbook (read-only). Risk level: .readOnly. Capability: .scratchbook. */
    public static let scratchRead: ColonyTool.Name = "scratch_read"
    /** Add an item to the scratchbook (state mutation). Risk level: .stateMutation. Capability: .scratchbook. */
    public static let scratchAdd: ColonyTool.Name = "scratch_add"
    /** Update an existing scratchbook item (state mutation). Risk level: .stateMutation. Capability: .scratchbook. */
    public static let scratchUpdate: ColonyTool.Name = "scratch_update"
    /** Mark a scratchbook item as complete (state mutation). Risk level: .stateMutation. Capability: .scratchbook. */
    public static let scratchComplete: ColonyTool.Name = "scratch_complete"
    /** Pin a scratchbook item (state mutation). Risk level: .stateMutation. Capability: .scratchbook. */
    public static let scratchPin: ColonyTool.Name = "scratch_pin"
    /** Unpin a scratchbook item (state mutation). Risk level: .stateMutation. Capability: .scratchbook. */
    public static let scratchUnpin: ColonyTool.Name = "scratch_unpin"
    /** Spawn a subagent to handle a task (execution). Risk level: .execution. Capability: .subagents. */
    public static let task: ColonyTool.Name = "task"
}

