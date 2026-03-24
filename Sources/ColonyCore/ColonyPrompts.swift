import HiveCore

/// Namespace for system prompt construction in Colony.
///
/// `ColonyPrompts` provides factory methods for constructing system prompts
/// with appropriate sections based on the agent's configuration and capabilities.
public enum ColonyPrompts {
    /// The base system prompt with core agent rules.
    ///
    /// This text establishes the foundational behavior expectations for all Colony agents.
    public static let baseSystemPrompt: String = """
You have tools to help complete the user's objective.

Rules:
- Be concise unless asked for detail.
- Use tools instead of guessing.
- Read files before editing; avoid unnecessary changes.
- Skills are metadata-only; read the SKILL.md when needed.
- Update memory files only when asked; never store secrets.
"""

    /// Builds a system prompt with additional text and available tools.
    ///
    /// - Parameters:
    ///   - additional: Additional prompt text to append
    ///   - availableTools: List of tool definitions to include in the prompt
    /// - Returns: A complete system prompt string
    public static func systemPrompt(
        additional: String?,
        availableTools: [HiveToolDefinition]
    ) -> String {
        systemPrompt(
            additional: additional,
            memory: nil,
            skills: nil,
            scratchbook: nil,
            availableTools: availableTools
        )
    }

    /// Builds a system prompt with memory, skills, and available tools.
    ///
    /// - Parameters:
    ///   - additional: Additional prompt text to append
    ///   - memory: Memory content to include
    ///   - skills: Skills content to include
    ///   - availableTools: List of tool definitions to include in the prompt
    /// - Returns: A complete system prompt string
    public static func systemPrompt(
        additional: String?,
        memory: String?,
        skills: String?,
        availableTools: [HiveToolDefinition]
    ) -> String {
        systemPrompt(
            additional: additional,
            memory: memory,
            skills: skills,
            scratchbook: nil,
            availableTools: availableTools
        )
    }

    /// Builds a complete system prompt with all sections.
    ///
    /// The prompt sections are ordered as follows:
    /// 1. Base system prompt (always)
    /// 2. Additional prompt text (if provided)
    /// 3. Scratchbook (if provided, placed before memory/skills for token truncation resilience)
    /// 4. Memory (if provided)
    /// 5. Skills (if provided)
    /// 6. Available tools (if any)
    ///
    /// - Parameters:
    ///   - additional: Additional prompt text to append
    ///   - memory: Memory content to include
    ///   - skills: Skills content to include
    ///   - scratchbook: Scratchbook content to include
    ///   - availableTools: List of tool definitions to include in the prompt
    /// - Returns: A complete system prompt string
    public static func systemPrompt(
        additional: String?,
        memory: String?,
        skills: String?,
        scratchbook: String?,
        availableTools: [HiveToolDefinition]
    ) -> String {
        var sections: [String] = [baseSystemPrompt]
        if let additional, additional.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            sections.append(additional)
        }

        // Scratchbook is placed before Memory/Skills so that under hard token
        // limits (where the system message is truncated from the end) the active
        // agent state survives while reference material is shed first.
        if let scratchbook, scratchbook.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            sections.append("Scratchbook:\n" + scratchbook)
        }

        if let memory, memory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            sections.append("Memory:\n" + memory)
        }

        if let skills, skills.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            sections.append("Skills:\n" + skills)
        }

        if availableTools.isEmpty == false {
            let toolList = availableTools
                .sorted { $0.name.utf8.lexicographicallyPrecedes($1.name.utf8) }
                .map { "- \($0.name): \($0.description)" }
                .joined(separator: "\n")
            sections.append("Tools:\n" + toolList)
        }

        return sections.joined(separator: "\n\n")
    }
}
