import HiveCore

public enum ColonyBuiltInToolDefinitions {
    public static let taskName = "task"

    public static let ls = HiveToolDefinition(
        name: "ls",
        description: "List files in a directory (non-recursive).",
        parametersJSONSchema: """
        {"type":"object","properties":{"path":{"type":"string","description":"Directory path. Defaults to '/'."}}}
        """
    )

    public static let readFile = HiveToolDefinition(
        name: "read_file",
        description: "Read a file with line numbers. Use offset/limit for pagination.",
        parametersJSONSchema: """
        {"type":"object","properties":{"path":{"type":"string","description":"File path."},"offset":{"type":"integer","description":"0-indexed line offset (default 0)."},"limit":{"type":"integer","description":"Max lines to read (default 100)."}},"required":["path"]}
        """
    )

    public static let writeFile = HiveToolDefinition(
        name: "write_file",
        description: "Create a new file. Fails if the file already exists.",
        parametersJSONSchema: """
        {"type":"object","properties":{"path":{"type":"string","description":"File path."},"content":{"type":"string","description":"Full file contents."}},"required":["path","content"]}
        """
    )

    public static let editFile = HiveToolDefinition(
        name: "edit_file",
        description: "Replace an exact string in a file.",
        parametersJSONSchema: """
        {"type":"object","properties":{"path":{"type":"string","description":"File path."},"old_string":{"type":"string","description":"Exact text to replace."},"new_string":{"type":"string","description":"Replacement text."},"replace_all":{"type":"boolean","description":"Replace all occurrences (default false)."}},"required":["path","old_string","new_string"]}
        """
    )

    public static let glob = HiveToolDefinition(
        name: "glob",
        description: "Find files matching a glob pattern.",
        parametersJSONSchema: """
        {"type":"object","properties":{"pattern":{"type":"string","description":"Glob pattern like '**/*.swift' or '*.md'."}},"required":["pattern"]}
        """
    )

    public static let grep = HiveToolDefinition(
        name: "grep",
        description: "Search for a literal string across files. Optionally filter files with glob.",
        parametersJSONSchema: """
        {"type":"object","properties":{"pattern":{"type":"string","description":"Literal substring to search for (not regex)."},"glob":{"type":"string","description":"Optional file glob filter."}},"required":["pattern"]}
        """
    )

    public static let writeTodos = HiveToolDefinition(
        name: "write_todos",
        description: "Replace the current todo list with the provided items.",
        parametersJSONSchema: """
        {"type":"object","properties":{"todos":{"type":"array","items":{"type":"object","properties":{"id":{"type":"string"},"title":{"type":"string"},"status":{"type":"string","enum":["pending","in_progress","completed"]}},"required":["id","title","status"]}}},"required":["todos"]}
        """
    )

    public static let readTodos = HiveToolDefinition(
        name: "read_todos",
        description: "Read the current todo list.",
        parametersJSONSchema: """
        {"type":"object","properties":{}}
        """
    )

    public static let execute = HiveToolDefinition(
        name: "execute",
        description: "Execute a shell command using the configured sandbox backend.",
        parametersJSONSchema: """
        {"type":"object","properties":{"command":{"type":"string","description":"Shell command to execute."},"cwd":{"type":"string","description":"Optional working directory path."},"timeout_ms":{"type":"integer","description":"Optional timeout in milliseconds."}},"required":["command"]}
        """
    )

    public static let shellOpen = HiveToolDefinition(
        name: "shell_open",
        description: "Open a managed interactive shell PTY session.",
        parametersJSONSchema: """
        {"type":"object","properties":{"command":{"type":"string","description":"Command to launch (for example '/bin/zsh')."},"cwd":{"type":"string","description":"Optional working directory path."},"idle_timeout_ms":{"type":"integer","description":"Optional idle timeout in milliseconds."}},"required":["command"]}
        """
    )

    public static let shellWrite = HiveToolDefinition(
        name: "shell_write",
        description: "Write stdin bytes to an existing managed shell session.",
        parametersJSONSchema: """
        {"type":"object","properties":{"session_id":{"type":"string","description":"Shell session id."},"input":{"type":"string","description":"Input text to write."}},"required":["session_id","input"]}
        """
    )

