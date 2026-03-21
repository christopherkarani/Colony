import Foundation
import Testing
@testable import Colony

private actor RecordingFileSystemBackend: ColonyFileSystemBackend {
    enum Operation: Sendable, Equatable {
        case list(ColonyVirtualPath)
        case read(ColonyVirtualPath)
        case write(ColonyVirtualPath, content: String)
        case edit(ColonyVirtualPath, old: String, new: String, replaceAll: Bool)
        case glob(String)
        case grep(pattern: String, glob: String?)
    }

    private let base: any ColonyFileSystemBackend
    private var operations: [Operation] = []

    init(base: any ColonyFileSystemBackend) {
        self.base = base
    }

    func list(at path: ColonyVirtualPath) async throws -> [ColonyFileInfo] {
        operations.append(.list(path))
        return try await base.list(at: path)
    }

    func read(at path: ColonyVirtualPath) async throws -> String {
        operations.append(.read(path))
        return try await base.read(at: path)
    }

    func write(at path: ColonyVirtualPath, content: String) async throws {
        operations.append(.write(path, content: content))
        try await base.write(at: path, content: content)
    }

    func edit(
        at path: ColonyVirtualPath,
        oldString: String,
        newString: String,
        replaceAll: Bool
    ) async throws -> Int {
        operations.append(.edit(path, old: oldString, new: newString, replaceAll: replaceAll))
        return try await base.edit(
            at: path,
            oldString: oldString,
            newString: newString,
            replaceAll: replaceAll
        )
    }

    func glob(pattern: String) async throws -> [ColonyVirtualPath] {
        operations.append(.glob(pattern))
        return try await base.glob(pattern: pattern)
    }

    func grep(pattern: String, glob: String?) async throws -> [ColonyGrepMatch] {
        operations.append(.grep(pattern: pattern, glob: glob))
        return try await base.grep(pattern: pattern, glob: glob)
    }

    func recordedOperations() -> [Operation] {
        operations
    }
}

@Test("Composite filesystem backend routes by longest prefix and strips/restores paths")
func compositeFileSystemBackend_routesByLongestPrefix_andStripsRestoresPaths() async throws {
    let defaultBackend = RecordingFileSystemBackend(
        base: ColonyInMemoryFileSystemBackend(
            files: [
                try ColonyVirtualPath("/default.txt"): "default",
            ]
        )
    )
    let memoriesBackend = RecordingFileSystemBackend(
        base: ColonyInMemoryFileSystemBackend(
            files: [
                try ColonyVirtualPath("/note.md"): "note",
            ]
        )
    )

    let composite = ColonyCompositeFileSystemBackend(
        default: defaultBackend,
        routes: [
            try ColonyVirtualPath("/memories"): memoriesBackend,
        ]
    )

    #expect(try await composite.read(at: ColonyVirtualPath("/default.txt")) == "default")
    #expect(try await composite.read(at: ColonyVirtualPath("/memories/note.md")) == "note")

    try await composite.write(at: ColonyVirtualPath("/memories/new.txt"), content: "new")
    #expect(try await composite.read(at: ColonyVirtualPath("/memories/new.txt")) == "new")

    #expect(await defaultBackend.recordedOperations() == [
        .read(try ColonyVirtualPath("/default.txt")),
    ])

    #expect(await memoriesBackend.recordedOperations() == [
        .read(try ColonyVirtualPath("/note.md")),
        .write(try ColonyVirtualPath("/new.txt"), content: "new"),
        .read(try ColonyVirtualPath("/new.txt")),
    ])
}

@Test("Composite filesystem backend prefers deterministic longest-prefix match")
func compositeFileSystemBackend_prefersDeterministicLongestPrefixMatch() async throws {
    let a = RecordingFileSystemBackend(
        base: ColonyInMemoryFileSystemBackend(
            files: [
                try ColonyVirtualPath("/public.md"): "public",
            ]
        )
    )
    let b = RecordingFileSystemBackend(
        base: ColonyInMemoryFileSystemBackend(
            files: [
                try ColonyVirtualPath("/secret.md"): "secret",
            ]
        )
    )

    let composite = ColonyCompositeFileSystemBackend(
        default: ColonyInMemoryFileSystemBackend(),
        routes: [
            try ColonyVirtualPath("/memories"): a,
            try ColonyVirtualPath("/memories/private"): b,
        ]
    )

    #expect(try await composite.read(at: ColonyVirtualPath("/memories/public.md")) == "public")
    #expect(try await composite.read(at: ColonyVirtualPath("/memories/private/secret.md")) == "secret")

    #expect(await a.recordedOperations() == [
        .read(try ColonyVirtualPath("/public.md")),
    ])
    #expect(await b.recordedOperations() == [
        .read(try ColonyVirtualPath("/secret.md")),
    ])
}

@Test("Composite filesystem backend exposes routed prefixes as root virtual directories with stable ordering")
func compositeFileSystemBackend_rootListing_exposesRoutesAsDirectories_withStableOrdering() async throws {
    let defaultBackend = ColonyInMemoryFileSystemBackend(
        files: [
            try ColonyVirtualPath("/a.txt"): "a",
        ]
    )
    let memoriesBackend = ColonyInMemoryFileSystemBackend(
        files: [
            try ColonyVirtualPath("/note.md"): "note",
        ]
    )

    let composite = ColonyCompositeFileSystemBackend(
        default: defaultBackend,
        routes: [
            try ColonyVirtualPath("/memories"): memoriesBackend,
        ]
    )

    let root = try await composite.list(at: .root)
    #expect(root.map(\.path.rawValue) == ["/a.txt", "/memories"])
    #expect(root.first?.isDirectory == false)
    #expect(root.last?.isDirectory == true)

    let memories = try await composite.list(at: ColonyVirtualPath("/memories"))
    #expect(memories.map(\.path.rawValue) == ["/memories/note.md"])
}

@Test("Composite filesystem backend merges glob/grep across routes and restores prefixes deterministically")
func compositeFileSystemBackend_globAndGrep_mergeAcrossRoutes_andRestorePrefixes() async throws {
    let defaultBackend = ColonyInMemoryFileSystemBackend(
        files: [
            try ColonyVirtualPath("/a.md"): "hello",
        ]
    )
    let memoriesBackend = ColonyInMemoryFileSystemBackend(
        files: [
            try ColonyVirtualPath("/note.md"): "hello",
        ]
    )

    let composite = ColonyCompositeFileSystemBackend(
        default: defaultBackend,
        routes: [
            try ColonyVirtualPath("/memories"): memoriesBackend,
        ]
    )

    let globbed = try await composite.glob(pattern: "**/*.md")
    #expect(globbed.map(\.rawValue) == ["/a.md", "/memories/note.md"])

    let scopedGlobbed = try await composite.glob(pattern: "/memories/*.md")
    #expect(scopedGlobbed.map(\.rawValue) == ["/memories/note.md"])

    let matches = try await composite.grep(pattern: "hello", glob: nil)
    #expect(matches.map(\.path.rawValue) == ["/a.md", "/memories/note.md"])

    let scopedMatches = try await composite.grep(pattern: "hello", glob: "/memories/*.md")
    #expect(scopedMatches.map(\.path.rawValue) == ["/memories/note.md"])
}

