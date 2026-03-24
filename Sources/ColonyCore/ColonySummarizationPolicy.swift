/// Policy for when and how to summarize conversation history.
///
/// `ColonySummarizationPolicy` controls the transition from compacting messages
/// (dropping oldest) to summarizing them (compressing content) as the conversation
/// grows longer.
public struct ColonySummarizationPolicy: Sendable {
    /// Token count that triggers summarization.
    ///
    /// When the conversation exceeds this many tokens, summarization should be considered.
    public var triggerTokens: Int
    /// Number of the most recent messages to preserve when summarizing.
    public var keepLastMessages: Int
    /// Virtual path prefix where conversation history files are stored.
    public var historyPathPrefix: ColonyVirtualPath

    public init(
        triggerTokens: Int,
        keepLastMessages: Int,
        historyPathPrefix: ColonyVirtualPath
    ) {
        self.triggerTokens = triggerTokens > 0 ? triggerTokens : Int.max
        self.keepLastMessages = max(0, keepLastMessages)
        self.historyPathPrefix = historyPathPrefix
    }
}

