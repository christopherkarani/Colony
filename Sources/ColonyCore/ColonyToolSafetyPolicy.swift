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
    case toolMetadataAlways = "tool_metadata_always"
    case policyAlways = "policy_always"
    case policyNotAllowListed = "policy_not_allow_listed"
}

public enum ColonyToolApprovalDisposition: String, Codable, Sendable, Equatable {
    case automatic
    case always
    case never
}

public enum ColonyToolRetryDisposition: String, Codable, Sendable, Equatable {
    case inherit
    case never
    case safeToRetry
    case approvalGated
}

public enum ColonyToolResultDurability: String, Codable, Sendable, Equatable {
    case transient
    case checkpointed
    case durable
}

public struct ColonyToolPolicyMetadata: Codable, Sendable, Equatable {
    public var riskLevel: ColonyToolRiskLevel?
    public var approvalDisposition: ColonyToolApprovalDisposition
    public var retryDisposition: ColonyToolRetryDisposition
    public var resultDurability: ColonyToolResultDurability

    public init(
        riskLevel: ColonyToolRiskLevel? = nil,
        approvalDisposition: ColonyToolApprovalDisposition = .automatic,
        retryDisposition: ColonyToolRetryDisposition = .inherit,
        resultDurability: ColonyToolResultDurability = .transient
    ) {
        self.riskLevel = riskLevel
        self.approvalDisposition = approvalDisposition
        self.retryDisposition = retryDisposition
        self.resultDurability = resultDurability
    }
}

public struct ColonyToolSafetyAssessment: Sendable, Equatable {
    public var toolCallID: String
    public var toolName: ColonyToolName
    public var riskLevel: ColonyToolRiskLevel
    public var requiresApproval: Bool
    public var reason: ColonyToolApprovalRequirementReason?
    public var approvalDisposition: ColonyToolApprovalDisposition
    public var retryDisposition: ColonyToolRetryDisposition
    public var resultDurability: ColonyToolResultDurability

    public init(
        toolCallID: String,
        toolName: ColonyToolName,
        riskLevel: ColonyToolRiskLevel,
        requiresApproval: Bool,
        reason: ColonyToolApprovalRequirementReason?,
        approvalDisposition: ColonyToolApprovalDisposition = .automatic,
        retryDisposition: ColonyToolRetryDisposition = .inherit,
        resultDurability: ColonyToolResultDurability = .transient
    ) {
        self.toolCallID = toolCallID
        self.toolName = toolName
        self.riskLevel = riskLevel
        self.requiresApproval = requiresApproval
        self.reason = reason
        self.approvalDisposition = approvalDisposition
        self.retryDisposition = retryDisposition
        self.resultDurability = resultDurability
    }
}

public struct ColonyToolSafetyPolicyEngine: Sendable {
    public var approvalPolicy: ColonyToolApprovalPolicy
    public var riskLevelOverrides: [ColonyToolName: ColonyToolRiskLevel]
    public var toolPolicyMetadataByName: [ColonyToolName: ColonyToolPolicyMetadata]
    public var mandatoryApprovalRiskLevels: Set<ColonyToolRiskLevel>
    public var defaultRiskLevel: ColonyToolRiskLevel

    public init(
        approvalPolicy: ColonyToolApprovalPolicy,
        riskLevelOverrides: [ColonyToolName: ColonyToolRiskLevel] = [:],
        toolPolicyMetadataByName: [ColonyToolName: ColonyToolPolicyMetadata] = [:],
        mandatoryApprovalRiskLevels: Set<ColonyToolRiskLevel> = [.mutation, .execution, .network],
        defaultRiskLevel: ColonyToolRiskLevel = .readOnly
    ) {
        self.approvalPolicy = approvalPolicy
        self.riskLevelOverrides = riskLevelOverrides
        self.toolPolicyMetadataByName = toolPolicyMetadataByName
        self.mandatoryApprovalRiskLevels = mandatoryApprovalRiskLevels
        self.defaultRiskLevel = defaultRiskLevel
    }

