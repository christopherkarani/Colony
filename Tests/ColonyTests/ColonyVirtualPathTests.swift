import Testing
@testable import ColonyCore

@Test("ColonyVirtualPath.safe falls back for invalid input")
func colonyVirtualPathSafeFallback() throws {
    let fallback = ColonyVirtualPath.safe("/fallback")
    let safe = ColonyVirtualPath.safe("~/secret", fallback: fallback)
    #expect(safe == fallback)
}

@Test("ColonyVirtualPath.root is normalized")
func colonyVirtualPathRootNormalized() throws {
    #expect(ColonyVirtualPath.root.rawValue == "/")
}
