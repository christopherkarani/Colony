public enum ColonyBudgetError: Error, Sendable, Equatable {
    case toolDefinitionsExceedHardRequestTokenLimit(
        requestHardTokenLimit: Int,
        toolTokenCount: Int,
        toolCount: Int
    )
}
