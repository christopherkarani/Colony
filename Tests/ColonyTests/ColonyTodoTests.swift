import Foundation
import Testing
@testable import Colony

@Test("ColonyTodo round-trips through JSON encoding and decoding")
func todoSerializationRoundTrip() throws {
    let todo = ColonyTodo(id: "t-1", title: "Write tests", status: .inProgress)
    let encoder = JSONEncoder()
    encoder.outputFormatting = .sortedKeys
    let data = try encoder.encode(todo)
    let decoded = try JSONDecoder().decode(ColonyTodo.self, from: data)
    #expect(decoded == todo)
}

@Test("ColonyTodo.Status raw values use snake_case JSON representation")
func todoStatusRawValues() {
    #expect(ColonyTodo.Status.pending.rawValue == "pending")
    #expect(ColonyTodo.Status.inProgress.rawValue == "in_progress")
    #expect(ColonyTodo.Status.completed.rawValue == "completed")
}

@Test("ColonyTodo status transitions: pending -> inProgress -> completed")
func todoStatusTransitions() {
    var todo = ColonyTodo(id: "t-2", title: "Ship feature", status: .pending)
    #expect(todo.status == .pending)

    todo.status = .inProgress
    #expect(todo.status == .inProgress)

    todo.status = .completed
    #expect(todo.status == .completed)
}

@Test("ColonyTodo Equatable compares all fields")
func todoEquatable() {
    let a = ColonyTodo(id: "t-3", title: "Task A", status: .pending)
    let b = ColonyTodo(id: "t-3", title: "Task A", status: .pending)
    let c = ColonyTodo(id: "t-3", title: "Task A", status: .completed)
    let d = ColonyTodo(id: "t-4", title: "Task A", status: .pending)
    let e = ColonyTodo(id: "t-3", title: "Task B", status: .pending)

    #expect(a == b)
    #expect(a != c)
    #expect(a != d)
    #expect(a != e)
}

@Test("ColonyTodo Identifiable id matches struct id field")
func todoIdentifiable() {
    let todo = ColonyTodo(id: "unique-42", title: "Check id", status: .pending)
    #expect(todo.id == "unique-42")
}

@Test("ColonyTodo Sendable conformance compiles across concurrency boundary")
func todoSendable() async {
    let todo = ColonyTodo(id: "t-5", title: "Cross boundary", status: .pending)
    let result: ColonyTodo = await Task.detached { todo }.value
    #expect(result == todo)
}

@Test("ColonyTodo decodes from canonical JSON with snake_case status")
func todoDecodesFromJSON() throws {
    let json = #"{"id":"t-6","title":"From JSON","status":"in_progress"}"#
    let data = Data(json.utf8)
    let todo = try JSONDecoder().decode(ColonyTodo.self, from: data)
    #expect(todo.id == "t-6")
    #expect(todo.title == "From JSON")
    #expect(todo.status == .inProgress)
}

@Test("ColonyTodo encoding produces expected JSON keys")
func todoEncodingKeys() throws {
    let todo = ColonyTodo(id: "t-7", title: "Encode", status: .completed)
    let encoder = JSONEncoder()
    encoder.outputFormatting = .sortedKeys
    let data = try encoder.encode(todo)
    let json = String(data: data, encoding: .utf8)!
    #expect(json.contains("\"id\":\"t-7\""))
    #expect(json.contains("\"title\":\"Encode\""))
    #expect(json.contains("\"status\":\"completed\""))
}
