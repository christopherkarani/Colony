import HiveCore

public struct ColonyConfiguration: Sendable {
    public var capabilities: ColonyCapabilities
    public var modelName: String
    public var structuredOutput: HiveStructuredOutputFormat?
    public var toolApprovalPolicy: ColonyToolApprovalPolicy
    public var toolApprovalRuleStore: (any ColonyToolApprovalRuleStore)?
    public var toolRiskLevelOverrides: [String: ColonyToolRiskLevel]
    public var toolPolicyMetadataByName: [String: ColonyToolPolicyMetadata]
    public var mandatoryApprovalRiskLevels: Set<ColonyToolRiskLevel>
    public var defaultToolRiskLevel: ColonyToolRiskLevel
    public var toolAuditRecorder: ColonyToolAuditRecorder?
    public var compactionPolicy: ColonyCompactionPolicy
    public var scratchbookPolicy: ColonyScratchbookPolicy
    public var toolPromptStrategy: ColonyToolPromptStrategy
    public var memorySources: [ColonyVirtualPath]
    public var skillSources: [ColonyVirtualPath]
    public var summarizationPolicy: ColonySummarizationPolicy?
    public var requestHardTokenLimit: Int?
    public var toolResultEvictionTokenLimit: Int?
    public var systemPromptMemoryTokenLimit: Int?
    public var systemPromptSkillsTokenLimit: Int?
    public var additionalSystemPrompt: String?

    public init(
        capabilities: ColonyCapabilities = .default,
        modelName: String,
        structuredOutput: HiveStructuredOutputFormat? = nil,
        toolApprovalPolicy: ColonyToolApprovalPolicy = .allowList(["ls", "read_file", "glob", "grep", "read_todos", "write_todos"]),
        toolApprovalRuleStore: (any ColonyToolApprovalRuleStore)? = nil,
        toolRiskLevelOverrides: [String: ColonyToolRiskLevel] = [:],
        toolPolicyMetadataByName: [String: ColonyToolPolicyMetadata] = [:],
        mandatoryApprovalRiskLevels: Set<ColonyToolRiskLevel> = [.mutation, .execution, .network],
        defaultToolRiskLevel: ColonyToolRiskLevel = .readOnly,
        toolAuditRecorder: ColonyToolAuditRecorder? = nil,
        compactionPolicy: ColonyCompactionPolicy = .maxTokens(12_000),
        scratchbookPolicy: ColonyScratchbookPolicy = ColonyScratchbookPolicy(),
        toolPromptStrategy: ColonyToolPromptStrategy = .automatic,
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
        self.structuredOutput = structuredOutput
        self.toolApprovalPolicy = toolApprovalPolicy
        self.toolApprovalRuleStore = toolApprovalRuleStore
        self.toolRiskLevelOverrides = toolRiskLevelOverrides
        self.toolPolicyMetadataByName = toolPolicyMetadataByName
        self.mandatoryApprovalRiskLevels = mandatoryApprovalRiskLevels
        self.defaultToolRiskLevel = defaultToolRiskLevel
        self.toolAuditRecorder = toolAuditRecorder
        self.compactionPolicy = compactionPolicy
        self.scratchbookPolicy = scratchbookPolicy
        self.toolPromptStrategy = toolPromptStrategy
        self.additionalSystemPrompt = additionalSystemPrompt
        self.memorySources = memorySources
        self.skillSources = skillSources
        self.summarizationPolicy = summarizationPolicy
        self.requestHardTokenLimit = requestHardTokenLimit
        self.toolResultEvictionTokenLimit = toolResultEvictionTokenLimit
        self.systemPromptMemoryTokenLimit = systemPromptMemoryTokenLimit
        self.systemPromptSkillsTokenLimit = systemPromptSkillsTokenLimit
    }

    @available(*, deprecated, message: "Use toolPromptStrategy instead.")
    public var includeToolListInSystemPrompt: Bool {
        get { toolPromptStrategy == .includeInSystemPrompt }
        set { toolPromptStrategy = newValue ? .includeInSystemPrompt : .omitFromSystemPrompt }
    }
}
