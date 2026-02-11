import HiveCore

public struct ColonyApplyPatchResult: Sendable, Codable, Equatable {
    public var success: Bool
    public var summary: String

    public init(success: Bool, summary: String) {
        self.success = success
        self.summary = summary
    }
}

public protocol ColonyApplyPatchBackend: Sendable {
    func applyPatch(_ patch: String) async throws -> ColonyApplyPatchResult
}

public struct ColonyWebSearchResultItem: Sendable, Codable, Equatable {
    public var title: String
    public var url: String
    public var snippet: String

    public init(title: String, url: String, snippet: String) {
        self.title = title
        self.url = url
        self.snippet = snippet
    }
}

public struct ColonyWebSearchResult: Sendable, Codable, Equatable {
    public var items: [ColonyWebSearchResultItem]

    public init(items: [ColonyWebSearchResultItem]) {
        self.items = items
    }
}

public protocol ColonyWebSearchBackend: Sendable {
    func search(query: String, limit: Int?) async throws -> ColonyWebSearchResult
}

public struct ColonyCodeSearchMatch: Sendable, Codable, Equatable {
    public var path: ColonyVirtualPath
    public var line: Int
    public var preview: String

    public init(path: ColonyVirtualPath, line: Int, preview: String) {
        self.path = path
        self.line = line
        self.preview = preview
    }
}

public struct ColonyCodeSearchResult: Sendable, Codable, Equatable {
    public var matches: [ColonyCodeSearchMatch]

    public init(matches: [ColonyCodeSearchMatch]) {
        self.matches = matches
    }
}

public protocol ColonyCodeSearchBackend: Sendable {
    func search(query: String, path: ColonyVirtualPath?) async throws -> ColonyCodeSearchResult
}

public struct ColonyMCPResource: Sendable, Codable, Equatable {
    public var id: String
    public var name: String
    public var description: String?

    public init(id: String, name: String, description: String? = nil) {
        self.id = id
        self.name = name
        self.description = description
    }
}

public protocol ColonyMCPBackend: Sendable {
    func listResources() async throws -> [ColonyMCPResource]
    func readResource(id: String) async throws -> String
}

public protocol ColonyPluginToolRegistry: Sendable {
    func listTools() -> [HiveToolDefinition]
    func invoke(name: String, argumentsJSON: String) async throws -> String
}
