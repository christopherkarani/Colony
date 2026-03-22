/// A task tracked in the agent's todo list during a run.
///
/// The todo list is managed via `.writeTodos` and `.readTodos` tools and is
/// included in the `ColonyRun.Transcript` when a run completes.
public struct ColonyTodo: Codable, Sendable, Equatable, Identifiable {
    /// The current state of a todo item.
    public enum Status: String, Codable, Sendable, Equatable {
        /// The task has not been started yet.
        case pending
        /// The task is currently being worked on.
        case inProgress = "in_progress"
        /// The task has been completed.
        case completed
    }

    /// Unique identifier for this todo, stable across supersteps.
    public let id: String
    /// A short title describing what needs to be done.
    public var title: String
    /// The current completion status.
    public var status: Status

    public init(id: String, title: String, status: Status) {
        self.id = id
        self.title = title
        self.status = status
    }
}

