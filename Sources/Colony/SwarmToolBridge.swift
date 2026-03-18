import Foundation
import HiveCore
import ColonyCore
import Swarm
import HiveSwarm

/// A registration entry for a Swarm tool within Colony's capability-gated system.
///
/// Associates a Swarm `AnyJSONTool` with a Colony capability and risk level,
/// so the tool participates in Colony's safety model (capability gating,
/// approval policy, and risk-level enforcement).
public struct SwarmToolRegistration: Sendable {
    /// The Swarm tool to register.
    public let tool: any AnyJSONTool

    /// The Colony capability required for this tool to be injected into the prompt.
    /// The tool will only appear when this capability is enabled in the configuration.
    public let capability: ColonyCapabilities

    /// The risk level for Colony's safety policy engine.
    /// Controls whether the tool requires human approval before execution.
    public let riskLevel: ColonyToolRiskLevel

    public init(
        tool: any AnyJSONTool,
        capability: ColonyCapabilities,
        riskLevel: ColonyToolRiskLevel = .readOnly
    ) {
        self.tool = tool
        self.capability = capability
        self.riskLevel = riskLevel
    }
}

/// Bridges Swarm's `@Tool`-defined tools into Colony's capability-gated tool system.
///
/// `SwarmToolBridge` wraps a `SwarmToolRegistry` (which handles the `AnyJSONTool` → `HiveToolDefinition`
/// conversion and execution) and layers Colony's safety model on top:
///
/// 1. **Capability gating:** Tools are only listed when their associated `ColonyCapabilities` flag
///    is enabled in the current configuration.
/// 2. **Risk-level overrides:** Each registered tool's risk level is injected into
///    `ColonyToolSafetyPolicyEngine` so approval policies apply correctly.
/// 3. **HiveToolRegistry conformance:** The bridge implements `HiveToolRegistry`, so it can be
///    composed with Colony's built-in tool registry.
///
/// ## Usage
///
/// ```swift
/// let bridge = try SwarmToolBridge(registrations: [
///     SwarmToolRegistration(tool: mySearchTool, capability: .webSearch, riskLevel: .network),
///     SwarmToolRegistration(tool: myCalcTool, capability: .planning, riskLevel: .readOnly),
/// ])
///
/// let runtime = try ColonyAgentFactory().makeRuntime(
///     profile: .cloud,
///     modelName: "gpt-4",
///     swarmTools: bridge
/// )
/// ```
public struct SwarmToolBridge: HiveToolRegistry, Sendable {
    /// The underlying Swarm tool registry that handles conversion and execution.
    private let registry: SwarmToolRegistry

    /// Mapping from tool name to the capability required to expose it.
    private let capabilityMap: [String: ColonyCapabilities]

    /// Risk-level overrides for Colony's safety policy engine.
    public let riskLevelOverrides: [String: ColonyToolRiskLevel]

    /// All tool definitions (pre-filtered by capability gating happens at query time).
    private let allDefinitions: [HiveToolDefinition]

    /// Creates a bridge from an array of tool registrations.
    ///
    /// - Parameter registrations: Swarm tools with their Colony capability and risk level.
    /// - Throws: If the underlying `SwarmToolRegistry` fails to build JSON schemas.
    public init(registrations: [SwarmToolRegistration]) throws {
        let tools = registrations.map(\.tool)
        self.registry = try SwarmToolRegistry(tools: tools)

        var capMap: [String: ColonyCapabilities] = [:]
        var riskMap: [String: ColonyToolRiskLevel] = [:]
        for reg in registrations {
            capMap[reg.tool.name] = reg.capability
            riskMap[reg.tool.name] = reg.riskLevel
        }
        self.capabilityMap = capMap
        self.riskLevelOverrides = riskMap
        self.allDefinitions = registry.listTools()
    }

    /// Creates a bridge from tools that all share the same capability and risk level.
    ///
    /// Convenience initializer for the common case where all Swarm tools
    /// belong to a single capability family.
    ///
    /// - Parameters:
    ///   - tools: The Swarm tools to register.
    ///   - capability: The Colony capability for all tools.
    ///   - riskLevel: The risk level for all tools.
    public init(
        tools: [any AnyJSONTool],
        capability: ColonyCapabilities,
        riskLevel: ColonyToolRiskLevel = .readOnly
    ) throws {
        let registrations = tools.map { tool in
            SwarmToolRegistration(tool: tool, capability: capability, riskLevel: riskLevel)
        }
        try self.init(registrations: registrations)
    }

    // MARK: - HiveToolRegistry

    /// Returns tool definitions filtered by the active capabilities.
    ///
    /// Only tools whose associated capability is present in `activeCapabilities`
    /// will be included. Call with the current `ColonyConfiguration.capabilities`.
    public func listTools(filteredBy activeCapabilities: ColonyCapabilities) -> [HiveToolDefinition] {
        allDefinitions.filter { def in
            guard let required = capabilityMap[def.name] else { return false }
            return activeCapabilities.contains(required)
        }
    }

    /// Returns all tool definitions regardless of capability gating.
    ///
    /// This satisfies `HiveToolRegistry` protocol. For capability-filtered listing,
    /// use `listTools(filteredBy:)`.
    public func listTools() -> [HiveToolDefinition] {
        allDefinitions
    }

    /// Invokes a Swarm tool by delegating to the underlying `SwarmToolRegistry`.
    ///
    /// Colony's approval and safety policies should be checked *before* calling this.
    /// The `ColonyAgent` graph's tool-execution node handles approval gating.
    public func invoke(_ call: HiveToolCall) async throws -> HiveToolResult {
        try await registry.invoke(call)
    }
}
