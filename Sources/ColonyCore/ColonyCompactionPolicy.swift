import HiveCore

public enum ColonyCompactionPolicy: Sendable {
    case disabled
    case maxMessages(Int, anchoredMessageCount: Int = 0)
    case maxTokens(Int, anchoredMessageCount: Int = 0)

    public func compact(
        _ messages: [HiveChatMessage],
        tokenizer: any ColonyTokenizer
    ) -> [HiveChatMessage]? {
        switch self {
        case .disabled:
            return nil
        case .maxMessages(let maxMessages, let anchoredMessageCount):
            guard maxMessages > 0 else { return [] }
            guard messages.count > maxMessages else { return nil }
            let anchorCount = min(anchoredMessageCount, messages.count)
            let anchored = Array(messages.prefix(anchorCount))
            let remaining = Array(messages.dropFirst(anchorCount))
            let budget = maxMessages - anchorCount
            guard budget > 0 else { return anchored }
            return anchored + remaining.suffix(budget)
        case .maxTokens(let maxTokens, let anchoredMessageCount):
            guard maxTokens > 0 else { return [] }
            if tokenizer.countTokens(messages) <= maxTokens {
                return nil
            }
            let anchorCount = min(anchoredMessageCount, messages.count)
            let anchored = Array(messages.prefix(anchorCount))
            var evictable = Array(messages.dropFirst(anchorCount))
            while evictable.isEmpty == false, tokenizer.countTokens(anchored + evictable) > maxTokens {
                evictable.removeFirst()
            }
            return anchored + evictable
        }
    }
}

