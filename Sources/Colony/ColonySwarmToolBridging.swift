import HiveCore
import ColonyCore

/// Package-internal protocol that captures the contract Colony's runtime needs
/// from a Swarm tool bridge, without depending on the concrete
/// `ColonySwarmToolBridge` type (which now lives in `ColonySwarmInterop`).
///
/// Colony's bootstrap, agent factory, and public API store an existential of
/// this protocol so that `import Colony` never exposes Swarm types.
package protocol ColonySwarmToolBridging: ColonyToolRegistry, Sendable {
    /// Union of all capabilities required by the bridge's registered tools.
    var requiredCapabilities: ColonyAgentCapabilities { get }

    /// Risk-level overrides for Colony's safety policy engine.
    var riskLevelOverrides: [ColonyTool.Name: ColonyTool.RiskLevel] { get }

    /// Policy metadata derived from Swarm tool execution semantics.
    var toolPolicyMetadataByName: [ColonyTool.Name: ColonyTool.PolicyMetadata] { get }

    /// Returns Hive tool definitions filtered by the active capabilities.
    func listHiveTools(filteredBy activeCapabilities: ColonyAgentCapabilities) -> [HiveToolDefinition]

    /// Invokes a Hive tool call by delegating to the underlying Swarm registry.
    func invokeHive(_ call: HiveToolCall) async throws -> HiveToolResult
}
