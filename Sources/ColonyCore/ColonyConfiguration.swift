public struct ColonyConfiguration: Sendable {
    public var capabilities: ColonyCapabilities
    public var modelName: String
    public var toolApprovalPolicy: ColonyToolApprovalPolicy
    public var compactionPolicy: ColonyCompactionPolicy
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
        toolApprovalPolicy: ColonyToolApprovalPolicy = .allowList(["ls", "read_file", "glob", "grep", "read_todos", "write_todos"]),
        compactionPolicy: ColonyCompactionPolicy = .maxTokens(12_000),
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
        self.compactionPolicy = compactionPolicy
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
