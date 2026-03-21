public struct ColonyScratchbookPolicy: Sendable {
    public var pathPrefix: ColonyVirtualPath
    public var viewTokenLimit: Int
    public var maxRenderedItems: Int
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

    public static var defaultPathPrefix: ColonyVirtualPath {
        // swiftlint:disable:next force_try
        try! ColonyVirtualPath("/scratchbook")
    }
}

