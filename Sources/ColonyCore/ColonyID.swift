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

// MARK: - Phantom Domain Types

extension ColonyID {
    public enum Thread: Sendable {}
    public enum Interrupt: Sendable {}
    public enum HarnessSession: Sendable {}
    public enum Project: Sendable {}
    public enum ProductSession: Sendable {}
    public enum ProductSessionVersion: Sendable {}
    public enum ShareToken: Sendable {}
    public enum Artifact: Sendable {}
    public enum Checkpoint: Sendable {}
}

// MARK: - Backward-Compatible Type Aliases

public typealias ColonyThreadID = ColonyID<ColonyID.Thread>
public typealias ColonyInterruptID = ColonyID<ColonyID.Interrupt>
public typealias ColonyHarnessSessionID = ColonyID<ColonyID.HarnessSession>
public typealias ColonyArtifactID = ColonyID<ColonyID.Artifact>
public typealias ColonyCheckpointID = ColonyID<ColonyID.Checkpoint>

// Keep old names as deprecated typealiases for migration
@available(*, deprecated, renamed: "ColonyID.Thread")
public typealias ThreadDomain = ColonyID.Thread
@available(*, deprecated, renamed: "ColonyID.Interrupt")
public typealias InterruptDomain = ColonyID.Interrupt
@available(*, deprecated, renamed: "ColonyID.HarnessSession")
public typealias HarnessSessionDomain = ColonyID.HarnessSession
@available(*, deprecated, renamed: "ColonyID.Project")
public typealias ProjectDomain = ColonyID.Project
@available(*, deprecated, renamed: "ColonyID.ProductSession")
public typealias ProductSessionDomain = ColonyID.ProductSession
@available(*, deprecated, renamed: "ColonyID.ProductSessionVersion")
public typealias ProductSessionVersionDomain = ColonyID.ProductSessionVersion
@available(*, deprecated, renamed: "ColonyID.ShareToken")
public typealias ShareTokenDomain = ColonyID.ShareToken

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
