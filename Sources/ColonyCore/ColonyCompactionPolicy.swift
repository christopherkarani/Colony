@_spi(ColonyInternal) import Swarm

/// Policy controlling when and how conversation history is compacted.
///
/// `ColonyCompactionPolicy` determines when older messages should be removed
/// from the conversation context to stay within token budgets.
public enum ColonyCompactionPolicy: Sendable {
    /// Compaction is disabled; messages are never automatically removed.
    case disabled
    /// Compact to the most recent N messages.
    case maxMessages(Int)
    /// Compact to fit within the token budget, removing oldest messages first.
    case maxTokens(Int)

    /// Compacts a message list according to this policy.
    ///
    /// - Parameters:
    ///   - messages: The full message list to potentially compact
    ///   - tokenizer: The tokenizer to use for counting tokens
    /// - Returns: A compacted message list, or `nil` if no compaction is needed
    public func compact(
        _ messages: [ColonyMessage],
        tokenizer: any ColonyTokenizer
    ) -> [ColonyMessage]? {
        switch self {
        case .disabled:
            return nil
        case .maxMessages(let maxMessages):
            guard maxMessages > 0 else { return [] }
            guard messages.count > maxMessages else { return nil }
            return Array(messages.suffix(maxMessages))
        case .maxTokens(let maxTokens):
            guard maxTokens > 0 else { return [] }
            if tokenizer.countTokens(messages) <= maxTokens {
                return nil
            }
            var kept = messages
            while kept.isEmpty == false, tokenizer.countTokens(kept) > maxTokens {
                kept.removeFirst()
            }
            return kept
        }
    }
}

package extension ColonyCompactionPolicy {
    func compact(
        _ messages: [HiveChatMessage],
        tokenizer: any ColonyTokenizer
    ) -> [HiveChatMessage]? {
        compact(messages.map(ColonyMessage.init), tokenizer: tokenizer)?.map(\.hiveChatMessage)
    }
}
