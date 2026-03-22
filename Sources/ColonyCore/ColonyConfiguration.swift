/// The complete configuration for a Colony runtime, organized into four groups.
///
/// `ColonyConfiguration` is the top-level configuration object passed to `Colony.agent(model:)`.
///
/// ## Configuration Tiers
///
/// Colony provides three initialization tiers for increasing control:
///
/// ```swift
/// // Tier 1 — Minimal (model name only)
/// let config = ColonyConfiguration(modelName: .claudeSonnet)
///
/// // Tier 2 — Common (capabilities + tool approval)
/// let config = ColonyConfiguration(
///     modelName: .claudeSonnet,
///     capabilities: [.filesystem, .shell, .git],
///     toolApprovalPolicy: .allowList([.ls, .readFile, .glob])
/// )
///
/// // Tier 3 — Full control (all nested groups)
/// let config = ColonyConfiguration(
///     model: ModelConfiguration(name: .claudeSonnet, capabilities: .default),
///     safety: SafetyConfiguration(...),
///     context: ContextConfiguration(...),
///     prompts: PromptConfiguration(...)
/// )
/// ```
public struct ColonyConfiguration: Sendable {
    public var model: ModelConfiguration
    public var safety: SafetyConfiguration
    public var context: ContextConfiguration
    public var prompts: PromptConfiguration

    // MARK: - Tier 1: Minimal init
    public init(modelName: ColonyModelName) {
        self.model = ModelConfiguration(name: modelName)
        self.safety = .default
        self.context = .default
        self.prompts = .default
    }

    // MARK: - Tier 2: Common customization
    public init(
        modelName: ColonyModelName,
        capabilities: ColonyAgentCapabilities = .default,
        toolApprovalPolicy: ColonyToolApproval.Policy = .allowList([.ls, .readFile, .glob, .grep, .readTodos, .writeTodos]),
        structuredOutput: ColonyStructuredOutput? = nil
    ) {
        self.model = ModelConfiguration(name: modelName, capabilities: capabilities, structuredOutput: structuredOutput)
        self.safety = SafetyConfiguration(toolApprovalPolicy: toolApprovalPolicy)
        self.context = .default
        self.prompts = .default
    }

    // MARK: - Tier 3: Full control
    public init(
        model: ModelConfiguration,
        safety: SafetyConfiguration = .default,
        context: ContextConfiguration = .default,
        prompts: PromptConfiguration = .default
    ) {
        self.model = model
        self.safety = safety
        self.context = context
        self.prompts = prompts
    }

    // MARK: - Nested Configuration Groups

    /// Configuration for the AI model used by the runtime.
    ///
    /// Controls which model runs, what capabilities it supports (native tool calling,
    /// structured outputs), and which agent capabilities are enabled.
    public struct ModelConfiguration: Sendable {
        public var name: ColonyModelName
        public var capabilities: ColonyAgentCapabilities
        public var structuredOutput: ColonyStructuredOutput?

        public init(
            name: ColonyModelName,
            capabilities: ColonyAgentCapabilities = .default,
            structuredOutput: ColonyStructuredOutput? = nil
        ) {
            self.name = name
            self.capabilities = capabilities
            self.structuredOutput = structuredOutput
        }
    }

    /// Configuration for tool safety, approval policies, and audit logging.
    ///
    /// Safety settings control:
    /// - Which tools require human approval before execution (`toolApprovalPolicy`)
    /// - Risk levels per tool (`toolRiskLevelOverrides`, `toolPolicyMetadataByName`)
    /// - Which risk levels always require approval regardless of policy (`mandatoryApprovalRiskLevels`)
    /// - Tool audit trail recording (`toolAuditRecorder`)
    ///
    /// The default safety configuration auto-approves read-only and planning tools,
    /// and requires approval for mutation, execution, and network tools.
    public struct SafetyConfiguration: Sendable {
        public var toolApprovalPolicy: ColonyToolApproval.Policy
        public var toolApprovalRuleStore: (any ColonyToolApprovalRuleStore)?
        public var toolRiskLevelOverrides: [ColonyTool.Name: ColonyTool.RiskLevel]
        public var toolPolicyMetadataByName: [ColonyTool.Name: ColonyTool.PolicyMetadata]
        public var mandatoryApprovalRiskLevels: Set<ColonyTool.RiskLevel>
        public var defaultToolRiskLevel: ColonyTool.RiskLevel
        public var toolAuditRecorder: ColonyToolAudit.Recorder?

