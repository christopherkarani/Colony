// MARK: - ColonyTool Namespace

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
    public static let ls: ColonyTool.Name = "ls"
    public static let readFile: ColonyTool.Name = "read_file"
    public static let writeFile: ColonyTool.Name = "write_file"
    public static let editFile: ColonyTool.Name = "edit_file"
    public static let glob: ColonyTool.Name = "glob"
    public static let grep: ColonyTool.Name = "grep"
    public static let writeTodos: ColonyTool.Name = "write_todos"
    public static let readTodos: ColonyTool.Name = "read_todos"
    public static let execute: ColonyTool.Name = "execute"
    public static let shellOpen: ColonyTool.Name = "shell_open"
    public static let shellWrite: ColonyTool.Name = "shell_write"
    public static let shellRead: ColonyTool.Name = "shell_read"
    public static let shellClose: ColonyTool.Name = "shell_close"
    public static let applyPatch: ColonyTool.Name = "apply_patch"
    public static let webSearch: ColonyTool.Name = "web_search"
    public static let codeSearch: ColonyTool.Name = "code_search"
    public static let memoryRecall: ColonyTool.Name = "wax_recall"
    public static let memoryRemember: ColonyTool.Name = "wax_remember"
    public static let mcpListResources: ColonyTool.Name = "mcp_list_resources"
    public static let mcpReadResource: ColonyTool.Name = "mcp_read_resource"
    public static let pluginListTools: ColonyTool.Name = "plugin_list_tools"
    public static let pluginInvoke: ColonyTool.Name = "plugin_invoke"
    public static let gitStatus: ColonyTool.Name = "git_status"
    public static let gitDiff: ColonyTool.Name = "git_diff"
    public static let gitCommit: ColonyTool.Name = "git_commit"
    public static let gitBranch: ColonyTool.Name = "git_branch"
    public static let gitPush: ColonyTool.Name = "git_push"
    public static let gitPreparePR: ColonyTool.Name = "git_prepare_pr"
    public static let lspSymbols: ColonyTool.Name = "lsp_symbols"
    public static let lspDiagnostics: ColonyTool.Name = "lsp_diagnostics"
    public static let lspReferences: ColonyTool.Name = "lsp_references"
    public static let lspApplyEdit: ColonyTool.Name = "lsp_apply_edit"
    public static let scratchRead: ColonyTool.Name = "scratch_read"
    public static let scratchAdd: ColonyTool.Name = "scratch_add"
    public static let scratchUpdate: ColonyTool.Name = "scratch_update"
    public static let scratchComplete: ColonyTool.Name = "scratch_complete"
    public static let scratchPin: ColonyTool.Name = "scratch_pin"
    public static let scratchUnpin: ColonyTool.Name = "scratch_unpin"
    public static let task: ColonyTool.Name = "task"
}

