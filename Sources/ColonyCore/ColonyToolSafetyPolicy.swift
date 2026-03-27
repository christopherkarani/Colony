/// Risk level classification for tools, ordered by increasing severity.
///
/// `ColonyToolRiskLevel` classifies tools based on their potential impact:
/// - `.readOnly` — Read-only operations with no side effects
/// - `.stateMutation` — Modifies internal agent state (e.g., scratchpad)
/// - `.mutation` — Modifies files or git state
/// - `.execution` — Runs arbitrary code or commands
/// - `.network` — Makes network requests
public enum ColonyToolRiskLevel: String, Codable, Sendable, CaseIterable, Comparable {
    /// Read-only operation with no side effects.
    case readOnly = "read_only"
    /// Modifies internal agent state (e.g., scratchpad, todos).
    case stateMutation = "state_mutation"
    /// Modifies files, disk state, or git state.
    case mutation
    /// Executes arbitrary code or commands.
    case execution
    /// Makes network requests to external services.
    case network

    public static func < (lhs: ColonyToolRiskLevel, rhs: ColonyToolRiskLevel) -> Bool {
        lhs.rank < rhs.rank
    }

    private var rank: Int {
        switch self {
        case .readOnly:
            return 0
        case .stateMutation:
            return 1
        case .mutation:
            return 2
        case .execution:
            return 3
        case .network:
            return 4
        }
    }
}

/// Reason why a tool requires approval.
public enum ColonyToolApprovalRequirementReason: String, Codable, Sendable, Equatable {
    /// Required because its risk level mandates approval.
    case mandatoryRiskLevel = "mandatory_risk_level"
    /// Required because the approval policy is `.always`.
    case policyAlways = "policy_always"
    /// Required because the tool is not in the allow list.
    case policyNotAllowListed = "policy_not_allow_listed"
}

/// Result of assessing a single tool call's safety properties.
public struct ColonyToolSafetyAssessment: Sendable, Equatable {
    /// The unique identifier of the tool call.
    public var toolCallID: String
    /// The name of the tool being assessed.
    public var toolName: String
    /// The risk level assigned to this tool.
    public var riskLevel: ColonyToolRiskLevel
    /// Whether this tool requires approval before execution.
    public var requiresApproval: Bool
    /// The reason approval is required, if applicable.
    public var reason: ColonyToolApprovalRequirementReason?

    public init(
        toolCallID: String,
        toolName: String,
        riskLevel: ColonyToolRiskLevel,
        requiresApproval: Bool,
        reason: ColonyToolApprovalRequirementReason?
    ) {
        self.toolCallID = toolCallID
        self.toolName = toolName
        self.riskLevel = riskLevel
        self.requiresApproval = requiresApproval
        self.reason = reason
    }
}

/// Engine for evaluating tool safety and determining approval requirements.
///
/// `ColonyToolSafetyPolicyEngine` combines the tool approval policy with
/// risk level overrides to produce safety assessments for tool calls.
public struct ColonyToolSafetyPolicyEngine: Sendable {
    /// The base approval policy to apply.
    public var approvalPolicy: ColonyToolApprovalPolicy
    /// Tool-specific risk level overrides.
    public var riskLevelOverrides: [String: ColonyToolRiskLevel]
    /// Risk levels that always require approval regardless of policy.
    public var mandatoryApprovalRiskLevels: Set<ColonyToolRiskLevel>
    /// Default risk level for unknown tools.
    public var defaultRiskLevel: ColonyToolRiskLevel

    public init(
        approvalPolicy: ColonyToolApprovalPolicy,
        riskLevelOverrides: [String: ColonyToolRiskLevel] = [:],
        mandatoryApprovalRiskLevels: Set<ColonyToolRiskLevel> = [.mutation, .execution, .network],
        defaultRiskLevel: ColonyToolRiskLevel = .readOnly
    ) {
        self.approvalPolicy = approvalPolicy
        self.riskLevelOverrides = riskLevelOverrides
        self.mandatoryApprovalRiskLevels = mandatoryApprovalRiskLevels
        self.defaultRiskLevel = defaultRiskLevel
    }

    /// Returns the effective risk level for a tool.
    ///
    /// Resolution order: override > built-in default > configured default.
    ///
    /// - Parameter toolName: The name of the tool
    /// - Returns: The risk level to assign to this tool
    public func riskLevel(for toolName: String) -> ColonyToolRiskLevel {
        if let override = riskLevelOverrides[toolName] {
            return override
        }
        if let builtIn = Self.defaultRiskLevelForToolName[toolName] {
            return builtIn
        }
        return defaultRiskLevel
    }