        public static let `default` = SafetyConfiguration()

        public init(
            toolApprovalPolicy: ColonyToolApproval.Policy = .allowList([.ls, .readFile, .glob, .grep, .readTodos, .writeTodos]),
            toolApprovalRuleStore: (any ColonyToolApprovalRuleStore)? = nil,
            toolRiskLevelOverrides: [ColonyTool.Name: ColonyTool.RiskLevel] = [:],
            toolPolicyMetadataByName: [ColonyTool.Name: ColonyTool.PolicyMetadata] = [:],
            mandatoryApprovalRiskLevels: Set<ColonyTool.RiskLevel> = [.mutation, .execution, .network],
            defaultToolRiskLevel: ColonyTool.RiskLevel = .readOnly,
            toolAuditRecorder: ColonyToolAudit.Recorder? = nil
        ) {
            self.toolApprovalPolicy = toolApprovalPolicy
            self.toolApprovalRuleStore = toolApprovalRuleStore
            self.toolRiskLevelOverrides = toolRiskLevelOverrides
            self.toolPolicyMetadataByName = toolPolicyMetadataByName
            self.mandatoryApprovalRiskLevels = mandatoryApprovalRiskLevels
            self.defaultToolRiskLevel = defaultToolRiskLevel
            self.toolAuditRecorder = toolAuditRecorder
        }
    }

    /// Configuration for context management, compaction, and summarization.
    ///
    /// Controls:
    /// - When context is compacted (`compactionPolicy`)
    /// - Scratchbook behavior (`scratchbookPolicy`)
    /// - Whether and how messages are summarized (`summarizationPolicy`)
    /// - Hard token limits (`requestHardTokenLimit`, `toolResultEvictionTokenLimit`)
    public struct ContextConfiguration: Sendable {
        public var compactionPolicy: ColonyCompactionPolicy
        public var scratchbookPolicy: ColonyScratchbookPolicy
        public var summarizationPolicy: ColonySummarizationPolicy?
        public var requestHardTokenLimit: Int?
        public var toolResultEvictionTokenLimit: Int?

        public static let `default` = ContextConfiguration()

        public init(
            compactionPolicy: ColonyCompactionPolicy = .maxTokens(12_000),
            scratchbookPolicy: ColonyScratchbookPolicy = ColonyScratchbookPolicy(),
            summarizationPolicy: ColonySummarizationPolicy? = nil,
            requestHardTokenLimit: Int? = nil,
            toolResultEvictionTokenLimit: Int? = 20_000
        ) {
            self.compactionPolicy = compactionPolicy
            self.scratchbookPolicy = scratchbookPolicy
            self.summarizationPolicy = summarizationPolicy
            self.requestHardTokenLimit = requestHardTokenLimit
            self.toolResultEvictionTokenLimit = toolResultEvictionTokenLimit
        }
    }

    /// Configuration for system prompts, tool prompt injection, and memory sources.
    ///
    /// Controls:
    /// - How tools are represented in prompts (`toolPromptStrategy`)
    /// - Additional system prompt content (`additionalSystemPrompt`)
    /// - Which memory files are injected (`memorySources`)
    /// - Which skill files are injected (`skillSources`)
    public struct PromptConfiguration: Sendable {
        public var toolPromptStrategy: ColonyTool.PromptStrategy
        public var additionalSystemPrompt: String?
        public var memorySources: [ColonyFileSystem.VirtualPath]
        public var skillSources: [ColonyFileSystem.VirtualPath]
        public var systemPromptMemoryTokenLimit: Int?
        public var systemPromptSkillsTokenLimit: Int?

        public static let `default` = PromptConfiguration()

        public init(
            toolPromptStrategy: ColonyTool.PromptStrategy = .automatic,
            additionalSystemPrompt: String? = nil,
            memorySources: [ColonyFileSystem.VirtualPath] = [],
            skillSources: [ColonyFileSystem.VirtualPath] = [],
            systemPromptMemoryTokenLimit: Int? = nil,
            systemPromptSkillsTokenLimit: Int? = nil
        ) {
            self.toolPromptStrategy = toolPromptStrategy
            self.additionalSystemPrompt = additionalSystemPrompt
            self.memorySources = memorySources
            self.skillSources = skillSources
            self.systemPromptMemoryTokenLimit = systemPromptMemoryTokenLimit
            self.systemPromptSkillsTokenLimit = systemPromptSkillsTokenLimit
        }
    }
}
