public struct ColonySubagentDescriptor: Sendable, Codable, Equatable {
    public var name: String
    public var description: String

    public init(name: String, description: String) {
        self.name = name
        self.description = description
    }
}

public struct ColonySubagentContext: Sendable, Codable, Equatable {
    public var objective: String?
    public var constraints: [String]
    public var acceptanceCriteria: [String]
    public var notes: [String]

    public init(
        objective: String? = nil,
        constraints: [String] = [],
        acceptanceCriteria: [String] = [],
        notes: [String] = []
    ) {
        self.objective = objective
        self.constraints = constraints
        self.acceptanceCriteria = acceptanceCriteria
        self.notes = notes
    }

    private enum CodingKeys: String, CodingKey {
        case objective
        case constraints
        case acceptanceCriteria = "acceptance_criteria"
        case notes
    }

    private enum LegacyCodingKeys: String, CodingKey {
        case acceptanceCriteria = "acceptanceCriteria"
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let legacyContainer = try decoder.container(keyedBy: LegacyCodingKeys.self)

        self.objective = try container.decodeIfPresent(String.self, forKey: .objective)
        self.constraints = try container.decodeIfPresent([String].self, forKey: .constraints) ?? []
        self.acceptanceCriteria =
            try container.decodeIfPresent([String].self, forKey: .acceptanceCriteria)
            ?? legacyContainer.decodeIfPresent([String].self, forKey: .acceptanceCriteria)
            ?? []
        self.notes = try container.decodeIfPresent([String].self, forKey: .notes) ?? []
    }
}

public struct ColonySubagentFileReference: Sendable, Codable, Equatable {
    public var path: ColonyVirtualPath
    public var offset: Int?
    public var limit: Int?

    public init(
        path: ColonyVirtualPath,
        offset: Int? = nil,
        limit: Int? = nil
    ) {
        self.path = path
        self.offset = offset
        self.limit = limit
    }
}

public struct ColonySubagentRequest: Sendable, Equatable {
    public var prompt: String
    public var subagentType: String
    public var context: ColonySubagentContext?
    public var fileReferences: [ColonySubagentFileReference]

    public init(
        prompt: String,
        subagentType: String,
        context: ColonySubagentContext? = nil,
        fileReferences: [ColonySubagentFileReference] = []
    ) {
        self.prompt = prompt
        self.subagentType = subagentType
        self.context = context
        self.fileReferences = fileReferences
    }
}

public struct ColonySubagentResult: Sendable, Equatable {
    public var content: String

    public init(content: String) {
        self.content = content
    }
}

public protocol ColonySubagentRegistry: Sendable {
    func listSubagents() -> [ColonySubagentDescriptor]
    func run(_ request: ColonySubagentRequest) async throws -> ColonySubagentResult
}
