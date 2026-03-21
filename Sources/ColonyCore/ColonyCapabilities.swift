public struct ColonyAgentCapabilities: OptionSet, Sendable {
    public let rawValue: UInt32

    public init(rawValue: UInt32) {
        self.rawValue = rawValue
    }

    public static let planning = ColonyAgentCapabilities(rawValue: 1 << 0)
    public static let filesystem = ColonyAgentCapabilities(rawValue: 1 << 1)
    public static let shell = ColonyAgentCapabilities(rawValue: 1 << 2)
    public static let subagents = ColonyAgentCapabilities(rawValue: 1 << 3)
    public static let scratchbook = ColonyAgentCapabilities(rawValue: 1 << 4)
    public static let git = ColonyAgentCapabilities(rawValue: 1 << 5)
    public static let lsp = ColonyAgentCapabilities(rawValue: 1 << 6)
    public static let applyPatch = ColonyAgentCapabilities(rawValue: 1 << 7)
    public static let webSearch = ColonyAgentCapabilities(rawValue: 1 << 8)
    public static let codeSearch = ColonyAgentCapabilities(rawValue: 1 << 9)
    public static let mcp = ColonyAgentCapabilities(rawValue: 1 << 10)
    public static let plugins = ColonyAgentCapabilities(rawValue: 1 << 11)
    public static let shellSessions = ColonyAgentCapabilities(rawValue: 1 << 12)
    public static let memory = ColonyAgentCapabilities(rawValue: 1 << 13)

    public static let `default`: ColonyAgentCapabilities = [.planning, .filesystem]
}
