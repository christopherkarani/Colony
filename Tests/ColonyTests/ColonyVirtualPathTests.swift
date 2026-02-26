import Testing
@testable import Colony

@Test("ColonyVirtualPath allows double-dot within a filename segment")
func colonyVirtualPath_allowsDoubleDotWithinSegment() throws {
    let path = try ColonyVirtualPath("/notes/a..b.md")
    #expect(path.rawValue == "/notes/a..b.md")
}

@Test("ColonyVirtualPath rejects traversal segment")
func colonyVirtualPath_rejectsTraversalSegment() {
    #expect(throws: ColonyFileSystemError.invalidPath("/notes/../secret.md")) {
        _ = try ColonyVirtualPath("/notes/../secret.md")
    }
}
