// MARK: - ColonyTool.RiskLevel

/// The risk level of a tool, ordered from lowest to highest: readOnly < stateMutation < mutation < execution < network.
///
/// Risk levels determine which tools require mandatory human approval regardless of the configured
/// `ColonyToolApproval.Policy`. By default, `.mutation`, `.execution`, and `.network` tools
/// require approval; `.readOnly` and `.stateMutation` tools do not.
///
/// Use `ColonyConfiguration.SafetyConfiguration.toolRiskLevelOverrides` to customize the risk
/// level of any built-in or custom tool.
extension ColonyTool {
    public enum RiskLevel: String, Codable, Sendable, CaseIterable, Comparable {
        /// Reading data without side effects — auto-approved by default.
        case readOnly = "read_only"
        /// Mutating in-memory state managed by Colony (e.g., todos, scratchbook) — auto-approved by default.
        case stateMutation = "state_mutation"
        /// Mutating persistent external state (e.g., files, git commits) — requires approval by default.
        case mutation
        /// Executing arbitrary external processes — requires approval by default.
        case execution
        /// Making network requests — requires approval by default.
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

/// The reason why a tool requires approval — useful for debugging and logging.
extension ColonyToolApproval {
    public enum RequirementReason: String, Codable, Sendable, Equatable {
        /// Tool's risk level is in the mandatory approval set (e.g., .mutation, .execution, .network).
        case mandatoryRiskLevel = "mandatory_risk_level"
        /// Tool's `PolicyMetadata` has `approvalDisposition = .always`.
        case toolMetadataAlways = "tool_metadata_always"
        /// Approval policy is `.always` and tool is not explicitly overridden.
        case policyAlways = "policy_always"
        /// Tool is not on the `.allowList` — approval required by policy.
        case policyNotAllowListed = "policy_not_allow_listed"
    }
}

// MARK: - ColonyToolApproval.Disposition

/// Controls whether a specific tool always, never, or automatically requires approval.
extension ColonyToolApproval {
    public enum Disposition: String, Codable, Sendable, Equatable {
        /// Follow the global `Policy` decision — depends on risk level and allow list.
        case automatic
        /// This tool always requires approval regardless of policy.
        case always
        /// This tool never requires approval regardless of policy.
        case never
    }
}

// MARK: - ColonyToolApproval.RetryDisposition

/// Controls whether a rejected or failed tool call can be automatically retried.
extension ColonyToolApproval {
    public enum RetryDisposition: String, Codable, Sendable, Equatable {
        /// Inherit the retry policy from the tool's risk level (default for most tools).
        case inherit
        /// Never retry this tool call after failure.
        case never
        /// Safe to retry if the failure was transient (e.g., network timeout).
        case safeToRetry
        /// Retry only after human approval is re-granted.
        case approvalGated
    }
}

// MARK: - ColonyToolApproval.ResultDurability

/// Controls whether a tool's result is checkpointed for interrupt/resume.
extension ColonyToolApproval {
    public enum ResultDurability: String, Codable, Sendable, Equatable {
        /// Result is not persisted — lost on interrupt/resume (fast).
        case transient
        /// Result is checkpointed for this interrupt cycle only.
        case checkpointed
        /// Result is durably persisted across interrupt cycles.
        case durable
    }
}

// MARK: - ColonyTool.PolicyMetadata

/// Per-tool policy overrides that supersede the global safety configuration.
///
/// Use `PolicyMetadata` to customize approval, retry, and checkpoint behavior for
/// specific tools. Set via `ColonyConfiguration.SafetyConfiguration.toolPolicyMetadataByName`.
///
/// ## Example
///
/// ```swift
/// var config = ColonyConfiguration(modelName: .claudeSonnet)
/// config.safety.toolPolicyMetadataByName[.gitPush] = ColonyTool.PolicyMetadata(
///     riskLevel: .network,                          // keep network risk level
///     approvalDisposition: .always,                  // always require approval
///     retryDisposition: .safeToRetry,               // allow retry on transient failure
///     resultDurability: .checkpointed               // checkpoint the push result
/// )
/// ```
extension ColonyTool {
    public struct PolicyMetadata: Codable, Sendable, Equatable {
        /// Override the computed risk level for this tool. `nil` uses the default.
        public var riskLevel: ColonyTool.RiskLevel?
        /// Override the approval disposition. Defaults to `.automatic`.
        public var approvalDisposition: ColonyToolApproval.Disposition
        /// Override the retry disposition. Defaults to `.inherit`.
        public var retryDisposition: ColonyToolApproval.RetryDisposition
        /// Override the result durability. Defaults to `.transient`.
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

