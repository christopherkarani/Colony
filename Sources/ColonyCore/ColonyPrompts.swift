import HiveCore

public enum ColonyPrompts {
    public static let baseSystemPrompt: String = """
You have tools to help complete the user's objective.

Rules:
- Be concise unless asked for detail.
- Use tools instead of guessing.
- Read files before editing; avoid unnecessary changes.
- Skills are metadata-only; read the SKILL.md when needed.
- Update memory files only when asked. Never store secrets.
"""

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