    public static let shellRead = HiveToolDefinition(
        name: "shell_read",
        description: "Read incremental output from a managed shell session.",
        parametersJSONSchema: """
        {"type":"object","properties":{"session_id":{"type":"string","description":"Shell session id."},"max_bytes":{"type":"integer","description":"Max bytes to read (default 4096)."},"timeout_ms":{"type":"integer","description":"Optional poll timeout in milliseconds."}},"required":["session_id"]}
        """
    )

    public static let shellClose = HiveToolDefinition(
        name: "shell_close",
        description: "Close a managed shell session.",
        parametersJSONSchema: """
        {"type":"object","properties":{"session_id":{"type":"string","description":"Shell session id."}},"required":["session_id"]}
        """
    )

    public static let applyPatch = HiveToolDefinition(
        name: "apply_patch",
        description: "Apply a unified patch using the configured apply-patch backend.",
        parametersJSONSchema: """
        {"type":"object","properties":{"patch":{"type":"string","description":"Patch text to apply."}},"required":["patch"]}
        """
    )

    public static let webSearch = HiveToolDefinition(
        name: "web_search",
        description: "Search the web via the configured web backend.",
        parametersJSONSchema: """
        {"type":"object","properties":{"query":{"type":"string","description":"Search query."},"limit":{"type":"integer","description":"Optional result limit."}},"required":["query"]}
        """
    )

    public static let codeSearch = HiveToolDefinition(
        name: "code_search",
        description: "Search code using the configured code-search backend.",
        parametersJSONSchema: """
        {"type":"object","properties":{"query":{"type":"string","description":"Code search query."},"path":{"type":"string","description":"Optional search path scope."}},"required":["query"]}
        """
    )

    public static let memoryRecall = HiveToolDefinition(
        name: "wax_recall",
        description: "Recall relevant memory entries from the configured memory backend.",
        parametersJSONSchema: """
        {"type":"object","properties":{"query":{"type":"string","description":"Recall query text."},"limit":{"type":"integer","description":"Optional max number of memory entries to return."}},"required":["query"]}
        """
    )

    public static let memoryRemember = HiveToolDefinition(
        name: "wax_remember",
        description: "Persist a memory entry in the configured memory backend.",
        parametersJSONSchema: """
        {"type":"object","properties":{"content":{"type":"string","description":"Memory content to store."},"tags":{"type":"array","items":{"type":"string"},"description":"Optional tags used for later recall."},"metadata":{"type":"object","additionalProperties":{"type":"string"},"description":"Optional structured metadata."}},"required":["content"]}
        """
    )

    public static let mcpListResources = HiveToolDefinition(
        name: "mcp_list_resources",
        description: "List resources from the configured MCP backend.",
        parametersJSONSchema: """
        {"type":"object","properties":{}}
        """
    )

    public static let mcpReadResource = HiveToolDefinition(
        name: "mcp_read_resource",
        description: "Read a resource by id from the configured MCP backend.",
        parametersJSONSchema: """
        {"type":"object","properties":{"resource_id":{"type":"string","description":"Resource id to read."}},"required":["resource_id"]}
        """
    )

    public static let pluginListTools = HiveToolDefinition(
        name: "plugin_list_tools",
        description: "List plugin tools available from the configured plugin registry.",
        parametersJSONSchema: """
        {"type":"object","properties":{}}
        """
    )

    public static let pluginInvoke = HiveToolDefinition(
        name: "plugin_invoke",
        description: "Invoke a plugin tool by name with JSON arguments.",
        parametersJSONSchema: """
        {"type":"object","properties":{"name":{"type":"string","description":"Plugin tool name."},"arguments_json":{"type":"string","description":"Raw JSON arguments payload."}},"required":["name","arguments_json"]}
        """
    )

    public static let gitStatus = HiveToolDefinition(
        name: "git_status",
        description: "Inspect working tree and branch status from the configured Git backend.",
        parametersJSONSchema: """
        {"type":"object","properties":{"repo_path":{"type":"string","description":"Optional repository path."},"include_untracked":{"type":"boolean","description":"Include untracked files (default true)."}}}
        """
    )

    public static let gitDiff = HiveToolDefinition(
        name: "git_diff",
        description: "Get repository diffs from the configured Git backend.",
        parametersJSONSchema: """
        {"type":"object","properties":{"repo_path":{"type":"string","description":"Optional repository path."},"base_ref":{"type":"string","description":"Optional base revision."},"head_ref":{"type":"string","description":"Optional head revision."},"pathspec":{"type":"string","description":"Optional single path/pathspec filter."},"staged":{"type":"boolean","description":"Compare staged changes when true (default false)."}}}
        """
    )

