import Foundation
import Testing
@testable import Colony

private func requireCodableAndSendable<T: Codable & Sendable>(_: T.Type) {}
private func requireIdentifiable<T: Identifiable & Sendable>(_: T.Type) {}

private func approximateTokenCount(_ text: String) -> Int {
    max(1, text.count / 4)
}

private func substringsAppearInOrder(_ substrings: [String], in text: String) -> Bool {
    var searchStart = text.startIndex
    for substring in substrings {
        guard let range = text.range(of: substring, range: searchStart..<text.endIndex) else { return false }
        searchStart = range.upperBound
    }
    return true
}

private func encodeSortedJSON<T: Encodable>(_ value: T) throws -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let data = try encoder.encode(value)
    return String(decoding: data, as: UTF8.self)
}

private func sanitizeThreadIDForPathComponent(_ raw: String) -> String {
    raw.map { character in
        switch character {
        case "/", "\\":
            return "_"
        default:
            return character
        }
    }.reduce(into: "") { partial, character in
        partial.append(character)
    }
}

@Test("Scratchbook core types are Codable + Sendable (and item is Identifiable)")
func scratchbookCore_conformance() {
    requireCodableAndSendable(ColonyScratchbook.self)
    requireCodableAndSendable(ColonyScratchItem.self)
    requireIdentifiable(ColonyScratchItem.self)
}

@Test("Scratchbook renderView prioritizes pinned, then open/in-progress tasks, then open todos, then recent notes")
func scratchbookCore_renderView_prioritizationAndDeterminism() throws {
    let pinnedNote = ColonyScratchItem(
        id: "pinned-note",
        kind: .note,
        status: .open,
        title: "Pinned Note",
        body: "pinned",
        tags: ["a"],
        createdAtNanoseconds: 10,
        updatedAtNanoseconds: 50,
        phase: nil,
        progress: nil
    )

    let inProgressTask = ColonyScratchItem(
        id: "task-in-progress",
        kind: .task,
        status: .inProgress,
        title: "Task (In Progress)",
        body: "work",
        tags: [],
        createdAtNanoseconds: 20,
        updatedAtNanoseconds: 60,
        phase: "build",
        progress: 0.5
    )

    let openTask = ColonyScratchItem(
        id: "task-open",
        kind: .task,
        status: .open,
        title: "Task (Open)",
        body: "todo",
        tags: [],
        createdAtNanoseconds: 30,
        updatedAtNanoseconds: 55,
        phase: nil,
        progress: nil
    )

    let openTodo = ColonyScratchItem(
        id: "todo-open",
        kind: .todo,
        status: .open,
        title: "Todo (Open)",
        body: "short",
        tags: [],
        createdAtNanoseconds: 40,
        updatedAtNanoseconds: 54,
        phase: nil,
        progress: nil
    )

    let recentNote = ColonyScratchItem(
        id: "note-recent",
        kind: .note,
        status: .open,
        title: "Note (Recent)",
        body: "recent",
        tags: [],
        createdAtNanoseconds: 41,
        updatedAtNanoseconds: 90,
        phase: nil,
        progress: nil
    )

    let olderNote = ColonyScratchItem(
        id: "note-older",
        kind: .note,
        status: .open,
        title: "Note (Older)",
        body: "older",
        tags: [],
        createdAtNanoseconds: 42,
        updatedAtNanoseconds: 11,
        phase: nil,
        progress: nil
    )

    // Intentionally shuffled input order to ensure renderView deterministically sorts by priority + timestamps.
    let scratchbook = ColonyScratchbook(
        items: [openTodo, olderNote, openTask, recentNote, pinnedNote, inProgressTask],
        pinnedItemIDs: ["pinned-note"]
    )

    let view = scratchbook.renderView(viewTokenLimit: 10_000, maxRenderedItems: 100)

    // View must include item ids so tool calls can target items by id.
    #expect(view.contains("pinned-note") == true)
    #expect(view.contains("task-in-progress") == true)
    #expect(view.contains("task-open") == true)
    #expect(view.contains("todo-open") == true)
    #expect(view.contains("note-recent") == true)
    #expect(view.contains("note-older") == true)

    // Priority tiers:
    // 1) pinned
    // 2) open/in-progress tasks
    // 3) open todos
    // 4) recent notes
    #expect(
        substringsAppearInOrder(
            ["pinned-note", "task-in-progress", "task-open", "todo-open", "note-recent", "note-older"],
            in: view
        )
    )

    // Deterministic ordering by timestamps: recent notes should appear before older notes.
    #expect(substringsAppearInOrder(["note-recent", "note-older"], in: view))
}

