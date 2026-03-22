/// Errors related to token budget violations during context preparation.
///
/// These errors arise before a run starts when the configured tool set or messages
/// exceed the hard token limits set in `ColonyConfiguration.ContextConfiguration`.
public enum ColonyBudgetError: Error, Sendable, Equatable {
    /// The combined token count of all tool definitions exceeds the hard token limit.
    case toolDefinitionsExceedHardRequestTokenLimit(
        requestHardTokenLimit: Int,
        toolTokenCount: Int,
        toolCount: Int
    )
}
