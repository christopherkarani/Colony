import Testing
@testable import ColonyCore

@Test("ColonyVirtualPath.root is canonical slash")
func colonyVirtualPath_root_isCanonicalSlash() {
    #expect(ColonyVirtualPath.root.rawValue == "/")
}

@Test("ColonyVirtualPath.literal normalizes valid literals")
func colonyVirtualPath_literal_normalizesValidLiteral() {
    let path = ColonyVirtualPath.literal("scratchbook/")
    #expect(path.rawValue == "/scratchbook")
}

@Test("ColonyVirtualPath.literal falls back to root for invalid literal")
func colonyVirtualPath_literal_fallsBackForInvalidLiteral() {
    let path = ColonyVirtualPath.literal("../escape")
    #expect(path.rawValue == "/")
}