@Test("Scratchbook renderView enforces maxRenderedItems without violating priority tiers")
func scratchbookCore_renderView_maxRenderedItems() throws {
    let pinned = ColonyScratchItem(
        id: "pinned",
        kind: .note,
        status: .open,
        title: "Pinned",
        body: "p",
        tags: [],
        createdAtNanoseconds: 1,
        updatedAtNanoseconds: 1,
        phase: nil,
        progress: nil
    )

    let task = ColonyScratchItem(
        id: "task",
        kind: .task,
        status: .open,
        title: "Task",
        body: "t",
        tags: [],
        createdAtNanoseconds: 2,
        updatedAtNanoseconds: 2,
        phase: nil,
        progress: nil
    )

    let todo = ColonyScratchItem(
        id: "todo",
        kind: .todo,
        status: .open,
        title: "Todo",
        body: "x",
        tags: [],
        createdAtNanoseconds: 3,
        updatedAtNanoseconds: 3,
        phase: nil,
        progress: nil
    )

    let scratchbook = ColonyScratchbook(
        items: [todo, task, pinned],
        pinnedItemIDs: ["pinned"]
    )

    let view = scratchbook.renderView(viewTokenLimit: 10_000, maxRenderedItems: 2)
    #expect(view.contains("pinned") == true)
    #expect(view.contains("task") == true)
    #expect(view.contains("todo") == false)

    // Still enforce priority when trimming.
    #expect(substringsAppearInOrder(["pinned", "task"], in: view))
}

@Test("Scratchbook renderView trims to viewTokenLimit using deterministic budgeting")
func scratchbookCore_renderView_viewTokenLimit() throws {
    let pinned = ColonyScratchItem(
        id: "pinned",
        kind: .note,
        status: .open,
        title: "Pinned",
        body: String(repeating: "a", count: 2_000),
        tags: [],
        createdAtNanoseconds: 1,
        updatedAtNanoseconds: 1,
        phase: nil,
        progress: nil
    )

    let note = ColonyScratchItem(
        id: "note",
        kind: .note,
        status: .open,
        title: "Note",
        body: String(repeating: "b", count: 2_000),
        tags: [],
        createdAtNanoseconds: 2,
        updatedAtNanoseconds: 2,
        phase: nil,
        progress: nil
    )

    let scratchbook = ColonyScratchbook(
        items: [note, pinned],
        pinnedItemIDs: ["pinned"]
    )

    let limit = 80
    let view = scratchbook.renderView(viewTokenLimit: limit, maxRenderedItems: 100)

    // Budget is conservative (4 chars/token heuristic) to avoid oversending context.
    #expect(approximateTokenCount(view) <= limit)
    #expect(view.contains("pinned") == true)
}

@Test("Scratchbook renderView returns a truncated first line for tiny positive budgets")
func scratchbookCore_renderView_tinyBudgetReturnsNonEmptyTruncation() throws {
    let item = ColonyScratchItem(
        id: "item-1",
        kind: .note,
        status: .open,
        title: "Very Long Title",
        body: String(repeating: "x", count: 200),
        tags: [],
        createdAtNanoseconds: 1,
        updatedAtNanoseconds: 1
    )

    let scratchbook = ColonyScratchbook(items: [item], pinnedItemIDs: [])
    let view = scratchbook.renderView(viewTokenLimit: 1, maxRenderedItems: 20)

    #expect(view.isEmpty == false)
    #expect(view.count <= 4)
}

@Test("Scratchbook store persists per-thread JSON at {prefix}/{sanitizedThreadID}.json using sortedKeys encoding")
func scratchbookStorage_persistsPerThread_withSortedKeysEncoding() async throws {
    let filesystem = ColonyInMemoryFileSystemBackend()
    let prefix = try ColonyVirtualPath("/scratchbook")
    let policy = ColonyScratchbookPolicy(
        pathPrefix: prefix,
        viewTokenLimit: 200,
        maxRenderedItems: 20,
        autoCompact: false
    )

    let threadID = HiveThreadID("thread/with\\slashes")
    let expectedPath = try ColonyScratchbookStore.path(threadID: threadID.rawValue, policy: policy)

    let scratchbook = ColonyScratchbook(
        items: [
            ColonyScratchItem(
                id: "item-1",
                kind: .task,
                status: .inProgress,
                title: "Work",
                body: "Details",
                tags: ["b", "a"],
                createdAtNanoseconds: 1,
                updatedAtNanoseconds: 2,
                phase: "phase",
                progress: 0.3
            )
        ],
        pinnedItemIDs: ["item-1"]
    )

    try await ColonyScratchbookStore.save(
        scratchbook,
        filesystem: filesystem,
        threadID: threadID.rawValue,
        policy: policy
    )

    let persistedJSON = try await filesystem.read(at: expectedPath)
    let expectedJSON = try encodeSortedJSON(scratchbook)
    #expect(persistedJSON == expectedJSON)
}

@Test("Scratchbook store load returns empty scratchbook when the per-thread file is missing")
func scratchbookStorage_loadMissing_returnsEmptyScratchbook() async throws {
    let filesystem = ColonyInMemoryFileSystemBackend()
    let policy = ColonyScratchbookPolicy(
        pathPrefix: try ColonyVirtualPath("/scratchbook"),
        viewTokenLimit: 200,
        maxRenderedItems: 20,
        autoCompact: false
    )

    let scratchbook = try await ColonyScratchbookStore.load(
        filesystem: filesystem,
        threadID: HiveThreadID("missing-thread").rawValue,
        policy: policy
    )
    #expect(scratchbook.items.isEmpty == true)
}