    public static let gitCommit = HiveToolDefinition(
        name: "git_commit",
        description: "Create a commit using the configured Git backend.",
        parametersJSONSchema: """
        {"type":"object","properties":{"repo_path":{"type":"string","description":"Optional repository path."},"message":{"type":"string","description":"Commit message."},"include_all":{"type":"boolean","description":"Stage tracked changes before commit (default true)."},"amend":{"type":"boolean","description":"Amend the previous commit (default false)."},"signoff":{"type":"boolean","description":"Add Signed-off-by trailer (default false)."}},"required":["message"]}
        """
    )

    public static let gitBranch = HiveToolDefinition(
        name: "git_branch",
        description: "List/create/checkout/delete branches via the configured Git backend.",
        parametersJSONSchema: """
        {"type":"object","properties":{"repo_path":{"type":"string","description":"Optional repository path."},"operation":{"type":"string","enum":["list","create","checkout","delete"],"description":"Branch operation."},"name":{"type":"string","description":"Target branch name for create/checkout/delete."},"start_point":{"type":"string","description":"Optional start point for create."},"force":{"type":"boolean","description":"Force checkout/delete behavior where supported."}},"required":["operation"]}
        """
    )

    public static let gitPush = HiveToolDefinition(
        name: "git_push",
        description: "Push commits using the configured Git backend.",
        parametersJSONSchema: """
        {"type":"object","properties":{"repo_path":{"type":"string","description":"Optional repository path."},"remote":{"type":"string","description":"Remote name (default origin)."},"branch":{"type":"string","description":"Branch to push (backend default when omitted)."},"set_upstream":{"type":"boolean","description":"Set upstream tracking (default false)."},"force_with_lease":{"type":"boolean","description":"Force push with lease protection (default false)."}}}
        """
    )

    public static let gitPreparePR = HiveToolDefinition(
        name: "git_prepare_pr",
        description: "Prepare pull-request metadata from the configured Git backend.",
        parametersJSONSchema: """
        {"type":"object","properties":{"repo_path":{"type":"string","description":"Optional repository path."},"base_branch":{"type":"string","description":"Base branch name."},"head_branch":{"type":"string","description":"Head branch name."},"title":{"type":"string","description":"Pull request title."},"body":{"type":"string","description":"Pull request body."},"draft":{"type":"boolean","description":"Prepare draft pull request (default false)."}},"required":["base_branch","head_branch","title","body"]}
        """
    )

    public static let lspSymbols = HiveToolDefinition(
        name: "lsp_symbols",
        description: "Query symbols from the configured LSP backend.",
        parametersJSONSchema: """
        {"type":"object","properties":{"path":{"type":"string","description":"Optional file path scope."},"query":{"type":"string","description":"Optional symbol search query."}}}
        """
    )

    public static let lspDiagnostics = HiveToolDefinition(
        name: "lsp_diagnostics",
        description: "Fetch diagnostics from the configured LSP backend.",
        parametersJSONSchema: """
        {"type":"object","properties":{"path":{"type":"string","description":"Optional file path scope."}}}
        """
    )

    public static let lspReferences = HiveToolDefinition(
        name: "lsp_references",
        description: "Find references for a symbol from the configured LSP backend.",
        parametersJSONSchema: """
        {"type":"object","properties":{"path":{"type":"string","description":"File path containing the symbol."},"line":{"type":"integer","description":"0-indexed line number."},"character":{"type":"integer","description":"0-indexed character offset."},"include_declaration":{"type":"boolean","description":"Include declaration references (default true)."}},"required":["path","line","character"]}
        """
    )

    public static let lspApplyEdit = HiveToolDefinition(
        name: "lsp_apply_edit",
        description: "Apply LSP text edits through the configured LSP backend.",
        parametersJSONSchema: """
        {"type":"object","properties":{"edits":{"type":"array","items":{"type":"object","properties":{"path":{"type":"string","description":"File path for edit."},"start_line":{"type":"integer","description":"0-indexed start line."},"start_character":{"type":"integer","description":"0-indexed start character."},"end_line":{"type":"integer","description":"0-indexed end line."},"end_character":{"type":"integer","description":"0-indexed end character."},"new_text":{"type":"string","description":"Replacement text."}},"required":["path","start_line","start_character","end_line","end_character","new_text"]}}},"required":["edits"]}
        """
    )

