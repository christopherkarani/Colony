import Foundation
import HiveCore

// MARK: - Phantom Type Domain Markers

/// Namespace for Colony ID domains.
public enum ColonyIDDomain {
    /// Domain for thread identifiers.
    public enum Thread: Sendable {}

    /// Domain for run identifiers.
    public enum Run: Sendable {}

    /// Domain for run attempt identifiers.
    public enum Attempt: Sendable {}

    /// Domain for checkpoint identifiers.
    public enum Checkpoint: Sendable {}

    /// Domain for interrupt identifiers.
    public enum Interrupt: Sendable {}

    /// Domain for channel identifiers.
    public enum Channel: Sendable {}

    /// Domain for node identifiers.
    public enum Node: Sendable {}

    /// Domain for subagent type identifiers.
    public enum Subagent: Sendable {}

    /// Domain for artifact identifiers.
    public enum Artifact: Sendable {}
}

// MARK: - Generic ID Type

/// A type-safe identifier with a phantom domain marker.
///
/// Use `ColonyID<Domain>` to create strongly-typed identifiers that prevent
/// mixing different ID types at compile time.
///
/// Example:
/// ```swift
/// let threadID: ColonyThreadID = .generate()
/// let runID: ColonyRunID = .generate()
/// ```
public struct ColonyID<Domain>: Sendable, Hashable, Codable, RawRepresentable,
    CustomStringConvertible
{
    public let rawValue: String

    public var description: String { rawValue }

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    /// Creates a new identifier with the given raw value.
    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    /// Generates a new unique identifier with the given prefix.
    ///
    /// - Parameter prefix: A prefix for the identifier (e.g., "thread", "run")
    /// - Returns: A new unique identifier
    public static func generate(prefix: String) -> ColonyID<Domain> {
        ColonyID("\(prefix):\(UUID().uuidString)")
    }

    /// Generates a new unique identifier.
    ///
    /// The generated ID includes a UUID for uniqueness.
    public static func generate() -> ColonyID<Domain> {
        ColonyID(UUID().uuidString)
    }
}

// MARK: - Typealiases for Common IDs

/// Type alias for thread identifiers.
public typealias ColonyThreadID = ColonyID<ColonyIDDomain.Thread>

/// Type alias for run identifiers.
public typealias ColonyRunID = ColonyID<ColonyIDDomain.Run>

/// Type alias for run attempt identifiers.
public typealias ColonyRunAttemptID = ColonyID<ColonyIDDomain.Attempt>

/// Type alias for checkpoint identifiers.
public typealias ColonyCheckpointID = ColonyID<ColonyIDDomain.Checkpoint>

/// Type alias for interrupt identifiers.
public typealias ColonyInterruptID = ColonyID<ColonyIDDomain.Interrupt>

/// Type alias for channel identifiers.
public typealias ColonyChannelID = ColonyID<ColonyIDDomain.Channel>

/// Type alias for node identifiers.
public typealias ColonyNodeID = ColonyID<ColonyIDDomain.Node>

/// Type alias for subagent type identifiers.
public typealias ColonySubagentType = ColonyID<ColonyIDDomain.Subagent>

/// Type alias for artifact identifiers.
public typealias ColonyArtifactID = ColonyID<ColonyIDDomain.Artifact>

// MARK: - Hive Compatibility Extensions

extension ColonyID where Domain == ColonyIDDomain.Thread {
    /// Converts this ColonyThreadID to a HiveThreadID.
    public var hiveThreadID: HiveThreadID {
        HiveThreadID(rawValue)
    }

    /// Creates a ColonyThreadID from a HiveThreadID.
    public init(hiveThreadID: HiveThreadID) {
        self.rawValue = hiveThreadID.rawValue
    }
}

extension ColonyID where Domain == ColonyIDDomain.Run {
    /// Converts this ColonyRunID to a HiveRunID.
    public var hiveRunID: HiveRunID {
        HiveRunID(UUID(uuidString: rawValue) ?? UUID())
    }

    /// Creates a ColonyRunID from a HiveRunID.
    public init(hiveRunID: HiveRunID) {
        self.rawValue = hiveRunID.rawValue.uuidString
    }
}

extension ColonyID where Domain == ColonyIDDomain.Attempt {
    /// Converts this ColonyRunAttemptID to a HiveRunAttemptID.
    public var hiveAttemptID: HiveRunAttemptID {
        HiveRunAttemptID(UUID(uuidString: rawValue) ?? UUID())
    }

    /// Creates a ColonyRunAttemptID from a HiveRunAttemptID.
    public init(hiveAttemptID: HiveRunAttemptID) {
        self.rawValue = hiveAttemptID.rawValue.uuidString
    }
}

extension ColonyID where Domain == ColonyIDDomain.Checkpoint {
    /// Converts this ColonyCheckpointID to a HiveCheckpointID.
    public var hiveCheckpointID: HiveCheckpointID {
        HiveCheckpointID(rawValue)
    }

    /// Creates a ColonyCheckpointID from a HiveCheckpointID.
    public init(hiveCheckpointID: HiveCheckpointID) {
        self.rawValue = hiveCheckpointID.rawValue
    }
}

extension ColonyID where Domain == ColonyIDDomain.Interrupt {
    /// Converts this ColonyInterruptID to a HiveInterruptID.
    public var hiveInterruptID: HiveInterruptID {
        HiveInterruptID(rawValue)
    }

    /// Creates a ColonyInterruptID from a HiveInterruptID.
    public init(hiveInterruptID: HiveInterruptID) {
        self.rawValue = hiveInterruptID.rawValue
    }
}

extension ColonyID where Domain == ColonyIDDomain.Channel {
    /// Converts this ColonyChannelID to a HiveChannelID.
    public var hiveChannelID: HiveChannelID {
        HiveChannelID(rawValue)
    }

    /// Creates a ColonyChannelID from a HiveChannelID.
    public init(hiveChannelID: HiveChannelID) {
        self.rawValue = hiveChannelID.rawValue
    }
}

extension ColonyID where Domain == ColonyIDDomain.Node {
    /// Converts this ColonyNodeID to a HiveNodeID.
    public var hiveNodeID: HiveNodeID {
        HiveNodeID(rawValue)
    }

    /// Creates a ColonyNodeID from a HiveNodeID.
    public init(hiveNodeID: HiveNodeID) {
        self.rawValue = hiveNodeID.rawValue
    }
}

// MARK: - Convenience Factory Methods

extension ColonyID where Domain == ColonyIDDomain.Thread {
    /// Generates a new thread ID with the "colony" prefix.
    public static func generate() -> ColonyThreadID {
        ColonyThreadID("colony:\(UUID().uuidString)")
    }
}

// MARK: - Subagent Type Constants

extension ColonySubagentType {
    /// Research subagent type.
    public static let research = ColonySubagentType("research")

    /// Code subagent type.
    public static let code = ColonySubagentType("code")

    /// Memory subagent type.
    public static let memory = ColonySubagentType("memory")

    /// General subagent type.
    public static let general = ColonySubagentType("general")

    /// Planner subagent type.
    public static let planner = ColonySubagentType("planner")

    /// Reviewer subagent type.
    public static let reviewer = ColonySubagentType("reviewer")

    /// Compactor subagent type for history compaction tasks.
    public static let compactor = ColonySubagentType("compactor")

    /// Creates a custom subagent type with the given identifier.
    public static func custom(_ identifier: String) -> ColonySubagentType {
        ColonySubagentType(identifier)
    }
}
