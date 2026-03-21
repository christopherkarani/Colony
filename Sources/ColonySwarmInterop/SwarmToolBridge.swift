import Foundation
import HiveCore
import ColonyCore
import Colony
import Swarm

/// A registration entry for a Swarm tool within Colony's capability-gated system.
///
/// Associates a Swarm `AnyJSONTool` with a Colony capability and risk level,
/// so the tool participates in Colony's safety model (capability gating,
/// approval policy, and risk-level enforcement).
public struct ColonySwarmToolRegistration: Sendable {
    /// The Swarm tool to register.
    public let tool: any AnyJSONTool

    /// The Colony capability required for this tool to be injected into the prompt.
    /// The tool will only appear when this capability is enabled in the configuration.
    public let capability: ColonyAgentCapabilities

    /// The risk level for Colony's safety policy engine.
    /// Controls whether the tool requires human approval before execution.
    public let riskLevel: ColonyTool.RiskLevel

    public init(
        tool: any AnyJSONTool,
        capability: ColonyAgentCapabilities,
        riskLevel: ColonyTool.RiskLevel = .readOnly
    ) {
        self.tool = tool
        self.capability = capability
        self.riskLevel = riskLevel
    }
}

/// Bridges Swarm's `@Tool`-defined tools into Colony's capability-gated tool system.
///
/// `ColonySwarmToolBridge` wraps a `SwarmToolRegistry` (which handles the `AnyJSONTool` → `HiveToolDefinition`
/// conversion and execution) and layers Colony's safety model on top:
///
/// 1. **Capability gating:** Tools are only listed when their associated `ColonyAgentCapabilities` flag
///    is enabled in the current configuration.
/// 2. **Risk-level overrides:** Each registered tool's risk level is injected into
///    `ColonyToolSafetyPolicyEngine` so approval policies apply correctly.
/// 3. **HiveToolRegistry conformance:** The bridge implements `HiveToolRegistry`, so it can be
///    composed with Colony's built-in tool registry.
///
/// ## Usage
///
/// ```swift
/// let bridge = try ColonySwarmToolBridge(registrations: [
///     ColonySwarmToolRegistration(tool: mySearchTool, capability: .webSearch, riskLevel: .network),
///     ColonySwarmToolRegistration(tool: myCalcTool, capability: .planning, riskLevel: .readOnly),
/// ])
///
/// let bootstrap = ColonyBootstrap()
/// let runtime = try await bootstrap.makeRuntime(options: .init(
///     profile: .cloud,
///     modelName: "gpt-4",
///     swarmTools: bridge
/// ))
/// ```
public struct ColonySwarmToolBridge: ColonySwarmToolBridging, ColonyToolRegistry, Sendable {
    /// The underlying Swarm tool registry that handles conversion and execution.
    private let registry: ColonySwarmToolRegistry

    /// Mapping from tool name to the capability required to expose it.
    private let capabilityMap: [String: ColonyAgentCapabilities]

    /// Risk-level overrides for Colony's safety policy engine.
    public let riskLevelOverrides: [ColonyTool.Name: ColonyTool.RiskLevel]

    /// Policy metadata derived from Swarm tool execution semantics.
    public let toolPolicyMetadataByName: [ColonyTool.Name: ColonyTool.PolicyMetadata]

    /// Union of all capabilities required by this bridge's registered tools.
    public let requiredCapabilities: ColonyAgentCapabilities

    /// All tool definitions (pre-filtered by capability gating happens at query time).
    private let allDefinitions: [ColonyTool.Definition]

    /// Creates a bridge from an array of tool registrations.
    ///
    /// - Parameter registrations: Swarm tools with their Colony capability and risk level.
    /// - Throws: If the underlying `SwarmToolRegistry` fails to build JSON schemas.
    public init(registrations: [ColonySwarmToolRegistration]) throws {
        let tools = registrations.map(\.tool)
        self.registry = try ColonySwarmToolRegistry(tools: tools)

        var capMap: [String: ColonyAgentCapabilities] = [:]
        var riskMap: [ColonyTool.Name: ColonyTool.RiskLevel] = [:]
        var policyMap: [ColonyTool.Name: ColonyTool.PolicyMetadata] = [:]
        var required: ColonyAgentCapabilities = []
        for reg in registrations {
            let toolName = ColonyTool.Name(rawValue: reg.tool.name)
            capMap[reg.tool.name] = reg.capability
            let metadata = Self.policyMetadata(for: reg)
            riskMap[toolName] = metadata.riskLevel ?? reg.riskLevel
            policyMap[toolName] = metadata
            required.formUnion(reg.capability)
        }
        self.capabilityMap = capMap
        self.riskLevelOverrides = riskMap
        self.toolPolicyMetadataByName = policyMap
        self.requiredCapabilities = required
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
        capability: ColonyAgentCapabilities,
        riskLevel: ColonyTool.RiskLevel = .readOnly
    ) throws {
        let registrations = tools.map { tool in
            ColonySwarmToolRegistration(tool: tool, capability: capability, riskLevel: riskLevel)
        }
        try self.init(registrations: registrations)
    }

