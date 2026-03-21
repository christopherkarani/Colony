import Foundation
import ColonyCore
import Colony
import Swarm

/// Adapts Swarm's `AgentRuntime`-based agents to Colony's `ColonySubagentRegistry`.
///
/// This adapter maps Colony subagent requests to Swarm agent execution:
/// - `listSubagents()` returns descriptors for all registered Swarm agents.
/// - `run(_:)` routes the request to the named agent (or the first available)
///   and returns the agent's output as a `ColonySubagent.Result`.
///
/// Swarm agents execute with their own tools, memory, and inference providers,
/// independent of Colony's graph. This adapter bridges the result back into
/// Colony's subagent protocol.
///
/// ## Usage
///
/// ```swift
/// let researcher = ReActAgent(
///     tools: [searchTool, summarizeTool],
///     instructions: "Research specialist"
/// )
/// let adapter = ColonySwarmSubagentAdapter(agents: [
///     ("researcher", researcher, "Researches topics using web search"),
/// ])
///
/// let bootstrap = ColonyBootstrap()
/// let runtime = try await bootstrap.makeRuntime(options: .init(
///     profile: .cloud,
///     modelName: "gpt-4",
///     subagents: adapter
/// ))
/// ```
public struct ColonySwarmSubagentAdapter: ColonySubagentRegistry, Sendable {
    private let agents: [(name: String, agent: any AgentRuntime, description: String)]

    /// Creates an adapter from a list of named Swarm agents.
    ///
    /// - Parameter agents: Tuples of (name, agent, description) for each sub-agent.
    public init(agents: [(name: String, agent: any AgentRuntime, description: String)]) {
        self.agents = agents
    }

    public func listSubagents() -> [ColonySubagent.Descriptor] {
        agents.map { entry in
            ColonySubagent.Descriptor(name: entry.name, description: entry.description)
        }
    }

    public func run(_ request: ColonySubagent.Request) async throws -> ColonySubagent.Result {
        let targetName = request.subagentType.rawValue.trimmingCharacters(in: .whitespacesAndNewlines)

        // Find the agent by name, or fall back to the first registered agent.
        guard let entry = agents.first(where: { $0.name == targetName }) ?? agents.first else {
            throw SwarmSubagentAdapterError.noAgentsRegistered
        }

        let prompt = buildPrompt(from: request)
        let result = try await entry.agent.run(prompt)
        return ColonySubagent.Result(content: result.output)
    }

    private func buildPrompt(from request: ColonySubagent.Request) -> String {
        var sections: [String] = [request.prompt]

        if let context = request.context {
            var contextLines: [String] = []
            if let objective = context.objective, !objective.isEmpty {
                contextLines.append("Objective: \(objective)")
            }
            if !context.constraints.isEmpty {
                contextLines.append("Constraints: \(context.constraints.joined(separator: "; "))")
            }
            if !context.acceptanceCriteria.isEmpty {
                contextLines.append("Acceptance criteria: \(context.acceptanceCriteria.joined(separator: "; "))")
            }
            if !context.notes.isEmpty {
                contextLines.append("Notes: \(context.notes.joined(separator: "; "))")
            }
            if !contextLines.isEmpty {
                sections.append(contextLines.joined(separator: "\n"))
            }
        }

        if !request.fileReferences.isEmpty {
            let references = request.fileReferences.map { reference in
                var components = ["Path: \(reference.path.rawValue)"]
                if let offset = reference.offset {
                    components.append("Offset: \(offset)")
                }
                if let limit = reference.limit {
                    components.append("Limit: \(limit)")
                }
                return components.joined(separator: ", ")
            }
            sections.append("File references:\n" + references.joined(separator: "\n"))
        }

        return sections.joined(separator: "\n\n")
    }
}

enum SwarmSubagentAdapterError: Error, Sendable {
    case noAgentsRegistered
}
