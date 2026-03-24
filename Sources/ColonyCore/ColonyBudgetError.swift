/// Errors that can occur when token budgets are exceeded.
public enum BudgetError: Error, Sendable, Equatable {
    /// Tool definitions together exceed the hard request token limit.
    ///
    /// Contains the configured limit, actual tool token count, and tool count.
    case toolDefinitionsExceedHardRequestTokenLimit(
        requestHardTokenLimit: Int,
        toolTokenCount: Int,
        toolCount: Int
    )
}

// MARK: - Backward Compatibility

@available(*, deprecated, renamed: "BudgetError")
public typealias ColonyBudgetError = BudgetError
