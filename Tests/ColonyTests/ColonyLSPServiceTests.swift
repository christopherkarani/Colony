import Testing
@testable import ColonyCore

// MARK: - Response Type Tests

@Test
func colonyLSPSymbolsResponseExists() async throws {
    let response = ColonyLSPSymbolsResponse(symbols: [])
    #expect(response.symbols.isEmpty)
}

@Test
func colonyLSPSymbolsResponseWithSymbols() async throws {
    let symbol = ColonyLSPSymbol(
        name: "testFunc",
        kind: .function,
        path: try ColonyVirtualPath("/test.swift"),
        range: ColonyLSPRange(
            start: ColonyLSPPosition(line: 1, character: 0),
            end: ColonyLSPPosition(line: 1, character: 10)
        )
    )
    let response = ColonyLSPSymbolsResponse(symbols: [symbol])
    #expect(response.symbols.count == 1)
    #expect(response.symbols[0].name == "testFunc")
}

@Test
func colonyLSPDiagnosticsResponseExists() async throws {
    let response = ColonyLSPDiagnosticsResponse(diagnostics: [])
    #expect(response.diagnostics.isEmpty)
}

@Test
func colonyLSPDiagnosticsResponseWithDiagnostics() async throws {
    let diagnostic = ColonyLSPDiagnostic(
        path: try ColonyVirtualPath("/test.swift"),
        range: ColonyLSPRange(
            start: ColonyLSPPosition(line: 1, character: 0),
            end: ColonyLSPPosition(line: 1, character: 10)
        ),
        severity: .error,
        message: "Test error"
    )
    let response = ColonyLSPDiagnosticsResponse(diagnostics: [diagnostic])
    #expect(response.diagnostics.count == 1)
    #expect(response.diagnostics[0].message == "Test error")
}

@Test
func colonyLSPReferencesResponseExists() async throws {
    let response = ColonyLSPReferencesResponse(references: [])
    #expect(response.references.isEmpty)
}

@Test
func colonyLSPReferencesResponseWithReferences() async throws {
    let reference = ColonyLSPReference(
        path: try ColonyVirtualPath("/test.swift"),
        range: ColonyLSPRange(
            start: ColonyLSPPosition(line: 1, character: 0),
            end: ColonyLSPPosition(line: 1, character: 10)
        )
    )
    let response = ColonyLSPReferencesResponse(references: [reference])
    #expect(response.references.count == 1)
    #expect(response.references[0].path.rawValue == "/test.swift")
}

// MARK: - ColonyLSPService Protocol Tests

@Test
func colonyLSPServiceProtocolExists() async throws {
    // Verify the protocol exists and has the expected methods
    let service = MockLSPService()

    let symbolsRequest = ColonyLSPSymbolsRequest(path: nil, query: nil)
    let symbolsResponse = try await service.findSymbols(symbolsRequest)
    #expect(symbolsResponse.symbols.isEmpty)

    let diagnosticsRequest = ColonyLSPDiagnosticsRequest(path: nil)
    let diagnosticsResponse = try await service.getDiagnostics(diagnosticsRequest)
    #expect(diagnosticsResponse.diagnostics.isEmpty)

    let referencesRequest = ColonyLSPReferencesRequest(
        path: try ColonyVirtualPath("/test.swift"),
        position: ColonyLSPPosition(line: 1, character: 0)
    )
    let referencesResponse = try await service.findReferences(referencesRequest)
    #expect(referencesResponse.references.isEmpty)
}

@Test
func colonyLSPServiceHasApplyEditMethod() async throws {
    let service = MockLSPService()

    let editRequest = ColonyLSPApplyEditRequest(edits: [])
    let result = try await service.applyEdit(editRequest)
    #expect(result.appliedEditCount == 0)
}

// MARK: - Deprecated ColonyLSPBackend Compatibility Tests

@Test
func deprecatedColonyLSPBackendTypealiasExists() async throws {
    // Verify the deprecated typealias exists for backward compatibility
    let service: ColonyLSPBackend = MockLSPService()
    _ = service
}

@Test
func deprecatedSymbolsMethodStillWorks() async throws {
    let service: ColonyLSPBackend = MockLSPService()

    let request = ColonyLSPSymbolsRequest(path: nil, query: nil)
    let symbols = try await service.symbols(request)
    #expect(symbols.isEmpty)
}

@Test
func deprecatedDiagnosticsMethodStillWorks() async throws {
    let service: ColonyLSPBackend = MockLSPService()

    let request = ColonyLSPDiagnosticsRequest(path: nil)
    let diagnostics = try await service.diagnostics(request)
    #expect(diagnostics.isEmpty)
}

@Test
func deprecatedReferencesMethodStillWorks() async throws {
    let service: ColonyLSPBackend = MockLSPService()

    let request = ColonyLSPReferencesRequest(
        path: try ColonyVirtualPath("/test.swift"),
        position: ColonyLSPPosition(line: 1, character: 0)
    )
    let references = try await service.references(request)
    #expect(references.isEmpty)
}

// MARK: - Mock Implementation

private actor MockLSPService: ColonyLSPService {
    func findSymbols(_ request: ColonyLSPSymbolsRequest) async throws -> ColonyLSPSymbolsResponse {
        ColonyLSPSymbolsResponse(symbols: [])
    }

    func getDiagnostics(_ request: ColonyLSPDiagnosticsRequest) async throws -> ColonyLSPDiagnosticsResponse {
        ColonyLSPDiagnosticsResponse(diagnostics: [])
    }

    func findReferences(_ request: ColonyLSPReferencesRequest) async throws -> ColonyLSPReferencesResponse {
        ColonyLSPReferencesResponse(references: [])
    }

    func applyEdit(_ request: ColonyLSPApplyEditRequest) async throws -> ColonyLSPApplyEditResult {
        ColonyLSPApplyEditResult(appliedEditCount: 0)
    }
}
