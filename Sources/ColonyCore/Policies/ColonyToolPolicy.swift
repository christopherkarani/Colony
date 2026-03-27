/// Unified policy struct that combines approval and safety concerns for tool execution.
/// Replaces `ColonyToolApprovalPolicy` and `ColonyToolRiskLevel` handling.
public struct ColonyToolPolicy: Sendable {
    /// The permission policy determining which tools require approval.
    public var permissionPolicy: ToolPermissionPolicy

    /// Optional rule store for fine-grained approval decisions.
    public var approvalRules: (any ColonyToolApprovalRuleStore)?

    /// Risk level overrides for specific tools.
    public var riskOverrides: [String: ColonyToolRiskLevel]

    /// Risk levels that always require approval regardless of permission policy.
    public var requiredApprovalRisks: Set<ColonyToolRiskLevel>

    /// Default risk level for tools without explicit assignment.
    public var defaultRiskLevel: ColonyToolRiskLevel

    /// Creates a new unified tool policy.
    ///
    /// - Parameters:
    ///   - permissionPolicy: The permission policy for tool approval.
    ///   - approvalRules: Optional rule store for fine-grained decisions.
    ///   - riskOverrides: Tool-specific risk level overrides.
    ///   - requiredApprovalRisks: Risk levels that always require approval.
    ///   - defaultRiskLevel: Default risk level for unassigned tools.
    public init(
        permissionPolicy: ToolPermissionPolicy = .allowList([
            "ls", "read_file", "glob", "grep",
            "read_todos", "write_todos",
            "scratch_read", "scratch_add", "scratch_update",
            "scratch_complete", "scratch_pin", "scratch_unpin"
        ]),
        approvalRules: (any ColonyToolApprovalRuleStore)? = nil,
        riskOverrides: [String: ColonyToolRiskLevel] = [:],
        requiredApprovalRisks: Set<ColonyToolRiskLevel> = [.mutation, .execution, .network],
        defaultRiskLevel: ColonyToolRiskLevel = .readOnly
    ) {
        self.permissionPolicy = permissionPolicy
        self.approvalRules = approvalRules
        self.riskOverrides = riskOverrides
        self.requiredApprovalRisks = requiredApprovalRisks
        self.defaultRiskLevel = defaultRiskLevel
    }

    /// Determines if a tool requires approval based on this policy.
    ///
    /// - Parameter toolName: The name of the tool to check.
    /// - Returns: `true` if the tool requires approval.
    public func requiresApproval(for toolName: String) -> Bool {
        let riskLevel = riskLevel(for: toolName)

        // First check: mandatory risk levels always require approval
        if requiredApprovalRisks.contains(riskLevel) {
            return true
        }

        // Second check: permission policy
        return permissionPolicy.requiresApproval(for: toolName)
    }

    /// Determines if any tool in the list requires approval.
    ///
    /// - Parameter toolNames: The names of the tools to check.
    /// - Returns: `true` if any tool requires approval.
    public func requiresApproval(for toolNames: [String]) -> Bool {
        toolNames.contains(where: requiresApproval(for:))
    }

    /// Gets the risk level for a specific tool.
    ///
    /// - Parameter toolName: The name of the tool.
    /// - Returns: The assigned risk level.
    public func riskLevel(for toolName: String) -> ColonyToolRiskLevel {
        if let override = riskOverrides[toolName] {
            return override
        }
        if let builtIn = Self.defaultRiskLevelForToolName[toolName] {
            return builtIn
        }
        return defaultRiskLevel
    }

