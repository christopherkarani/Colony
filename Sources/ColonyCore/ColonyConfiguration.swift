public struct ColonyConfiguration: Sendable {
    public var model: ModelConfiguration
    public var safety: SafetyConfiguration
    public var context: ContextConfiguration
    public var prompts: PromptConfiguration

    // MARK: - Tier 1: Minimal init
    public init(modelName: String) {
        self.model = ModelConfiguration(name: modelName)
        self.safety = .default
        self.context = .default
        self.prompts = .default
    }

    // MARK: - Tier 2: Common customization
    public init(
        modelName: String,
        capabilities: ColonyRuntimeCapabilities = .default,
        toolApprovalPolicy: ColonyToolApprovalPolicy = .allowList(["ls", "read_file", "glob", "grep", "read_todos", "write_todos"]),
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

    public struct ModelConfiguration: Sendable {
        public var name: String
        public var capabilities: ColonyRuntimeCapabilities
        public var structuredOutput: ColonyStructuredOutput?

        public init(
            name: String,
            capabilities: ColonyRuntimeCapabilities = .default,
            structuredOutput: ColonyStructuredOutput? = nil
        ) {
            self.name = name
            self.capabilities = capabilities
            self.structuredOutput = structuredOutput
        }
    }

    public struct SafetyConfiguration: Sendable {
        public var toolApprovalPolicy: ColonyToolApprovalPolicy
        public var toolApprovalRuleStore: (any ColonyToolApprovalRuleStore)?
        public var toolRiskLevelOverrides: [ColonyToolName: ColonyToolRiskLevel]
        public var toolPolicyMetadataByName: [ColonyToolName: ColonyToolPolicyMetadata]
        public var mandatoryApprovalRiskLevels: Set<ColonyToolRiskLevel>
        public var defaultToolRiskLevel: ColonyToolRiskLevel
        public var toolAuditRecorder: ColonyToolAuditRecorder?

        public static let `default` = SafetyConfiguration()

        public init(
            toolApprovalPolicy: ColonyToolApprovalPolicy = .allowList(["ls", "read_file", "glob", "grep", "read_todos", "write_todos"]),
            toolApprovalRuleStore: (any ColonyToolApprovalRuleStore)? = nil,
            toolRiskLevelOverrides: [ColonyToolName: ColonyToolRiskLevel] = [:],
            toolPolicyMetadataByName: [ColonyToolName: ColonyToolPolicyMetadata] = [:],
            mandatoryApprovalRiskLevels: Set<ColonyToolRiskLevel> = [.mutation, .execution, .network],
            defaultToolRiskLevel: ColonyToolRiskLevel = .readOnly,
            toolAuditRecorder: ColonyToolAuditRecorder? = nil
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

    public struct PromptConfiguration: Sendable {
        public var toolPromptStrategy: ColonyToolPromptStrategy
        public var additionalSystemPrompt: String?
        public var memorySources: [ColonyVirtualPath]
        public var skillSources: [ColonyVirtualPath]
        public var systemPromptMemoryTokenLimit: Int?
        public var systemPromptSkillsTokenLimit: Int?

        public static let `default` = PromptConfiguration()

        public init(
            toolPromptStrategy: ColonyToolPromptStrategy = .automatic,
            additionalSystemPrompt: String? = nil,
            memorySources: [ColonyVirtualPath] = [],
            skillSources: [ColonyVirtualPath] = [],
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
