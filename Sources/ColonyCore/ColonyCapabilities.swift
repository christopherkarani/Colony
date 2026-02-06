public struct ColonyCapabilities: OptionSet, Sendable {
    public let rawValue: UInt32

    public init(rawValue: UInt32) {
        self.rawValue = rawValue
    }

    public static let planning = ColonyCapabilities(rawValue: 1 << 0)
    public static let filesystem = ColonyCapabilities(rawValue: 1 << 1)
    public static let shell = ColonyCapabilities(rawValue: 1 << 2)
    public static let subagents = ColonyCapabilities(rawValue: 1 << 3)

    public static let `default`: ColonyCapabilities = [.planning, .filesystem]
}