    /// Assesses a batch of tool calls for safety and approval requirements.
    ///
    /// - Parameter toolCalls: The tool calls to assess.
    /// - Returns: An array of safety assessments for each tool call.
    public func assess(toolCalls: [ColonyToolCall]) -> [ColonyToolSafetyAssessment] {
        toolCalls.map { call in
            let riskLevel = riskLevel(for: call.name)

            if requiredApprovalRisks.contains(riskLevel) {
                return ColonyToolSafetyAssessment(
                    toolCallID: call.id,
                    toolName: call.name,
                    riskLevel: riskLevel,
                    requiresApproval: true,
                    reason: .mandatoryRiskLevel
                )
            }

            if permissionPolicy.requiresApproval(for: call.name) {
                let reason: ColonyToolApprovalRequirementReason = {
                    switch permissionPolicy {
                    case .unrestricted:
                        return .policyAlways
                    case .requireApproval:
                        return .policyAlways
                    case .allowList:
                        return .policyNotAllowListed
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

    /// Resolves the approval decision for a tool, checking rules if configured.
    ///
    /// - Parameters:
    ///   - toolName: The name of the tool.
    ///   - consumeOneShot: Whether to consume one-shot rules after use.
    /// - Returns: The matched rule decision, if any.
    public func resolveDecision(for toolName: String, consumeOneShot: Bool) async throws -> ColonyMatchedToolApprovalRule? {
        guard let rules = approvalRules else {
            return nil
        }
        return try await rules.resolveDecision(forToolName: toolName, consumeOneShot: consumeOneShot)
    }
}

// MARK: - Permission Policy

/// Determines which tools require approval based on permission settings.
public enum ToolPermissionPolicy: Sendable, Equatable {
    /// No tools require approval (use with caution).
    case unrestricted

    /// All tools require approval.
    case requireApproval

    /// Only tools not in the allow list require approval.
    case allowList(Set<String>)

    /// Creates an allow-list policy from an array of tool names.
    ///
    /// - Parameter allowed: The tools that do not require approval.
    /// - Returns: An allow-list policy.
    public static func allowList(_ allowed: [String]) -> ToolPermissionPolicy {
        .allowList(Set(allowed))
    }

    /// Determines if a specific tool requires approval under this policy.
    ///
    /// - Parameter toolName: The name of the tool to check.
    /// - Returns: `true` if the tool requires approval.
    public func requiresApproval(for toolName: String) -> Bool {
        switch self {
        case .unrestricted:
            return false
        case .requireApproval:
            return true
        case .allowList(let allowed):
            return !allowed.contains(toolName)
        }
    }

    /// Determines if any tool in the list requires approval.
    ///
    /// - Parameter toolNames: The names of the tools to check.
    /// - Returns: `true` if any tool requires approval.
    public func requiresApproval(for toolNames: [String]) -> Bool {
        toolNames.contains(where: requiresApproval(for:))
    }
}

// MARK: - Default Risk Levels

extension ColonyToolPolicy {
    /// Default risk levels for built-in Colony tools.
    private static let defaultRiskLevelForToolName: [String: ColonyToolRiskLevel] = [
        // Read-only tools
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

        // State mutation tools (agent-local state)
        ColonyBuiltInToolDefinitions.writeTodos.name: .stateMutation,
        ColonyBuiltInToolDefinitions.scratchAdd.name: .stateMutation,
        ColonyBuiltInToolDefinitions.scratchUpdate.name: .stateMutation,
        ColonyBuiltInToolDefinitions.scratchComplete.name: .stateMutation,
        ColonyBuiltInToolDefinitions.scratchPin.name: .stateMutation,
        ColonyBuiltInToolDefinitions.scratchUnpin.name: .stateMutation,
        ColonyBuiltInToolDefinitions.memoryRemember.name: .stateMutation,

        // Mutation tools (filesystem/workspace changes)
        ColonyBuiltInToolDefinitions.writeFile.name: .mutation,
        ColonyBuiltInToolDefinitions.editFile.name: .mutation,
        ColonyBuiltInToolDefinitions.gitCommit.name: .mutation,
        ColonyBuiltInToolDefinitions.gitBranch.name: .mutation,
        ColonyBuiltInToolDefinitions.lspApplyEdit.name: .mutation,
        ColonyBuiltInToolDefinitions.applyPatch.name: .mutation,

        // Execution tools (code execution)
        ColonyBuiltInToolDefinitions.execute.name: .execution,
        ColonyBuiltInToolDefinitions.shellOpen.name: .execution,
        ColonyBuiltInToolDefinitions.shellWrite.name: .execution,
        ColonyBuiltInToolDefinitions.shellClose.name: .execution,
        ColonyBuiltInToolDefinitions.taskName: .execution,

        // Network tools (external communication)
        ColonyBuiltInToolDefinitions.gitPush.name: .network,
        ColonyBuiltInToolDefinitions.gitPreparePR.name: .network,
        ColonyBuiltInToolDefinitions.webSearch.name: .network,
        ColonyBuiltInToolDefinitions.codeSearch.name: .network,
        ColonyBuiltInToolDefinitions.pluginInvoke.name: .network,

        // External tool aliases
        "tavily_search": .network,
        "tavily_extract": .network,
    ]
}

// MARK: - Convenience Extensions

extension ColonyToolPolicy {
    /// Creates a permissive policy that allows all tools without approval.
    /// Use with caution - suitable only for highly trusted environments.
    public static var unrestricted: ColonyToolPolicy {
        ColonyToolPolicy(
            permissionPolicy: .unrestricted,
            requiredApprovalRisks: [.execution, .network]
        )
    }

    /// Creates a strict policy that requires approval for all tools.
    public static var strict: ColonyToolPolicy {
        ColonyToolPolicy(
            permissionPolicy: .requireApproval,
            requiredApprovalRisks: [.mutation, .execution, .network]
        )
    }

    /// Creates a default policy with standard allow-list behavior.
    public static var `default`: ColonyToolPolicy {
        ColonyToolPolicy()
    }
}
