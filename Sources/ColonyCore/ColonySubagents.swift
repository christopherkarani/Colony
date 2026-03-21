/// Namespace for Colony subagent value types.
public enum ColonySubagent {}

// MARK: - Descriptor

extension ColonySubagent {
    public struct Descriptor: Sendable, Codable, Equatable {
        public var name: String
        public var description: String

        public init(name: String, description: String) {
            self.name = name
            self.description = description
        }
    }
}

// MARK: - Context

extension ColonySubagent {
    public struct Context: Sendable, Codable, Equatable {
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
}

// MARK: - FileReference

extension ColonySubagent {
    public struct FileReference: Sendable, Codable, Equatable {
        public var path: ColonyFileSystem.VirtualPath
        public var offset: Int?
        public var limit: Int?

        public init(
            path: ColonyFileSystem.VirtualPath,
            offset: Int? = nil,
            limit: Int? = nil
        ) {
            self.path = path
            self.offset = offset
            self.limit = limit
        }
    }
}

// MARK: - Request

extension ColonySubagent {
    public struct Request: Sendable, Equatable {
        public var prompt: String
        public var subagentType: ColonySubagentType
        public var context: ColonySubagent.Context?
        public var fileReferences: [ColonySubagent.FileReference]

        public init(
            prompt: String,
            subagentType: ColonySubagentType,
            context: ColonySubagent.Context? = nil,
            fileReferences: [ColonySubagent.FileReference] = []
        ) {
            self.prompt = prompt
            self.subagentType = subagentType
            self.context = context
            self.fileReferences = fileReferences
        }
    }
}

// MARK: - Result

extension ColonySubagent {
    public struct Result: Sendable, Equatable {
        public var content: String

        public init(content: String) {
            self.content = content
        }
    }
}

// MARK: - Registry (top-level protocol)

public protocol ColonySubagentRegistry: Sendable {
    func listSubagents() -> [ColonySubagent.Descriptor]
    func run(_ request: ColonySubagent.Request) async throws -> ColonySubagent.Result
}