    /// Returns tool definitions filtered by the active capabilities.
    ///
    /// Only tools whose associated capability is present in `activeCapabilities`
    /// will be included. Call with the current `ColonyConfiguration.model.capabilities`.
    public func listTools(filteredBy activeCapabilities: ColonyAgentCapabilities) -> [ColonyTool.Definition] {
        allDefinitions.filter { def in
            guard let required = capabilityMap[def.name.rawValue] else { return false }
            return activeCapabilities.contains(required)
        }
    }

    /// Returns all tool definitions regardless of capability gating.
    public func listTools() -> [ColonyTool.Definition] {
        allDefinitions
    }

    /// Invokes a Swarm tool by delegating to the underlying `SwarmToolRegistry`.
    ///
    /// Colony's approval and safety policies should be checked *before* calling this.
    /// The `ColonyAgent` graph's tool-execution node handles approval gating.
    public func invoke(_ call: ColonyTool.Call) async throws -> ColonyTool.Result {
        try await registry.invoke(call)
    }

    package func listHiveTools(filteredBy activeCapabilities: ColonyAgentCapabilities) -> [HiveToolDefinition] {
        listTools(filteredBy: activeCapabilities).map(\.hive)
    }

    package func invokeHive(_ call: HiveToolCall) async throws -> HiveToolResult {
        try await invoke(ColonyTool.Call(call)).hive
    }

    private static func policyMetadata(for registration: ColonySwarmToolRegistration) -> ColonyTool.PolicyMetadata {
        let semantics = registration.tool.executionSemantics
        let semanticRiskLevel = riskLevel(for: semantics.sideEffectLevel)
        let resolvedRiskLevel = max(registration.riskLevel, semanticRiskLevel)

        return ColonyTool.PolicyMetadata(
            riskLevel: resolvedRiskLevel,
            approvalDisposition: approvalDisposition(for: semantics.approvalRequirement),
            retryDisposition: retryDisposition(for: semantics.retryPolicy),
            resultDurability: resultDurability(for: semantics.resultDurability)
        )
    }

    private static func riskLevel(for sideEffectLevel: ToolSideEffectLevel) -> ColonyTool.RiskLevel {
        switch sideEffectLevel {
        case .unspecified, .readOnly:
            return .readOnly
        case .localMutation:
            return .stateMutation
        case .externalMutation:
            return .mutation
        }
    }

    private static func approvalDisposition(for requirement: ToolApprovalRequirement) -> ColonyToolApproval.Disposition {
        switch requirement {
        case .automatic:
            return .automatic
        case .always:
            return .always
        case .never:
            return .never
        }
    }

    private static func retryDisposition(for retryPolicy: ToolRetryPolicy) -> ColonyToolApproval.RetryDisposition {
        switch retryPolicy {
        case .automatic:
            return .inherit
        case .safe:
            return .safeToRetry
        case .unsafe:
            return .never
        case .callerManaged:
            return .approvalGated
        }
    }

    private static func resultDurability(for durability: ToolResultDurability) -> ColonyToolApproval.ResultDurability {
        switch durability {
        case .unspecified, .transcriptOnly:
            return .transient
        case .artifactBacked:
            return .checkpointed
        case .externalReference:
            return .durable
        }
    }
}

private enum ColonySwarmToolRegistryError: Error, Equatable, Sendable {
    case invalidArgumentsJSON
    case argumentsMustBeJSONObject
    case resultEncodingFailed
    case schemaEncodingFailed
    case toolNotFound(name: String)
}

private struct ColonySwarmToolRegistry: ColonyToolRegistry, Sendable {
    private let registry: ToolRegistry
    private let toolDefinitions: [ColonyTool.Definition]

    init(tools: [any AnyJSONTool]) throws {
        self.registry = try ToolRegistry(tools: tools)
        self.toolDefinitions = try tools
            .map { try Self.makeToolDefinition(for: $0.schema) }
            .sorted { $0.name.rawValue.utf8.lexicographicallyPrecedes($1.name.rawValue.utf8) }
    }

    func listTools() -> [ColonyTool.Definition] {
        toolDefinitions
    }

    func invoke(_ call: ColonyTool.Call) async throws -> ColonyTool.Result {
        let arguments = try Self.parseArgumentsJSON(call.argumentsJSON)
        guard await registry.contains(named: call.name.rawValue) else {
            throw ColonySwarmToolRegistryError.toolNotFound(name: call.name.rawValue)
        }

        let output = try await registry.execute(toolNamed: call.name.rawValue, arguments: arguments)
        let content = try Self.encodeJSONFragment(output)
        return ColonyTool.Result(toolCallID: call.id, content: content)
    }

