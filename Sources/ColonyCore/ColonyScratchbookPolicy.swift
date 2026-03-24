/// Policy configuration for the scratchbook/workspace feature.
///
/// `ColonyScratchbookPolicy` controls where scratchbook data is stored and how
/// it's rendered in the system prompt.
public struct ColonyScratchbookPolicy: Sendable {
    /// Virtual path prefix where scratchbook files are stored.
    public var pathPrefix: ColonyVirtualPath
    /// Token budget for the scratchbook view rendered in the system prompt.
    public var viewTokenLimit: Int
    /// Maximum number of items to include in the scratchbook view.
    public var maxRenderedItems: Int
    /// Whether to automatically compact the scratchbook when it grows large.
    public var autoCompact: Bool?

    public init(
        pathPrefix: ColonyVirtualPath = Self.defaultPathPrefix,
        viewTokenLimit: Int = 800,
        maxRenderedItems: Int = 40,
        autoCompact: Bool? = true
    ) {
        self.pathPrefix = pathPrefix
        self.viewTokenLimit = max(0, viewTokenLimit)
        self.maxRenderedItems = max(0, maxRenderedItems)
        self.autoCompact = autoCompact
    }

    /// Default path prefix at `/scratchbook`.
    public static var defaultPathPrefix: ColonyVirtualPath {
        ColonyVirtualPath.scratchbookRoot
    }
}
