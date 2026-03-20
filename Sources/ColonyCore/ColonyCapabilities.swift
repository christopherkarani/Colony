public struct ColonyRuntimeCapabilities: OptionSet, Sendable {
    public let rawValue: UInt32

    public init(rawValue: UInt32) {
        self.rawValue = rawValue
    }

    public static let planning = ColonyRuntimeCapabilities(rawValue: 1 << 0)
    public static let filesystem = ColonyRuntimeCapabilities(rawValue: 1 << 1)
    public static let shell = ColonyRuntimeCapabilities(rawValue: 1 << 2)
    public static let subagents = ColonyRuntimeCapabilities(rawValue: 1 << 3)
    public static let scratchbook = ColonyRuntimeCapabilities(rawValue: 1 << 4)
    public static let git = ColonyRuntimeCapabilities(rawValue: 1 << 5)
    public static let lsp = ColonyRuntimeCapabilities(rawValue: 1 << 6)
    public static let applyPatch = ColonyRuntimeCapabilities(rawValue: 1 << 7)
    public static let webSearch = ColonyRuntimeCapabilities(rawValue: 1 << 8)
    public static let codeSearch = ColonyRuntimeCapabilities(rawValue: 1 << 9)
    public static let mcp = ColonyRuntimeCapabilities(rawValue: 1 << 10)
    public static let plugins = ColonyRuntimeCapabilities(rawValue: 1 << 11)
    public static let shellSessions = ColonyRuntimeCapabilities(rawValue: 1 << 12)
    public static let memory = ColonyRuntimeCapabilities(rawValue: 1 << 13)

    public static let `default`: ColonyRuntimeCapabilities = [.planning, .filesystem]
}

@available(*, deprecated, renamed: "ColonyRuntimeCapabilities")
public typealias ColonyCapabilities = ColonyRuntimeCapabilities
