public struct ColonyCapabilities: OptionSet, Sendable {
    public let rawValue: UInt32

    public init(rawValue: UInt32) {
        self.rawValue = rawValue
    }

    public static let planning = ColonyCapabilities(rawValue: 1 << 0)
    public static let filesystem = ColonyCapabilities(rawValue: 1 << 1)
    public static let shell = ColonyCapabilities(rawValue: 1 << 2)
    public static let subagents = ColonyCapabilities(rawValue: 1 << 3)
    public static let scratchbook = ColonyCapabilities(rawValue: 1 << 4)
    public static let git = ColonyCapabilities(rawValue: 1 << 5)
    public static let lsp = ColonyCapabilities(rawValue: 1 << 6)
    public static let applyPatch = ColonyCapabilities(rawValue: 1 << 7)
    public static let webSearch = ColonyCapabilities(rawValue: 1 << 8)
    public static let codeSearch = ColonyCapabilities(rawValue: 1 << 9)
    public static let mcp = ColonyCapabilities(rawValue: 1 << 10)
    public static let plugins = ColonyCapabilities(rawValue: 1 << 11)
    public static let shellSessions = ColonyCapabilities(rawValue: 1 << 12)
    public static let memory = ColonyCapabilities(rawValue: 1 << 13)

    public static let `default`: ColonyCapabilities = [.planning, .filesystem]
}
