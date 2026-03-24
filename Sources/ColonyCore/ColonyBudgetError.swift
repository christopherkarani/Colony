public enum BudgetError: Error, Sendable, Equatable {
    case toolDefinitionsExceedHardRequestTokenLimit(
        requestHardTokenLimit: Int,
        toolTokenCount: Int,
        toolCount: Int
    )
}

// MARK: - Backward Compatibility

@available(*, deprecated, renamed: "BudgetError")
public typealias ColonyBudgetError = BudgetError
