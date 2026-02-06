import HiveCore

public enum ColonyPrompts {
    public static let baseSystemPrompt: String = """
In order to complete the objective that the user asks of you, you have access to a number of standard tools.

Follow these rules:
- Be concise and direct unless the user asks for detail.
- Prefer using tools over guessing.
- When operating on files, read before editing, and avoid unnecessary changes.
- Skills are metadata-only; read the referenced SKILL.md file when needed.
- If memory files are provided, update them via edit_file only when asked (never store secrets).
"""

    public static func systemPrompt(
        additional: String?,
        availableTools: [HiveToolDefinition]
    ) -> String {
        systemPrompt(
            additional: additional,
            memory: nil,
            skills: nil,
            availableTools: availableTools
        )
    }

    public static func systemPrompt(
        additional: String?,
        memory: String?,
        skills: String?,
        availableTools: [HiveToolDefinition]
    ) -> String {
        var sections: [String] = [baseSystemPrompt]
        if let additional, additional.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            sections.append(additional)
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
