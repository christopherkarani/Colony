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
