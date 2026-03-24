/// Defines the operational mode for an agent, determining its specialized behavior and capabilities.
///
/// Use `AgentMode` to configure an agent for specific types of tasks:
/// - ``generalPurpose``: General-purpose agent suitable for a wide range of tasks
/// - ``code``: Specialized for software development, debugging, and code review
/// - ``research``: Optimized for information gathering, analysis, and comparison
/// - ``knowledge``: Focused on memory operations and context retrieval
///
/// ## Example
/// ```swift
/// let runtime = try factory.makeRuntime(
///     profile: .cloud,
///     modelName: "claude-sonnet-4",
///     lane: .code  // Use coding mode for development tasks
/// )
/// ```
public enum AgentMode: String, Sendable, CaseIterable {
    /// General-purpose agent suitable for a wide range of tasks.
    case generalPurpose

    /// Specialized for software development, debugging, and code review.
    case code

    /// Optimized for information gathering, analysis, and comparison.
    case research

    /// Focused on memory operations and context retrieval.
    case knowledge
}

// MARK: - Backward Compatibility

/// Deprecated type alias for backward compatibility.
///
/// Use ``AgentMode`` instead.
@available(*, deprecated, renamed: "AgentMode")
public typealias ColonyLane = AgentMode

extension AgentMode {
    /// Deprecated: Use ``generalPurpose`` instead.
    @available(*, deprecated, renamed: "generalPurpose")
    public static let general: Self = .generalPurpose

    /// Deprecated: Use ``code`` instead.
    @available(*, deprecated, renamed: "code")
    public static let coding: Self = .code

    /// Deprecated: Use ``knowledge`` instead.
    @available(*, deprecated, renamed: "knowledge")
    public static let memory: Self = .knowledge
}
