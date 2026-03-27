/// Protocol for tokenizing chat messages.
///
/// Implement this protocol to provide custom tokenization logic for message
/// compaction and budget calculations.
public protocol ColonyTokenizer: Sendable {
    /// Counts the number of tokens in a message list.
    ///
    /// - Parameter messages: The messages to count tokens for
    /// - Returns: An approximate token count
    func countTokens(_ messages: [ColonyMessage]) -> Int
}

/// Cheap, deterministic fallback tokenizer.
///
/// Notes:
/// - This is an approximation intended for compaction thresholds, not billing.
/// - Uses a conservative 4 chars/token heuristic to avoid oversending context.
public struct ColonyApproximateTokenizer: ColonyTokenizer, Sendable {
    public init() {}

    public func countTokens(_ messages: [ColonyMessage]) -> Int {
        let chars = messages.reduce(into: 0) { partial, message in
            partial += message.id.count
            partial += message.role.rawValue.count
            partial += message.content.count
            partial += message.name?.count ?? 0
            partial += message.toolCallID?.count ?? 0
            partial += 12 // Conservative per-message structural overhead.
            partial += message.toolCalls.reduce(into: 0) { toolPartial, call in
                toolPartial += call.id.count + call.name.count + call.argumentsJSON.count
            }
        }
        return max(1, chars / 4)
    }
}
