/// Represents a task or to-do item managed by the agent's planning capability.
///
/// Used internally by the `write_todos` and `read_todos` built-in tools to track
/// multi-step tasks and their completion status.
public struct ColonyTodo: Codable, Sendable, Equatable, Identifiable {
    /// The lifecycle state of a todo item.
    public enum Status: String, Codable, Sendable, Equatable {
        /// Task has not yet been started.
        case pending
        /// Task is currently being worked on.
        case inProgress = "in_progress"
        /// Task has been completed.
        case completed
    }

    /// Unique identifier for this todo item.
    public let id: String
    /// Brief title describing the task.
    public var title: String
    /// Current completion status.
    public var status: Status

    /// Creates a new todo item.
    ///
    /// - Parameters:
    ///   - id: Unique identifier for the todo.
    ///   - title: Brief description of the task.
    ///   - status: Initial status (defaults to `.pending`).
    public init(id: String, title: String, status: Status) {
        self.id = id
        self.title = title
        self.status = status
    }
}

