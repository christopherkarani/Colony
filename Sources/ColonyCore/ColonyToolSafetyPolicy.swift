// MARK: - ColonyTool.RiskLevel

extension ColonyTool {
    public enum RiskLevel: String, Codable, Sendable, CaseIterable, Comparable {
        case readOnly = "read_only"
        case stateMutation = "state_mutation"
        case mutation
        case execution
        case network

        public static func < (lhs: ColonyTool.RiskLevel, rhs: ColonyTool.RiskLevel) -> Bool {
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
}

// MARK: - ColonyToolApproval.RequirementReason

extension ColonyToolApproval {
    public enum RequirementReason: String, Codable, Sendable, Equatable {
        case mandatoryRiskLevel = "mandatory_risk_level"
        case toolMetadataAlways = "tool_metadata_always"
        case policyAlways = "policy_always"
        case policyNotAllowListed = "policy_not_allow_listed"
    }
}

// MARK: - ColonyToolApproval.Disposition

extension ColonyToolApproval {
    public enum Disposition: String, Codable, Sendable, Equatable {
        case automatic
        case always
        case never
    }
}

// MARK: - ColonyToolApproval.RetryDisposition

extension ColonyToolApproval {
    public enum RetryDisposition: String, Codable, Sendable, Equatable {
        case inherit
        case never
        case safeToRetry
        case approvalGated
    }
}

// MARK: - ColonyToolApproval.ResultDurability

extension ColonyToolApproval {
    public enum ResultDurability: String, Codable, Sendable, Equatable {
        case transient
        case checkpointed
        case durable
    }
}

// MARK: - ColonyTool.PolicyMetadata

extension ColonyTool {
    public struct PolicyMetadata: Codable, Sendable, Equatable {
        public var riskLevel: ColonyTool.RiskLevel?
        public var approvalDisposition: ColonyToolApproval.Disposition
        public var retryDisposition: ColonyToolApproval.RetryDisposition
        public var resultDurability: ColonyToolApproval.ResultDurability

        public init(
            riskLevel: ColonyTool.RiskLevel? = nil,
            approvalDisposition: ColonyToolApproval.Disposition = .automatic,
            retryDisposition: ColonyToolApproval.RetryDisposition = .inherit,
            resultDurability: ColonyToolApproval.ResultDurability = .transient
        ) {
            self.riskLevel = riskLevel
            self.approvalDisposition = approvalDisposition
            self.retryDisposition = retryDisposition
            self.resultDurability = resultDurability
        }
    }
}

// MARK: - Package types (unchanged names)

package struct ColonyToolSafetyAssessment: Sendable, Equatable {
    package var toolCallID: ColonyToolCallID
    package var toolName: ColonyTool.Name
    package var riskLevel: ColonyTool.RiskLevel
    package var requiresApproval: Bool
    package var reason: ColonyToolApproval.RequirementReason?
    package var approvalDisposition: ColonyToolApproval.Disposition
    package var retryDisposition: ColonyToolApproval.RetryDisposition
    package var resultDurability: ColonyToolApproval.ResultDurability

    package init(
        toolCallID: ColonyToolCallID,
        toolName: ColonyTool.Name,
        riskLevel: ColonyTool.RiskLevel,
        requiresApproval: Bool,
        reason: ColonyToolApproval.RequirementReason?,
        approvalDisposition: ColonyToolApproval.Disposition = .automatic,
        retryDisposition: ColonyToolApproval.RetryDisposition = .inherit,
        resultDurability: ColonyToolApproval.ResultDurability = .transient
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

package struct ColonyToolSafetyPolicyEngine: Sendable {
    package var approvalPolicy: ColonyToolApproval.Policy
    package var riskLevelOverrides: [ColonyTool.Name: ColonyTool.RiskLevel]
    package var toolPolicyMetadataByName: [ColonyTool.Name: ColonyTool.PolicyMetadata]
    package var mandatoryApprovalRiskLevels: Set<ColonyTool.RiskLevel>
    package var defaultRiskLevel: ColonyTool.RiskLevel

    package init(
        approvalPolicy: ColonyToolApproval.Policy,
        riskLevelOverrides: [ColonyTool.Name: ColonyTool.RiskLevel] = [:],
        toolPolicyMetadataByName: [ColonyTool.Name: ColonyTool.PolicyMetadata] = [:],
        mandatoryApprovalRiskLevels: Set<ColonyTool.RiskLevel> = [.mutation, .execution, .network],
        defaultRiskLevel: ColonyTool.RiskLevel = .readOnly
    ) {
        self.approvalPolicy = approvalPolicy
        self.riskLevelOverrides = riskLevelOverrides
        self.toolPolicyMetadataByName = toolPolicyMetadataByName
        self.mandatoryApprovalRiskLevels = mandatoryApprovalRiskLevels
        self.defaultRiskLevel = defaultRiskLevel
    }

    package func riskLevel(for toolName: ColonyTool.Name) -> ColonyTool.RiskLevel {
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

    package func assess(toolCalls: [ColonyTool.Call]) -> [ColonyToolSafetyAssessment] {
        toolCalls.map { call in
            let toolName = call.name
            let riskLevel = riskLevel(for: toolName)
            let metadata = toolPolicyMetadataByName[toolName] ?? ColonyTool.PolicyMetadata()

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

            let policyRequiresApproval = approvalPolicy.requiresApproval(for: toolName)
            if policyRequiresApproval, metadata.approvalDisposition != .never {
                let reason: ColonyToolApproval.RequirementReason = {
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
    private static let defaultRiskLevelForToolName: [ColonyTool.Name: ColonyTool.RiskLevel] = [
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