    /// Assesses the safety of a batch of tool calls.
    ///
    /// - Parameter toolCalls: The tool calls to assess
    /// - Returns: An array of safety assessments, one per tool call
    public func assess(toolCalls: [ColonyToolCall]) -> [ColonyToolSafetyAssessment] {
        toolCalls.map { call in
            let riskLevel = riskLevel(for: call.name)

            if mandatoryApprovalRiskLevels.contains(riskLevel) {
                return ColonyToolSafetyAssessment(
                    toolCallID: call.id,
                    toolName: call.name,
                    riskLevel: riskLevel,
                    requiresApproval: true,
                    reason: .mandatoryRiskLevel
                )
            }

            if approvalPolicy.requiresApproval(for: call.name) {
                let reason: ColonyToolApprovalRequirementReason = {
                    switch approvalPolicy {
                    case .always:
                        return .policyAlways
                    case .allowList:
                        return .policyNotAllowListed
                    case .never:
                        return .policyAlways
                    }
                }()

                return ColonyToolSafetyAssessment(
                    toolCallID: call.id,
                    toolName: call.name,
                    riskLevel: riskLevel,
                    requiresApproval: true,
                    reason: reason
                )
            }

            return ColonyToolSafetyAssessment(
                toolCallID: call.id,
                toolName: call.name,
                riskLevel: riskLevel,
                requiresApproval: false,
                reason: nil
            )
        }
    }
}

extension ColonyToolSafetyPolicyEngine {
    private static let defaultRiskLevelForToolName: [String: ColonyToolRiskLevel] = [
        ColonyBuiltInToolDefinitions.ls.name: .readOnly,
        ColonyBuiltInToolDefinitions.readFile.name: .readOnly,
        ColonyBuiltInToolDefinitions.glob.name: .readOnly,
        ColonyBuiltInToolDefinitions.grep.name: .readOnly,
        ColonyBuiltInToolDefinitions.readTodos.name: .readOnly,
        ColonyBuiltInToolDefinitions.scratchRead.name: .readOnly,
        ColonyBuiltInToolDefinitions.workspaceRead.name: .readOnly,
        ColonyBuiltInToolDefinitions.gitStatus.name: .readOnly,
        ColonyBuiltInToolDefinitions.gitDiff.name: .readOnly,
        ColonyBuiltInToolDefinitions.lspSymbols.name: .readOnly,
        ColonyBuiltInToolDefinitions.lspDiagnostics.name: .readOnly,
        ColonyBuiltInToolDefinitions.lspReferences.name: .readOnly,
        ColonyBuiltInToolDefinitions.shellRead.name: .readOnly,
        ColonyBuiltInToolDefinitions.mcpListResources.name: .readOnly,
        ColonyBuiltInToolDefinitions.mcpReadResource.name: .readOnly,
        ColonyBuiltInToolDefinitions.pluginListTools.name: .readOnly,
        ColonyBuiltInToolDefinitions.memoryRecall.name: .readOnly,

        ColonyBuiltInToolDefinitions.writeTodos.name: .stateMutation,
        ColonyBuiltInToolDefinitions.scratchAdd.name: .stateMutation,
        ColonyBuiltInToolDefinitions.scratchUpdate.name: .stateMutation,
        ColonyBuiltInToolDefinitions.scratchComplete.name: .stateMutation,
        ColonyBuiltInToolDefinitions.scratchPin.name: .stateMutation,
        ColonyBuiltInToolDefinitions.scratchUnpin.name: .stateMutation,
        ColonyBuiltInToolDefinitions.workspaceAdd.name: .stateMutation,
        ColonyBuiltInToolDefinitions.workspaceUpdate.name: .stateMutation,
        ColonyBuiltInToolDefinitions.workspaceComplete.name: .stateMutation,
        ColonyBuiltInToolDefinitions.workspacePin.name: .stateMutation,
        ColonyBuiltInToolDefinitions.workspaceUnpin.name: .stateMutation,
        ColonyBuiltInToolDefinitions.memoryRemember.name: .stateMutation,

        ColonyBuiltInToolDefinitions.writeFile.name: .mutation,
        ColonyBuiltInToolDefinitions.editFile.name: .mutation,
        ColonyBuiltInToolDefinitions.gitCommit.name: .mutation,
        ColonyBuiltInToolDefinitions.gitBranch.name: .mutation,
        ColonyBuiltInToolDefinitions.lspApplyEdit.name: .mutation,
        ColonyBuiltInToolDefinitions.applyPatch.name: .mutation,

        ColonyBuiltInToolDefinitions.execute.name: .execution,
        ColonyBuiltInToolDefinitions.shellOpen.name: .execution,
        ColonyBuiltInToolDefinitions.shellWrite.name: .execution,
        ColonyBuiltInToolDefinitions.shellClose.name: .execution,
        ColonyBuiltInToolDefinitions.taskName: .execution,

        ColonyBuiltInToolDefinitions.gitPush.name: .network,
        ColonyBuiltInToolDefinitions.gitPreparePR.name: .network,
        ColonyBuiltInToolDefinitions.webSearch.name: .network,
        ColonyBuiltInToolDefinitions.codeSearch.name: .network,
        ColonyBuiltInToolDefinitions.pluginInvoke.name: .network,

        "tavily_search": .network,
        "tavily_extract": .network,
    ]
}
