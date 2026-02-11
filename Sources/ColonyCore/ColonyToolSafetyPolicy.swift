import HiveCore

public enum ColonyToolRiskLevel: String, Codable, Sendable, CaseIterable, Comparable {
    case readOnly = "read_only"
    case stateMutation = "state_mutation"
    case mutation
    case execution
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

public enum ColonyToolApprovalRequirementReason: String, Codable, Sendable, Equatable {
    case mandatoryRiskLevel = "mandatory_risk_level"
    case policyAlways = "policy_always"
    case policyNotAllowListed = "policy_not_allow_listed"
}

public struct ColonyToolSafetyAssessment: Sendable, Equatable {
    public var toolCallID: String
    public var toolName: String
    public var riskLevel: ColonyToolRiskLevel
    public var requiresApproval: Bool
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

public struct ColonyToolSafetyPolicyEngine: Sendable {
    public var approvalPolicy: ColonyToolApprovalPolicy
    public var riskLevelOverrides: [String: ColonyToolRiskLevel]
    public var mandatoryApprovalRiskLevels: Set<ColonyToolRiskLevel>
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

    public func riskLevel(for toolName: String) -> ColonyToolRiskLevel {
        if let override = riskLevelOverrides[toolName] {
            return override
        }
        if let builtIn = Self.defaultRiskLevelForToolName[toolName] {
            return builtIn
        }
        return defaultRiskLevel
    }

    public func assess(toolCalls: [HiveToolCall]) -> [ColonyToolSafetyAssessment] {
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