    private static func parseArgumentsJSON(_ json: String) throws -> [String: SendableValue] {
        guard let data = json.data(using: .utf8) else {
            throw ColonySwarmToolRegistryError.invalidArgumentsJSON
        }

        let jsonObject: Any
        do {
            jsonObject = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        } catch {
            throw ColonySwarmToolRegistryError.invalidArgumentsJSON
        }

        guard let dict = jsonObject as? [String: Any] else {
            throw ColonySwarmToolRegistryError.argumentsMustBeJSONObject
        }

        var result: [String: SendableValue] = [:]
        for (key, value) in dict {
            result[key] = sendableValue(fromJSONValue: value)
        }
        return result
    }

    private static func encodeJSONFragment(_ value: SendableValue) throws -> String {
        if case let .string(text) = value {
            return text
        }

        let object = value.toJSONObject()
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .fragmentsAllowed])
        guard let json = String(data: data, encoding: .utf8) else {
            throw ColonySwarmToolRegistryError.resultEncodingFailed
        }
        return json
    }

    private static func makeToolDefinition(for schema: ToolSchema) throws -> ColonyTool.Definition {
        let schemaObject = makeParametersSchema(toolName: schema.name, parameters: schema.parameters)
        let data = try JSONSerialization.data(withJSONObject: schemaObject, options: [.sortedKeys])
        guard let json = String(data: data, encoding: .utf8) else {
            throw ColonySwarmToolRegistryError.schemaEncodingFailed
        }
        return ColonyTool.Definition(
            name: ColonyTool.Name(rawValue: schema.name),
            description: schema.description,
            parametersJSONSchema: json
        )
    }

    private static func makeParametersSchema(toolName: String, parameters: [ToolParameter]) -> [String: Any] {
        var properties: [String: Any] = [:]
        var required: [String] = []

        for parameter in parameters {
            var schema = jsonSchema(for: parameter.type)
            schema["description"] = parameter.description
            if let defaultValue = parameter.defaultValue {
                schema["default"] = defaultValue.toJSONObject()
            }
            properties[parameter.name] = schema
            if parameter.isRequired, parameter.defaultValue == nil {
                required.append(parameter.name)
            }
        }

        required.sort { $0.utf8.lexicographicallyPrecedes($1.utf8) }

        var root: [String: Any] = [
            "type": "object",
            "description": "Tool parameters for \(toolName)",
            "properties": properties,
            "additionalProperties": false,
        ]
        if !required.isEmpty {
            root["required"] = required
        }
        return root
    }

    private static func jsonSchema(for type: ToolParameter.ParameterType) -> [String: Any] {
        switch type {
        case .string:
            return ["type": "string"]
        case .int:
            return ["type": "integer"]
        case .double:
            return ["type": "number"]
        case .bool:
            return ["type": "boolean"]
        case .array(let elementType):
            return [
                "type": "array",
                "items": jsonSchema(for: elementType),
            ]
        case .object(let properties):
            var props: [String: Any] = [:]
            var required: [String] = []
            for property in properties {
                var schema = jsonSchema(for: property.type)
                schema["description"] = property.description
                if let defaultValue = property.defaultValue {
                    schema["default"] = defaultValue.toJSONObject()
                }
                props[property.name] = schema
                if property.isRequired, property.defaultValue == nil {
                    required.append(property.name)
                }
            }

            required.sort { $0.utf8.lexicographicallyPrecedes($1.utf8) }

            var object: [String: Any] = [
                "type": "object",
                "properties": props,
                "additionalProperties": false,
            ]
            if !required.isEmpty {
                object["required"] = required
            }
            return object
        case .oneOf(let options):
            return [
                "type": "string",
                "enum": options,
            ]
        case .any:
            return [
                "anyOf": [
                    ["type": "string"],
                    ["type": "number"],
                    ["type": "integer"],
                    ["type": "boolean"],
                    ["type": "object"],
                    ["type": "array"],
                ],
            ]
        }
    }

    private static func sendableValue(fromJSONValue value: Any) -> SendableValue {
        switch value {
        case is NSNull:
            return .null
        case let bool as Bool:
            return .bool(bool)
        case let int as Int:
            return .int(int)
        case let double as Double:
            if double.truncatingRemainder(dividingBy: 1) == 0,
               double >= -9_007_199_254_740_992, double <= 9_007_199_254_740_992
            {
                return .int(Int(double))
            }
            return .double(double)
        case let string as String:
            return .string(string)
        case let array as [Any]:
            return .array(array.map { sendableValue(fromJSONValue: $0) })
        case let dict as [String: Any]:
            return .dictionary(dict.mapValues { sendableValue(fromJSONValue: $0) })
        default:
            return .null
        }
    }
}

private extension SendableValue {
    func toJSONObject() -> Any {
        switch self {
        case .null:
            return NSNull()
        case let .bool(value):
            return value
        case let .int(value):
            return value
        case let .double(value):
            return value
        case let .string(value):
            return value
        case let .array(values):
            return values.map { $0.toJSONObject() }
        case let .dictionary(values):
            return values.mapValues { $0.toJSONObject() }
        }
    }
}