    public func riskLevel(for toolName: ColonyToolName) -> ColonyToolRiskLevel {
        if let override = riskLevelOverrides[toolName] {
            return override
        }
        if let metadataRiskLevel = toolPolicyMetadataByName[toolName]?.riskLevel {
            return metadataRiskLevel
        }
        if let builtIn = Self.defaultRiskLevelForToolName[toolName] {
            return builtIn
        }
        return defaultRiskLevel
    }

    public func assess(toolCalls: [ColonyToolCall]) -> [ColonyToolSafetyAssessment] {
        toolCalls.map { call in
            let toolName = call.name
            let riskLevel = riskLevel(for: toolName)
            let metadata = toolPolicyMetadataByName[toolName] ?? ColonyToolPolicyMetadata()

            if metadata.approvalDisposition == .always {
                return ColonyToolSafetyAssessment(
                    toolCallID: call.id,
                    toolName: toolName,
                    riskLevel: riskLevel,
                    requiresApproval: true,
                    reason: .toolMetadataAlways,
                    approvalDisposition: metadata.approvalDisposition,
                    retryDisposition: metadata.retryDisposition,
                    resultDurability: metadata.resultDurability
                )
            }

            if mandatoryApprovalRiskLevels.contains(riskLevel) {
                return ColonyToolSafetyAssessment(
                    toolCallID: call.id,
                    toolName: toolName,
                    riskLevel: riskLevel,
                    requiresApproval: true,
                    reason: .mandatoryRiskLevel,
                    approvalDisposition: metadata.approvalDisposition,
                    retryDisposition: metadata.retryDisposition,
                    resultDurability: metadata.resultDurability
                )
            }

            let policyRequiresApproval = approvalPolicy.requiresApproval(for: toolName.rawValue)
            if policyRequiresApproval, metadata.approvalDisposition != .never {
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
                    toolName: toolName,
                    riskLevel: riskLevel,
                    requiresApproval: true,
                    reason: reason,
                    approvalDisposition: metadata.approvalDisposition,
                    retryDisposition: metadata.retryDisposition,
                    resultDurability: metadata.resultDurability
                )
            }

            return ColonyToolSafetyAssessment(
                toolCallID: call.id,
                toolName: toolName,
                riskLevel: riskLevel,
                requiresApproval: false,
                reason: nil,
                approvalDisposition: metadata.approvalDisposition,
                retryDisposition: metadata.retryDisposition,
                resultDurability: metadata.resultDurability
            )
        }
    }
}

extension ColonyToolSafetyPolicyEngine {
    private static let defaultRiskLevelForToolName: [ColonyToolName: ColonyToolRiskLevel] = [
        .ls: .readOnly,
        .readFile: .readOnly,
        .glob: .readOnly,
        .grep: .readOnly,
        .readTodos: .readOnly,
        .scratchRead: .readOnly,
        .gitStatus: .readOnly,
        .gitDiff: .readOnly,
        .lspSymbols: .readOnly,
        .lspDiagnostics: .readOnly,
        .lspReferences: .readOnly,
        .shellRead: .readOnly,
        .mcpListResources: .readOnly,
        .mcpReadResource: .readOnly,
        .pluginListTools: .readOnly,
        .memoryRecall: .readOnly,

        .writeTodos: .stateMutation,
        .scratchAdd: .stateMutation,
        .scratchUpdate: .stateMutation,
        .scratchComplete: .stateMutation,
        .scratchPin: .stateMutation,
        .scratchUnpin: .stateMutation,
        .memoryRemember: .stateMutation,

        .writeFile: .mutation,
        .editFile: .mutation,
        .gitCommit: .mutation,
        .gitBranch: .mutation,
        .lspApplyEdit: .mutation,
        .applyPatch: .mutation,

        .execute: .execution,
        .shellOpen: .execution,
        .shellWrite: .execution,
        .shellClose: .execution,
        .task: .execution,

        .gitPush: .network,
        .gitPreparePR: .network,
        .webSearch: .network,
        .codeSearch: .network,
        .pluginInvoke: .network,

        "tavily_search": .network,
        "tavily_extract": .network,
    ]
}
