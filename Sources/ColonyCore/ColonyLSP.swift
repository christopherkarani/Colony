// MARK: - ColonyLSP Namespace

public enum ColonyLSP {}

// MARK: - Position

extension ColonyLSP {
    public struct Position: Sendable, Equatable, Codable {
        public var line: Int
        public var character: Int

        public init(line: Int, character: Int) {
            self.line = line
            self.character = character
        }
    }
}

// MARK: - Range

extension ColonyLSP {
    public struct Range: Sendable, Equatable, Codable {
        public var start: Position
        public var end: Position

        public init(start: Position, end: Position) {
            self.start = start
            self.end = end
        }
    }
}

// MARK: - SymbolsRequest

extension ColonyLSP {
    public struct SymbolsRequest: Sendable, Equatable, Codable {
        public var path: ColonyFileSystem.VirtualPath?
        public var query: String?

        public init(path: ColonyFileSystem.VirtualPath? = nil, query: String? = nil) {
            self.path = path
            self.query = query
        }
    }
}

// MARK: - Symbol

extension ColonyLSP {
    public struct Symbol: Sendable, Equatable, Codable {
        public enum Kind: String, Sendable, Codable, CaseIterable {
            case file
            case module
            case namespace
            case package
            case `class`
            case method
            case property
            case field
            case constructor
            case `enum`
            case interface
            case function
            case variable
            case constant
            case string
            case number
            case boolean
            case array
            case object
            case key
            case null
            case enumMember = "enum_member"
            case `struct`
            case event
            case `operator`
            case typeParameter = "type_parameter"
            case unknown
        }

        public var name: String
        public var kind: Kind
        public var path: ColonyFileSystem.VirtualPath
        public var range: ColonyLSP.Range

        public init(name: String, kind: Kind, path: ColonyFileSystem.VirtualPath, range: ColonyLSP.Range) {
            self.name = name
            self.kind = kind
            self.path = path
            self.range = range
        }
    }
}

// MARK: - DiagnosticsRequest

extension ColonyLSP {
    public struct DiagnosticsRequest: Sendable, Equatable, Codable {
        public var path: ColonyFileSystem.VirtualPath?

        public init(path: ColonyFileSystem.VirtualPath? = nil) {
            self.path = path
        }
    }
}

// MARK: - Diagnostic

extension ColonyLSP {
    public struct Diagnostic: Sendable, Equatable, Codable {
        public enum Severity: String, Sendable, Codable, CaseIterable {
            case error
            case warning
            case information
            case hint
        }

        public var path: ColonyFileSystem.VirtualPath
        public var range: ColonyLSP.Range
        public var severity: Severity
        public var message: String
        public var code: String?

        public init(
            path: ColonyFileSystem.VirtualPath,
            range: ColonyLSP.Range,
            severity: Severity,
            message: String,
            code: String? = nil
        ) {
            self.path = path
            self.range = range
            self.severity = severity
            self.message = message
            self.code = code
        }
    }
}

// MARK: - ReferencesRequest

extension ColonyLSP {
    public struct ReferencesRequest: Sendable, Equatable, Codable {
        public var path: ColonyFileSystem.VirtualPath
        public var position: ColonyLSP.Position
        public var includeDeclaration: Bool

        public init(
            path: ColonyFileSystem.VirtualPath,
            position: ColonyLSP.Position,
            includeDeclaration: Bool = true
        ) {
            self.path = path
            self.position = position
            self.includeDeclaration = includeDeclaration
        }
    }
}

// MARK: - Reference

extension ColonyLSP {
    public struct Reference: Sendable, Equatable, Codable {
        public var path: ColonyFileSystem.VirtualPath
        public var range: ColonyLSP.Range
        public var preview: String?

        public init(path: ColonyFileSystem.VirtualPath, range: ColonyLSP.Range, preview: String? = nil) {
            self.path = path
            self.range = range
            self.preview = preview
        }
    }
}

// MARK: - TextEdit

extension ColonyLSP {
    public struct TextEdit: Sendable, Equatable, Codable {
        public var path: ColonyFileSystem.VirtualPath
        public var range: ColonyLSP.Range
        public var newText: String

        public init(path: ColonyFileSystem.VirtualPath, range: ColonyLSP.Range, newText: String) {
            self.path = path
            self.range = range
            self.newText = newText
        }
    }
}

// MARK: - ApplyEditRequest

extension ColonyLSP {
    public struct ApplyEditRequest: Sendable, Equatable, Codable {
        public var edits: [TextEdit]

        public init(edits: [TextEdit]) {
            self.edits = edits
        }
    }
}

// MARK: - ApplyEditResult

extension ColonyLSP {
    public struct ApplyEditResult: Sendable, Equatable, Codable {
        public var appliedEditCount: Int
        public var summary: String?

        public init(appliedEditCount: Int, summary: String? = nil) {
            self.appliedEditCount = appliedEditCount
            self.summary = summary
        }
    }
}

// MARK: - ColonyLSPBackend Protocol (top-level)

public protocol ColonyLSPBackend: Sendable {
    func symbols(_ request: ColonyLSP.SymbolsRequest) async throws -> [ColonyLSP.Symbol]
    func diagnostics(_ request: ColonyLSP.DiagnosticsRequest) async throws -> [ColonyLSP.Diagnostic]
    func references(_ request: ColonyLSP.ReferencesRequest) async throws -> [ColonyLSP.Reference]
    func applyEdit(_ request: ColonyLSP.ApplyEditRequest) async throws -> ColonyLSP.ApplyEditResult
}

