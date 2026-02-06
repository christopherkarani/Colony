import HiveCore

public enum ColonyCompactionPolicy: Sendable {
    case disabled
    case maxMessages(Int)
    case maxTokens(Int)

    public func compact(
        _ messages: [HiveChatMessage],
        tokenizer: any ColonyTokenizer
    ) -> [HiveChatMessage]? {
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

