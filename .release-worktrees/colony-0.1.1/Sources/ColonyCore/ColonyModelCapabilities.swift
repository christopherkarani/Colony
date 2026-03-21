public struct ColonyModelCapabilities: OptionSet, Sendable {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    /// Model consumes tool definitions and emits structured tool calls natively.
    public static let nativeToolCalling = ColonyModelCapabilities(rawValue: 1 << 0)
    /// Model client translates Hive tool definitions into prompt instructions internally.
    public static let managedToolPrompting = ColonyModelCapabilities(rawValue: 1 << 1)
    /// Model/client can satisfy structured output requests without Colony prompt injection.
    public static let nativeStructuredOutputs = ColonyModelCapabilities(rawValue: 1 << 2)
    /// Model client enforces structured output formatting internally through managed prompting.
    public static let managedStructuredOutputs = ColonyModelCapabilities(rawValue: 1 << 3)

    public var handlesToolDefinitionsWithoutSystemPrompt: Bool {
        contains(.nativeToolCalling) || contains(.managedToolPrompting)
    }

    public var handlesStructuredOutputsWithoutSystemPrompt: Bool {
        contains(.nativeStructuredOutputs) || contains(.managedStructuredOutputs)
    }
}

public enum ColonyToolPromptStrategy: Sendable, Equatable {
    /// Decide based on the routed model capabilities at runtime.
    case automatic
    /// Always include the tool list in Colony's system prompt.
    case includeInSystemPrompt
    /// Never include the tool list in Colony's system prompt.
    case omitFromSystemPrompt

    public func includesToolList(for capabilities: ColonyModelCapabilities) -> Bool {
        switch self {
        case .automatic:
            return capabilities.handlesToolDefinitionsWithoutSystemPrompt == false
        case .includeInSystemPrompt:
            return true
        case .omitFromSystemPrompt:
            return false
        }
    }
}
