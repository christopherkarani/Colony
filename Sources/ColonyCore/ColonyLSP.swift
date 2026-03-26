/// A position in a source file (0-indexed line and character).
public struct ColonyLSPPosition: Sendable, Equatable, Codable {
    /// 0-indexed line number.
    public var line: Int
    /// 0-indexed character offset within the line.
    public var character: Int

    public init(line: Int, character: Int) {
        self.line = line
        self.character = character
    }
}

/// A range in a source file, defined by start and end positions.
public struct ColonyLSPRange: Sendable, Equatable, Codable {
    /// Start position (inclusive).
    public var start: ColonyLSPPosition
    /// End position (exclusive).
    public var end: ColonyLSPPosition

    public init(start: ColonyLSPPosition, end: ColonyLSPPosition) {
        self.start = start
        self.end = end
    }
}

/// Request to search for symbols (functions, classes, etc.) in the codebase.
public struct ColonyLSPSymbolsRequest: Sendable, Equatable, Codable {
    /// Optional file path to search within.
    public var path: ColonyVirtualPath?
    /// Optional search query to filter symbols by name.
    public var query: String?

    public init(path: ColonyVirtualPath? = nil, query: String? = nil) {
        self.path = path
        self.query = query
    }
}

/// A symbol (function, class, variable, etc.) found in the codebase.
public struct ColonyLSPSymbol: Sendable, Equatable, Codable {
    /// LSP symbol kind enumeration.
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

    /// Name of the symbol.
    public var name: String
    /// Kind of symbol (function, class, etc.).
    public var kind: Kind
    /// Path to the file containing this symbol.
    public var path: ColonyVirtualPath
    /// Range of the symbol's definition in the file.
    public var range: ColonyLSPRange

    public init(name: String, kind: Kind, path: ColonyVirtualPath, range: ColonyLSPRange) {
        self.name = name
        self.kind = kind
        self.path = path
        self.range = range
    }
}

/// Request to fetch diagnostics (errors, warnings, etc.) for a file.
public struct ColonyLSPDiagnosticsRequest: Sendable, Equatable, Codable {
    /// Optional file path to get diagnostics for (all files if nil).
    public var path: ColonyVirtualPath?

    public init(path: ColonyVirtualPath? = nil) {
        self.path = path
    }
}

/// A single diagnostic (error, warning, etc.) from the LSP.
public struct ColonyLSPDiagnostic: Sendable, Equatable, Codable {
    /// Diagnostic severity level.
    public enum Severity: String, Sendable, Codable, CaseIterable {
        case error
        case warning
        case information
        case hint
    }

    /// Path to the file containing this diagnostic.
    public var path: ColonyVirtualPath
    /// Range in the file this diagnostic applies to.
    public var range: ColonyLSPRange
    /// Severity of the diagnostic.
    public var severity: Severity
    /// Human-readable diagnostic message.
    public var message: String
    /// Optional error code identifier.
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

/// Request to find references to a symbol at a given position.
public struct ColonyLSPReferencesRequest: Sendable, Equatable, Codable {
    /// Path to the file containing the symbol.
    public var path: ColonyVirtualPath
    /// Position of the symbol to find references for.
    public var position: ColonyLSPPosition
    /// Whether to include the declaration itself in results.
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

/// A reference to a symbol found in the codebase.
public struct ColonyLSPReference: Sendable, Equatable, Codable {
    /// Path to the file containing the reference.
    public var path: ColonyVirtualPath
    /// Range of the reference in the file.
    public var range: ColonyLSPRange
    /// Optional preview text of the reference line.
    public var preview: String?

    public init(path: ColonyVirtualPath, range: ColonyLSPRange, preview: String? = nil) {
        self.path = path
        self.range = range
        self.preview = preview
    }
}

/// A text edit to apply to a file.
public struct ColonyLSPTextEdit: Sendable, Equatable, Codable {
    /// Path to the file to edit.
    public var path: ColonyVirtualPath
    /// Range of text to replace.
    public var range: ColonyLSPRange
    /// New text to insert at the range.
    public var newText: String

    public init(path: ColonyVirtualPath, range: ColonyLSPRange, newText: String) {
        self.path = path
        self.range = range
        self.newText = newText
    }
}

/// Request to apply a batch of text edits via LSP.
public struct ColonyLSPApplyEditRequest: Sendable, Equatable, Codable {
    /// The edits to apply.
    public var edits: [ColonyLSPTextEdit]

    public init(edits: [ColonyLSPTextEdit]) {
        self.edits = edits
    }
}

/// Result of applying text edits via LSP.
public struct ColonyLSPApplyEditResult: Sendable, Equatable, Codable {
    /// Number of edits that were successfully applied.
    public var appliedEditCount: Int
    /// Optional human-readable summary of the result.
    public var summary: String?

    public init(appliedEditCount: Int, summary: String? = nil) {
        self.appliedEditCount = appliedEditCount
        self.summary = summary
    }
}

// MARK: - Response Types

/// Response containing symbol search results.
public struct ColonyLSPSymbolsResponse: Sendable, Equatable, Codable {
    /// The matching symbols found.
    public var symbols: [ColonyLSPSymbol]

    public init(symbols: [ColonyLSPSymbol]) {
        self.symbols = symbols
    }
}

/// Response containing diagnostic results.
public struct ColonyLSPDiagnosticsResponse: Sendable, Equatable, Codable {
    /// The diagnostics found.
    public var diagnostics: [ColonyLSPDiagnostic]

    public init(diagnostics: [ColonyLSPDiagnostic]) {
        self.diagnostics = diagnostics
    }
}

/// Response containing reference search results.
public struct ColonyLSPReferencesResponse: Sendable, Equatable, Codable {
    /// The references found.
    public var references: [ColonyLSPReference]

    public init(references: [ColonyLSPReference]) {
        self.references = references
    }
}

// MARK: - ColonyLSPService Protocol

/// Protocol for Language Server Protocol operations backed by an LSP implementation.
///
/// Implement this protocol to provide LSP functionality (symbol search, diagnostics,
/// references, and edits) for Colony's coding capabilities.
public protocol ColonyLSPService: Sendable {
    /// Searches for symbols matching the request criteria.
    func findSymbols(_ request: ColonyLSPSymbolsRequest) async throws -> ColonyLSPSymbolsResponse
    /// Gets diagnostics for a file or all files.
    func getDiagnostics(_ request: ColonyLSPDiagnosticsRequest) async throws -> ColonyLSPDiagnosticsResponse
    /// Finds all references to a symbol at a given position.
    func findReferences(_ request: ColonyLSPReferencesRequest) async throws -> ColonyLSPReferencesResponse
    /// Applies a batch of text edits.
    func applyEdit(_ request: ColonyLSPApplyEditRequest) async throws -> ColonyLSPApplyEditResult
}

// MARK: - Deprecated Backward Compatibility

public typealias ColonyLSPBackend = ColonyLSPService

public extension ColonyLSPService {
    func symbols(_ request: ColonyLSPSymbolsRequest) async throws -> [ColonyLSPSymbol] {
        let response = try await findSymbols(request)
        return response.symbols
    }

    func diagnostics(_ request: ColonyLSPDiagnosticsRequest) async throws -> [ColonyLSPDiagnostic] {
        let response = try await getDiagnostics(request)
        return response.diagnostics
    }

    func references(_ request: ColonyLSPReferencesRequest) async throws -> [ColonyLSPReference] {
        let response = try await findReferences(request)
        return response.references
    }
}
