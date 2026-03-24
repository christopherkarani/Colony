import HiveCore

/// Result of applying a unified patch.
public struct ColonyApplyPatchResult: Sendable, Codable, Equatable {
    /// Whether the patch was applied successfully.
    public var success: Bool
    /// Human-readable summary of the result.
    public var summary: String

    public init(success: Bool, summary: String) {
        self.success = success
        self.summary = summary
    }
}

/// Protocol for applying unified patches to files.
public protocol ColonyApplyPatchBackend: Sendable {
    /// Applies a unified diff patch.
    ///
    /// - Parameter patch: The unified diff patch string
    /// - Returns: Result indicating success or failure
    func applyPatch(_ patch: String) async throws -> ColonyApplyPatchResult
}

/// A single web search result item.
public struct ColonyWebSearchResultItem: Sendable, Codable, Equatable {
    /// Title of the search result.
    public var title: String
    /// URL of the search result.
    public var url: String
    /// Snippet/description of the result.
    public var snippet: String

    public init(title: String, url: String, snippet: String) {
        self.title = title
        self.url = url
        self.snippet = snippet
    }
}

/// Response from a web search.
public struct ColonyWebSearchResult: Sendable, Codable, Equatable {
    /// The list of search result items.
    public var items: [ColonyWebSearchResultItem]

    public init(items: [ColonyWebSearchResultItem]) {
        self.items = items
    }
}

/// Protocol for web search operations.
public protocol ColonyWebSearchBackend: Sendable {
    /// Searches the web for the given query.
    ///
    /// - Parameters:
    ///   - query: The search query
    ///   - limit: Optional maximum number of results
    /// - Returns: Search results
    func search(query: String, limit: Int?) async throws -> ColonyWebSearchResult
}

/// A single code search match.
public struct ColonyCodeSearchMatch: Sendable, Codable, Equatable {
    /// Path to the file containing the match.
    public var path: ColonyVirtualPath
    /// 1-based line number of the match.
    public var line: Int
    /// Preview text of the matching line.
    public var preview: String

    public init(path: ColonyVirtualPath, line: Int, preview: String) {
        self.path = path
        self.line = line
        self.preview = preview
    }
}

/// Response from a code search.
public struct ColonyCodeSearchResult: Sendable, Codable, Equatable {
    /// The matching code locations.
    public var matches: [ColonyCodeSearchMatch]

    public init(matches: [ColonyCodeSearchMatch]) {
        self.matches = matches
    }
}

/// Protocol for code search operations.
public protocol ColonyCodeSearchBackend: Sendable {
    /// Searches code for the given query.
    ///
    /// - Parameters:
    ///   - query: The code search query
    ///   - path: Optional path to search within
    /// - Returns: Search results
    func search(query: String, path: ColonyVirtualPath?) async throws -> ColonyCodeSearchResult
}

/// A resource exposed by an MCP (Model Context Protocol) server.
public struct ColonyMCPResource: Sendable, Codable, Equatable {
    /// Unique identifier for this resource.
    public var id: String
    /// Human-readable name of the resource.
    public var name: String
    /// Optional description of the resource.
    public var description: String?

    public init(id: String, name: String, description: String? = nil) {
        self.id = id
        self.name = name
        self.description = description
    }
}

/// Protocol for MCP (Model Context Protocol) operations.
public protocol ColonyMCPBackend: Sendable {
    /// Lists all available resources from the MCP server.
    func listResources() async throws -> [ColonyMCPResource]
    /// Reads a resource by its ID.
    func readResource(id: String) async throws -> String
}

/// Protocol for plugin tool registry operations.
public protocol ColonyPluginToolRegistry: Sendable {
    /// Lists all tools available from this plugin registry.
    func listTools() -> [HiveToolDefinition]
    /// Invokes a plugin tool by name with the given arguments.
    func invoke(name: String, argumentsJSON: String) async throws -> String
}
