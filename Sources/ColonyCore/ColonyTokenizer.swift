import HiveCore

public protocol ColonyTokenizer: Sendable {
    func countTokens(_ messages: [HiveChatMessage]) -> Int
}

/// Cheap, deterministic fallback tokenizer.
///
/// Notes:
/// - This is an approximation intended for compaction thresholds, not billing.
/// - Uses a conservative 4 chars/token heuristic to avoid oversending context.
public struct ColonyApproximateTokenizer: ColonyTokenizer, Sendable {
    public init() {}

    public func countTokens(_ messages: [HiveChatMessage]) -> Int {
        let chars = messages.reduce(into: 0) { partial, message in
            partial += message.content.count
            partial += message.name?.count ?? 0
            partial += message.toolCallID?.count ?? 0
            partial += message.toolCalls.reduce(into: 0) { toolPartial, call in
                toolPartial += call.id.count + call.name.count + call.argumentsJSON.count
            }
        }
        return max(1, chars / 4)
    }
}

