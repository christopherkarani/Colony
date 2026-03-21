public struct ColonySummarizationPolicy: Sendable {
    public var triggerTokens: Int
    public var keepLastMessages: Int
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