    public static let scratchRead = HiveToolDefinition(
        name: "scratch_read",
        description: "Read the Scratchbook (compact view).",
        parametersJSONSchema: """
        {"type":"object","properties":{}}
        """
    )

    public static let scratchAdd = HiveToolDefinition(
        name: "scratch_add",
        description: "Add a Scratchbook item (note/todo/task).",
        parametersJSONSchema: """
        {"type":"object","properties":{"kind":{"type":"string","enum":["note","todo","task"],"description":"Item kind."},"title":{"type":"string","description":"Short title."},"body":{"type":"string","description":"Optional body text."},"tags":{"type":"array","items":{"type":"string"},"description":"Optional tags."},"phase":{"type":"string","description":"Optional task phase (task kind only)."},"progress":{"type":"number","description":"Optional task progress 0..1 (task kind only)."}},"required":["kind","title"]}
        """
    )

    public static let scratchUpdate = HiveToolDefinition(
        name: "scratch_update",
        description: "Update fields on an existing Scratchbook item by id.",
        parametersJSONSchema: """
        {"type":"object","properties":{"id":{"type":"string","description":"Item id."},"title":{"type":"string","description":"New title."},"body":{"type":"string","description":"New body."},"tags":{"type":"array","items":{"type":"string"},"description":"New tags."},"status":{"type":"string","enum":["open","in_progress","blocked","done","archived"],"description":"New status."},"phase":{"type":"string","description":"Optional task phase."},"progress":{"type":"number","description":"Optional task progress 0..1."}},"required":["id"]}
        """
    )

    public static let scratchComplete = HiveToolDefinition(
        name: "scratch_complete",
        description: "Mark a Scratchbook item done by id.",
        parametersJSONSchema: """
        {"type":"object","properties":{"id":{"type":"string","description":"Item id."}},"required":["id"]}
        """
    )

    public static let scratchPin = HiveToolDefinition(
        name: "scratch_pin",
        description: "Pin a Scratchbook item by id.",
        parametersJSONSchema: """
        {"type":"object","properties":{"id":{"type":"string","description":"Item id."}},"required":["id"]}
        """
    )

    public static let scratchUnpin = HiveToolDefinition(
        name: "scratch_unpin",
        description: "Unpin a Scratchbook item by id.",
        parametersJSONSchema: """
        {"type":"object","properties":{"id":{"type":"string","description":"Item id."}},"required":["id"]}
        """
    )

    public static func task(availableSubagents: [ColonySubagentDescriptor]) -> HiveToolDefinition {
        let available: String
        if availableSubagents.isEmpty {
            available = "(none configured)"
        } else {
            available = availableSubagents
                .sorted { $0.name.utf8.lexicographicallyPrecedes($1.name.utf8) }
                .map { "\($0.name): \($0.description)" }
                .joined(separator: "; ")
        }
        return HiveToolDefinition(
            name: taskName,
            description: "Launch an isolated subagent task. Available subagents: \(available)",
            parametersJSONSchema: """
            {"type":"object","properties":{"prompt":{"type":"string","description":"Detailed delegated task prompt for the subagent."},"subagent_type":{"type":"string","description":"Name of the subagent to invoke. Use 'general-purpose' when unsure."},"context":{"type":"object","description":"Optional structured task context for the subagent.","properties":{"objective":{"type":"string","description":"Primary objective for the delegated task."},"constraints":{"type":"array","items":{"type":"string"},"description":"Hard constraints the subagent must follow."},"acceptance_criteria":{"type":"array","items":{"type":"string"},"description":"Checks that define task completion."},"notes":{"type":"array","items":{"type":"string"},"description":"Additional relevant notes."}}},"file_references":{"type":"array","description":"Optional file-backed context references to include in the delegated prompt.","items":{"type":"object","properties":{"path":{"type":"string","description":"Virtual file path."},"offset":{"type":"integer","description":"0-indexed line offset for snippet extraction."},"limit":{"type":"integer","description":"Max lines to include for this file reference."}},"required":["path"]}}},"required":["prompt"]}
            """
        )
    }
}
