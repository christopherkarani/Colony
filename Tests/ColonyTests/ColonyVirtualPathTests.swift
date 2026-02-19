import Testing
@testable import ColonyCore

struct ColonyVirtualPathTests {
    @Test
    func safeFallsBackForInvalidPath() throws {
        let fallback = try ColonyVirtualPath("/fallback")
        let result = ColonyVirtualPath.safe("../bad", fallback: fallback)
        #expect(result == fallback)
    }

    @Test
    func rootIsStable() {
        #expect(ColonyVirtualPath.root.rawValue == "/")
    }
}
