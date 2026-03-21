/// Phantom domain types for `ColonyID`.
///
/// These empty enums serve as type-level tags that prevent accidentally
/// mixing IDs at compile time.
public enum ColonyIDDomain {
    public enum Thread: Sendable {}
    public enum Interrupt: Sendable {}
    public enum HarnessSession: Sendable {}
    public enum Project: Sendable {}
    public enum ProductSession: Sendable {}
    public enum ProductSessionVersion: Sendable {}
    public enum ShareToken: Sendable {}
    public enum Artifact: Sendable {}
    public enum Checkpoint: Sendable {}
    public enum ToolCall: Sendable {}
    public enum Run: Sendable {}
    public enum Message: Sendable {}
    public enum Attempt: Sendable {}
    public enum ShellSession: Sendable {}
}

/// A type-safe identifier parameterized by a phantom `Domain` type.
///
/// Different domains prevent accidentally mixing IDs at compile time
/// while sharing a single implementation.
///
/// ```swift
/// let thread: ColonyThreadID = "my-thread"
/// let interrupt: ColonyInterruptID = "int-1"
/// // thread == interrupt  // compile error — different types
/// ```
public struct ColonyID<Domain>: Hashable, Codable, Sendable,
                                 ExpressibleByStringLiteral,
                                 LosslessStringConvertible {
    public let rawValue: String

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: String) {
        self.init(value)
    }

    public var description: String { rawValue }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.rawValue = try container.decode(String.self)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

// MARK: - Type Aliases

public typealias ColonyThreadID = ColonyID<ColonyIDDomain.Thread>
public typealias ColonyInterruptID = ColonyID<ColonyIDDomain.Interrupt>
public typealias ColonyHarnessSessionID = ColonyID<ColonyIDDomain.HarnessSession>
public typealias ColonyArtifactID = ColonyID<ColonyIDDomain.Artifact>
public typealias ColonyCheckpointID = ColonyID<ColonyIDDomain.Checkpoint>
public typealias ColonyToolCallID = ColonyID<ColonyIDDomain.ToolCall>
public typealias ColonyRunID = ColonyID<ColonyIDDomain.Run>
public typealias ColonyMessageID = ColonyID<ColonyIDDomain.Message>
public typealias ColonyProjectID = ColonyID<ColonyIDDomain.Project>
public typealias ColonyProductSessionID = ColonyID<ColonyIDDomain.ProductSession>
public typealias ColonyProductSessionVersionID = ColonyID<ColonyIDDomain.ProductSessionVersion>
public typealias ColonySessionShareToken = ColonyID<ColonyIDDomain.ShareToken>
public typealias ColonyAttemptID = ColonyID<ColonyIDDomain.Attempt>
public typealias ColonyShellSessionID = ColonyID<ColonyIDDomain.ShellSession>

// MARK: - Subagent Type

/// Type-safe subagent type identifier.
public struct ColonySubagentType: Hashable, Codable, Sendable,
                                   ExpressibleByStringLiteral,
                                   CustomStringConvertible {
    public let rawValue: String
    public init(_ rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { self.init(value) }
    public var description: String { rawValue }

    public static let generalPurpose: ColonySubagentType = "general-purpose"
    public static let compactor: ColonySubagentType = "compactor"
}
