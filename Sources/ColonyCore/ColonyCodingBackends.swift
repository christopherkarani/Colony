// MARK: - ColonyPatch Namespace

public enum ColonyPatch {}

extension ColonyPatch {
    public struct Result: Sendable, Codable, Equatable {
        public var success: Bool
        public var summary: String

        public init(success: Bool, summary: String) {
            self.success = success
            self.summary = summary
        }
    }
}

public protocol ColonyApplyPatchBackend: Sendable {
    func applyPatch(_ patch: String) async throws -> ColonyPatch.Result
}

// MARK: - ColonyWebSearch Namespace

public enum ColonyWebSearch {}

extension ColonyWebSearch {
    public struct ResultItem: Sendable, Codable, Equatable {
        public var title: String
        public var url: String
        public var snippet: String

        public init(title: String, url: String, snippet: String) {
            self.title = title
            self.url = url
            self.snippet = snippet
        }
    }

    public struct Result: Sendable, Codable, Equatable {
        public var items: [ColonyWebSearch.ResultItem]

        public init(items: [ColonyWebSearch.ResultItem]) {
            self.items = items
        }
    }
}

public protocol ColonyWebSearchBackend: Sendable {
    func search(query: String, limit: Int?) async throws -> ColonyWebSearch.Result
}

// MARK: - ColonyCodeSearch Namespace

public enum ColonyCodeSearch {}

extension ColonyCodeSearch {
    public struct Match: Sendable, Codable, Equatable {
        public var path: ColonyFileSystem.VirtualPath
        public var line: Int
        public var preview: String

        public init(path: ColonyFileSystem.VirtualPath, line: Int, preview: String) {
            self.path = path
            self.line = line
            self.preview = preview
        }
    }

    public struct Result: Sendable, Codable, Equatable {
        public var matches: [ColonyCodeSearch.Match]

        public init(matches: [ColonyCodeSearch.Match]) {
            self.matches = matches
        }
    }
}

public protocol ColonyCodeSearchBackend: Sendable {
    func search(query: String, path: ColonyFileSystem.VirtualPath?) async throws -> ColonyCodeSearch.Result
}

// MARK: - ColonyMCP Namespace

public enum ColonyMCP {}

extension ColonyMCP {
    public struct Resource: Sendable, Codable, Equatable {
        public var id: String
        public var name: String
        public var description: String?

        public init(id: String, name: String, description: String? = nil) {
            self.id = id
            self.name = name
            self.description = description
        }
    }
}

public protocol ColonyMCPBackend: Sendable {
    func listResources() async throws -> [ColonyMCP.Resource]
    func readResource(id: String) async throws -> String
}

public protocol ColonyPluginToolRegistry: Sendable {
    func listTools() -> [ColonyTool.Definition]
    func invoke(_ call: ColonyTool.Call) async throws -> ColonyTool.Result
}

