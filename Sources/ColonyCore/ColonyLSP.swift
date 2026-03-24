public struct ColonyLSPPosition: Sendable, Equatable, Codable {
    public var line: Int
    public var character: Int

    public init(line: Int, character: Int) {
        self.line = line
        self.character = character
    }
}

public struct ColonyLSPRange: Sendable, Equatable, Codable {
    public var start: ColonyLSPPosition
    public var end: ColonyLSPPosition

    public init(start: ColonyLSPPosition, end: ColonyLSPPosition) {
        self.start = start
        self.end = end
    }
}

public struct ColonyLSPSymbolsRequest: Sendable, Equatable, Codable {
    public var path: ColonyVirtualPath?
    public var query: String?

    public init(path: ColonyVirtualPath? = nil, query: String? = nil) {
        self.path = path
        self.query = query
    }
}

public struct ColonyLSPSymbol: Sendable, Equatable, Codable {
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
    public var path: ColonyVirtualPath
    public var range: ColonyLSPRange

    public init(name: String, kind: Kind, path: ColonyVirtualPath, range: ColonyLSPRange) {
        self.name = name
        self.kind = kind
        self.path = path
        self.range = range
    }
}

public struct ColonyLSPDiagnosticsRequest: Sendable, Equatable, Codable {
    public var path: ColonyVirtualPath?

    public init(path: ColonyVirtualPath? = nil) {
        self.path = path
    }
}

public struct ColonyLSPDiagnostic: Sendable, Equatable, Codable {
    public enum Severity: String, Sendable, Codable, CaseIterable {
        case error
        case warning
        case information
        case hint
    }

    public var path: ColonyVirtualPath
    public var range: ColonyLSPRange
    public var severity: Severity
    public var message: String
    public var code: String?

    public init(
        path: ColonyVirtualPath,
        range: ColonyLSPRange,
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

public struct ColonyLSPReferencesRequest: Sendable, Equatable, Codable {
    public var path: ColonyVirtualPath
    public var position: ColonyLSPPosition
    public var includeDeclaration: Bool

    public init(
        path: ColonyVirtualPath,
        position: ColonyLSPPosition,
        includeDeclaration: Bool = true
    ) {
        self.path = path
        self.position = position
        self.includeDeclaration = includeDeclaration
    }
}

public struct ColonyLSPReference: Sendable, Equatable, Codable {
    public var path: ColonyVirtualPath
    public var range: ColonyLSPRange
    public var preview: String?

    public init(path: ColonyVirtualPath, range: ColonyLSPRange, preview: String? = nil) {
        self.path = path
        self.range = range
        self.preview = preview
    }
}

public struct ColonyLSPTextEdit: Sendable, Equatable, Codable {
    public var path: ColonyVirtualPath
    public var range: ColonyLSPRange
    public var newText: String

    public init(path: ColonyVirtualPath, range: ColonyLSPRange, newText: String) {
        self.path = path
        self.range = range
        self.newText = newText
    }
}

public struct ColonyLSPApplyEditRequest: Sendable, Equatable, Codable {
    public var edits: [ColonyLSPTextEdit]

    public init(edits: [ColonyLSPTextEdit]) {
        self.edits = edits
    }
}

public struct ColonyLSPApplyEditResult: Sendable, Equatable, Codable {
    public var appliedEditCount: Int
    public var summary: String?

    public init(appliedEditCount: Int, summary: String? = nil) {
        self.appliedEditCount = appliedEditCount
        self.summary = summary
    }
}

// MARK: - Response Types

public struct ColonyLSPSymbolsResponse: Sendable, Equatable, Codable {
    public var symbols: [ColonyLSPSymbol]

    public init(symbols: [ColonyLSPSymbol]) {
        self.symbols = symbols
    }
}

public struct ColonyLSPDiagnosticsResponse: Sendable, Equatable, Codable {
    public var diagnostics: [ColonyLSPDiagnostic]

    public init(diagnostics: [ColonyLSPDiagnostic]) {
        self.diagnostics = diagnostics
    }
}

public struct ColonyLSPReferencesResponse: Sendable, Equatable, Codable {
    public var references: [ColonyLSPReference]

    public init(references: [ColonyLSPReference]) {
        self.references = references
    }
}

// MARK: - ColonyLSPService Protocol

public protocol ColonyLSPService: Sendable {
    func findSymbols(_ request: ColonyLSPSymbolsRequest) async throws -> ColonyLSPSymbolsResponse
    func getDiagnostics(_ request: ColonyLSPDiagnosticsRequest) async throws -> ColonyLSPDiagnosticsResponse
    func findReferences(_ request: ColonyLSPReferencesRequest) async throws -> ColonyLSPReferencesResponse
    func applyEdit(_ request: ColonyLSPApplyEditRequest) async throws -> ColonyLSPApplyEditResult
}

// MARK: - Deprecated Backward Compatibility

@available(*, deprecated, renamed: "ColonyLSPService")
public typealias ColonyLSPBackend = ColonyLSPService

public extension ColonyLSPService {
    @available(*, deprecated, renamed: "findSymbols")
    func symbols(_ request: ColonyLSPSymbolsRequest) async throws -> [ColonyLSPSymbol] {
        let response = try await findSymbols(request)
        return response.symbols
    }

    @available(*, deprecated, renamed: "getDiagnostics")
    func diagnostics(_ request: ColonyLSPDiagnosticsRequest) async throws -> [ColonyLSPDiagnostic] {
        let response = try await getDiagnostics(request)
        return response.diagnostics
    }

    @available(*, deprecated, renamed: "findReferences")
    func references(_ request: ColonyLSPReferencesRequest) async throws -> [ColonyLSPReference] {
        let response = try await findReferences(request)
        return response.references
    }
}
