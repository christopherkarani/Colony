import Foundation
import Testing
@testable import Colony

private func requireCodableAndSendable<T: Codable & Sendable>(_: T.Type) {}
private func requireIdentifiable<T: Identifiable & Sendable>(_: T.Type) {}

@Suite("ColonyWorkspace Tests")
struct ColonyWorkspaceTests {

    @Test("Workspace core types are Codable + Sendable (and item is Identifiable)")
    func workspaceCore_conformance() {
        requireCodableAndSendable(ColonyWorkspace.self)
        requireCodableAndSendable(ColonyWorkspaceItem.self)
        requireIdentifiable(ColonyWorkspaceItem.self)
    }

    @Test("WorkspaceItem initializes with correct default values")
    func workspaceItem_initialization() {
        let item = ColonyWorkspaceItem(
            kind: .note,
            title: "Test Title",
            content: "Test Content"
        )

        #expect(item.kind == .note)
        #expect(item.status == .active)
        #expect(item.title == "Test Title")
        #expect(item.content == "Test Content")
        #expect(item.id.isEmpty == false)

        // Dates should be set to approximately now
        let now = Date()
        let timeDiff = now.timeIntervalSince(item.createdAt)
        #expect(timeDiff < 1.0)
        #expect(timeDiff >= 0)
    }

    @Test("WorkspaceItem can be initialized with custom id and status")
    func workspaceItem_customInitialization() {
        let customId = "custom-id-123"
        let item = ColonyWorkspaceItem(
            id: customId,
            kind: .task,
            status: .inProgress,
            title: "Task Title",
            content: "Task Content"
        )

        #expect(item.id == customId)
        #expect(item.kind == .task)
        #expect(item.status == .inProgress)
    }

    @Test("Workspace initializes with empty items and pinnedItems by default")
    func workspace_defaultInitialization() {
        let workspace = ColonyWorkspace()

        #expect(workspace.items.isEmpty)
        #expect(workspace.pinnedItems.isEmpty)
    }

    @Test("Workspace can be initialized with items and pinned items")
    func workspace_customInitialization() {
        let item1 = ColonyWorkspaceItem(kind: .note, title: "Note 1", content: "Content 1")
        let item2 = ColonyWorkspaceItem(kind: .todo, title: "Todo 1", content: "Content 2")

        let workspace = ColonyWorkspace(
            items: [item1, item2],
            pinnedItems: [item1.id]
        )

        #expect(workspace.items.count == 2)
        #expect(workspace.pinnedItems.count == 1)
        #expect(workspace.pinnedItems.contains(item1.id))
    }

    @Test("WorkspaceItem is Codable")
    func workspaceItem_codable() throws {
        let item = ColonyWorkspaceItem(
            id: "test-id",
            kind: .task,
            status: .completed,
            title: "Test Task",
            content: "Task Content"
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(item)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(ColonyWorkspaceItem.self, from: data)

        #expect(decoded.id == item.id)
        #expect(decoded.kind == item.kind)
        #expect(decoded.status == item.status)
        #expect(decoded.title == item.title)
        #expect(decoded.content == item.content)
    }

    @Test("Workspace is Codable")
    func workspace_codable() throws {
        let item1 = ColonyWorkspaceItem(kind: .note, title: "Note", content: "Note Content")
        let item2 = ColonyWorkspaceItem(kind: .todo, title: "Todo", content: "Todo Content")

        let workspace = ColonyWorkspace(
            items: [item1, item2],
            pinnedItems: [item1.id]
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(workspace)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(ColonyWorkspace.self, from: data)

        #expect(decoded.items.count == 2)
        #expect(decoded.pinnedItems.count == 1)
        #expect(decoded.pinnedItems.contains(item1.id))
    }

    @Test("WorkspaceItem Kind enum has all expected cases")
    func workspaceItem_kindCases() {
        let note: ColonyWorkspaceItem.Kind = .note
        let todo: ColonyWorkspaceItem.Kind = .todo
        let task: ColonyWorkspaceItem.Kind = .task

        #expect(note.rawValue == "note")
        #expect(todo.rawValue == "todo")
        #expect(task.rawValue == "task")
    }

    @Test("WorkspaceItem Status enum has all expected cases")
    func workspaceItem_statusCases() {
        let active: ColonyWorkspaceItem.Status = .active
        let archived: ColonyWorkspaceItem.Status = .archived
        let pending: ColonyWorkspaceItem.Status = .pending
        let inProgress: ColonyWorkspaceItem.Status = .inProgress
        let completed: ColonyWorkspaceItem.Status = .completed

        #expect(active.rawValue == "active")
        #expect(archived.rawValue == "archived")
        #expect(pending.rawValue == "pending")
        #expect(inProgress.rawValue == "in_progress")
        #expect(completed.rawValue == "completed")
    }

    @Test("Deprecated ColonyScratchbook typealias points to ColonyWorkspace")
    func deprecation_scratchbook() {
        // This test verifies the typealias exists and points to the correct type
        let workspace: ColonyScratchbook = ColonyWorkspace()
        #expect(workspace.items.isEmpty)
    }

    @Test("Deprecated ColonyScratchItem typealias points to ColonyWorkspaceItem")
    func deprecation_scratchItem() {
        // This test verifies the typealias exists and points to the correct type
        let item: ColonyScratchItem = ColonyWorkspaceItem(kind: .note, title: "Test", content: "Content")
        #expect(item.kind == .note)
    }
}
