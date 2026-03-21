public struct ColonyTodo: Codable, Sendable, Equatable, Identifiable {
    public enum Status: String, Codable, Sendable, Equatable {
        case pending
        case inProgress = "in_progress"
        case completed
    }

    public let id: String
    public var title: String
    public var status: Status

    public init(id: String, title: String, status: Status) {
        self.id = id
        self.title = title
        self.status = status
    }
}

