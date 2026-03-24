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
    public var subagentType: ColonySubagentType
    public var context: ColonySubagentContext?
    public var fileReferences: [ColonySubagentFileReference]

    public init(
        prompt: String,
        subagentType: ColonySubagentType,
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

// MARK: - Service Protocol

/// Request type for creating a subagent task.
/// This is a typealias for backward compatibility with `ColonySubagentRequest`.
public typealias ColonySubagentTaskRequest = ColonySubagentRequest

/// Response type for a subagent task.
/// This is a typealias for backward compatibility with `ColonySubagentResult`.
public typealias ColonySubagentTaskResponse = ColonySubagentResult

/// Service protocol for subagent task operations.
///
/// This protocol defines the service interface for creating and running subagent tasks.
/// Implementations provide the actual subagent execution logic, while consumers depend
/// on this abstract interface.
///
/// Migration from `ColonySubagentRegistry`:
/// - Replace `ColonySubagentRegistry` with `ColonySubagentService` in new code
/// - Use `createTask` instead of `run`
/// - The request/response types remain compatible through typealiases
public protocol ColonySubagentService: Sendable {
    /// Create and run a subagent task with the given request.
    /// - Parameter request: The task request containing prompt, subagent type, and context
    /// - Returns: The task response with the subagent's output content
    func createTask(_ request: ColonySubagentTaskRequest) async throws -> ColonySubagentTaskResponse
}

// MARK: - Legacy Registry Protocol (Deprecated)

/// Registry protocol for subagent management.
///
/// > Deprecated: Use `ColonySubagentService` instead. This protocol will be removed in a future version.
///
/// The registry protocol extends `ColonySubagentService` with subagent listing capabilities.
/// For simple task delegation, migrate to `ColonySubagentService`.
@available(*, deprecated, renamed: "ColonySubagentService", message: "Use ColonySubagentService instead. Listing methods are being moved to a separate protocol.")
public protocol ColonySubagentRegistry: ColonySubagentService {
    func listSubagents() -> [ColonySubagentDescriptor]
    func run(_ request: ColonySubagentRequest) async throws -> ColonySubagentResult
}

public extension ColonySubagentRegistry {
    /// Default implementation of `ColonySubagentService.createTask` that delegates to `run`.
    func createTask(_ request: ColonySubagentTaskRequest) async throws -> ColonySubagentTaskResponse {
        try await run(request)
    }
}
