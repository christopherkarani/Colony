/// Configuration for a Colony agent runtime instance.
///
/// `ColonyConfiguration` bundles all settings that control an agent's behavior,
/// including enabled capabilities, tool approval policies, token budgets, and
/// external service integrations.
///
/// Example:
/// ```swift
/// let config = ColonyConfiguration(
///     capabilities: [.planning, .filesystem, .shell],
///     modelName: "claude-3-5-sonnet",
///     toolApprovalPolicy: .always,
///     compactionPolicy: .maxTokens(12_000)
/// )
/// ```
public struct ColonyConfiguration: Sendable {

    /// The set of capabilities enabled for this agent.
    ///
    /// Determines which tool families are available at runtime.
    public var capabilities: ColonyCapabilities

    /// The name of the model to use for completions.
    ///
    /// Format depends on the backend (e.g., "claude-3-5-sonnet", "gpt-4o").
    public var modelName: String

    /// Policy controlling when tool approval is required.
    ///
    /// See `ColonyToolApprovalPolicy` for available modes.
    public var toolApprovalPolicy: ColonyToolApprovalPolicy

    /// Optional custom rule store for per-tool approval decisions.
    ///
    /// When `nil`, only the `toolApprovalPolicy` is used.
    public var toolApprovalRuleStore: (any ColonyToolApprovalRuleStore)?

    /// Tool-specific risk level overrides.
    ///
    /// Keys are tool names, values are the effective risk level.
    /// Takes precedence over built-in defaults.
    public var toolRiskLevelOverrides: [String: ColonyToolRiskLevel]

    /// Risk levels that always require user approval regardless of policy.
    ///
    /// Default includes `.mutation`, `.execution`, and `.network`.
    public var mandatoryApprovalRiskLevels: Set<ColonyToolRiskLevel>

    /// Default risk level for tools without an override.
    ///
    /// Default is `.readOnly`.
    public var defaultToolRiskLevel: ColonyToolRiskLevel

    /// Optional recorder for tool audit events.
    public var toolAuditRecorder: ColonyToolAuditRecorder?

    /// Policy governing when and how conversation history is compacted.
    ///
    /// Default is `.maxTokens(12_000)`.
    public var compactionPolicy: ColonyCompactionPolicy

    /// Policy governing scratchpad behavior.
    ///
    /// Default is a fresh `ColonyScratchbookPolicy()`.
    public var scratchbookPolicy: ColonyScratchbookPolicy

    /// Whether to include the tool list in the system prompt.
    ///
    /// When `true`, the agent receives a description of all available tools.
    public var includeToolListInSystemPrompt: Bool

    /// Virtual paths to memory resources to inject into the system prompt.
    ///
    /// These files are read and included as context at prompt construction time.
    public var memorySources: [ColonyVirtualPath]

    /// Virtual paths to skill definition files to inject into the system prompt.
    ///
    /// These files contain skill definitions that augment the agent's capabilities.
    public var skillSources: [ColonyVirtualPath]

    /// Optional policy for conversation summarization.
    ///
    /// When `nil`, summarization is disabled.
    public var summarizationPolicy: ColonySummarizationPolicy?

    /// Hard token limit for a single request.
    ///
    /// When set, requests exceeding this limit will fail with `ColonyBudgetError`.
    public var requestHardTokenLimit: Int?

    /// Token limit for tool results before eviction.
    ///
    /// Tool results exceeding this limit are evicted from context first.
    /// Default is 20,000.
    public var toolResultEvictionTokenLimit: Int?

    /// Token budget for memory sources in the system prompt.
    ///
    /// When `nil`, memory sources are included in full (subject to `requestHardTokenLimit`).
    public var systemPromptMemoryTokenLimit: Int?

    /// Token budget for skill sources in the system prompt.
    ///
    /// When `nil`, skill sources are included in full (subject to `requestHardTokenLimit`).
    public var systemPromptSkillsTokenLimit: Int?

    /// Additional text to append to the system prompt.
    ///
    /// Use for agent-specific instructions or customization.
    public var additionalSystemPrompt: String?

    public init(
        capabilities: ColonyCapabilities = .default,
        modelName: String,
        toolApprovalPolicy: ColonyToolApprovalPolicy = .allowList(["ls", "read_file", "glob", "grep", "read_todos", "write_todos"]),
        toolApprovalRuleStore: (any ColonyToolApprovalRuleStore)? = nil,
        toolRiskLevelOverrides: [String: ColonyToolRiskLevel] = [:],
        mandatoryApprovalRiskLevels: Set<ColonyToolRiskLevel> = [.mutation, .execution, .network],
        defaultToolRiskLevel: ColonyToolRiskLevel = .readOnly,
        toolAuditRecorder: ColonyToolAuditRecorder? = nil,
        compactionPolicy: ColonyCompactionPolicy = .maxTokens(12_000),
        scratchbookPolicy: ColonyScratchbookPolicy = ColonyScratchbookPolicy(),
        includeToolListInSystemPrompt: Bool = true,
        additionalSystemPrompt: String? = nil,
        memorySources: [ColonyVirtualPath] = [],
        skillSources: [ColonyVirtualPath] = [],
        summarizationPolicy: ColonySummarizationPolicy? = nil,
        requestHardTokenLimit: Int? = nil,
        toolResultEvictionTokenLimit: Int? = 20_000,
        systemPromptMemoryTokenLimit: Int? = nil,
        systemPromptSkillsTokenLimit: Int? = nil
    ) {
        self.capabilities = capabilities
        self.modelName = modelName
        self.toolApprovalPolicy = toolApprovalPolicy
        self.toolApprovalRuleStore = toolApprovalRuleStore
        self.toolRiskLevelOverrides = toolRiskLevelOverrides
        self.mandatoryApprovalRiskLevels = mandatoryApprovalRiskLevels
        self.defaultToolRiskLevel = defaultToolRiskLevel
        self.toolAuditRecorder = toolAuditRecorder
        self.compactionPolicy = compactionPolicy
        self.scratchbookPolicy = scratchbookPolicy
        self.includeToolListInSystemPrompt = includeToolListInSystemPrompt
        self.additionalSystemPrompt = additionalSystemPrompt
        self.memorySources = memorySources
        self.skillSources = skillSources
        self.summarizationPolicy = summarizationPolicy
        self.requestHardTokenLimit = requestHardTokenLimit
        self.toolResultEvictionTokenLimit = toolResultEvictionTokenLimit
        self.systemPromptMemoryTokenLimit = systemPromptMemoryTokenLimit
        self.systemPromptSkillsTokenLimit = systemPromptSkillsTokenLimit
    }
}
