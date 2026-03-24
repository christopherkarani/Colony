import Foundation

/// Unified resource management policy that combines context window management,
/// compression/summarization, and working memory (scratchbook) configuration.
public struct ColonyResourcePolicy: Sendable {
    /// Policy for managing the context window size and thresholds
    public var contextWindow: ContextWindowPolicy

    /// Optional policy for context compression and summarization
    public var compression: ContextCompressionPolicy?

    /// Policy for working memory (scratchbook) configuration
    public var workingMemory: WorkingMemoryPolicy

    /// Creates a new resource policy with the specified configuration
    public init(
        contextWindow: ContextWindowPolicy = .default,
        compression: ContextCompressionPolicy? = nil,
        workingMemory: WorkingMemoryPolicy = .default
    ) {
        self.contextWindow = contextWindow
        self.compression = compression
        self.workingMemory = workingMemory
    }

    /// Default resource policy suitable for cloud-based models
    public static var `default`: ColonyResourcePolicy {
        ColonyResourcePolicy(
            contextWindow: .default,
            compression: .default,
            workingMemory: .default
        )
    }

    /// Resource policy optimized for on-device models with strict token limits
    public static var onDevice4k: ColonyResourcePolicy {
        ColonyResourcePolicy(
            contextWindow: .onDevice4k,
            compression: .onDevice4k,
            workingMemory: .onDevice4k
        )
    }
}

// MARK: - ContextWindowPolicy

/// Policy for managing the context window size and compaction thresholds
public struct ContextWindowPolicy: Sendable {
    /// Maximum tokens allowed in the context window
    public var maxTokens: Int

    /// Token threshold at which compaction should trigger
    public var compactionThreshold: Int

    /// Token threshold at which summarization should trigger
    public var summarizationThreshold: Int

    /// Creates a new context window policy
    public init(
        maxTokens: Int,
        compactionThreshold: Int,
        summarizationThreshold: Int
    ) {
        self.maxTokens = max(1, maxTokens)
        self.compactionThreshold = max(1, compactionThreshold)
        self.summarizationThreshold = max(1, summarizationThreshold)
    }

    /// Default context window policy for cloud-based models
    public static var `default`: ContextWindowPolicy {
        ContextWindowPolicy(
            maxTokens: 200_000,
            compactionThreshold: 12_000,
            summarizationThreshold: 170_000
        )
    }

    /// Context window policy optimized for on-device models (~4k token budget)
    public static var onDevice4k: ContextWindowPolicy {
        ContextWindowPolicy(
            maxTokens: 4_000,
            compactionThreshold: 2_600,
            summarizationThreshold: 3_200
        )
    }
}

// MARK: - ContextCompressionPolicy

/// Policy for context compression through summarization and tool result eviction
public struct ContextCompressionPolicy: Sendable {
    /// Maximum tokens to keep after summarization
    public var maxSummarizedTokens: Int

    /// Minimum tokens required before summarization triggers
    public var minTokensToSummarize: Int

    /// Maximum tokens allowed for individual tool results before eviction
    public var maxToolResultTokens: Int

    /// Number of recent messages to preserve during summarization
    public var keepLastMessages: Int

    /// Creates a new context compression policy
    public init(
        maxSummarizedTokens: Int,
        minTokensToSummarize: Int,
        maxToolResultTokens: Int,
        keepLastMessages: Int
    ) {
        self.maxSummarizedTokens = max(1, maxSummarizedTokens)
        self.minTokensToSummarize = max(1, minTokensToSummarize)
        self.maxToolResultTokens = max(1, maxToolResultTokens)
        self.keepLastMessages = max(0, keepLastMessages)
    }

    /// Default compression policy for cloud-based models
    public static var `default`: ContextCompressionPolicy {
        ContextCompressionPolicy(
            maxSummarizedTokens: 150_000,
            minTokensToSummarize: 170_000,
            maxToolResultTokens: 20_000,
            keepLastMessages: 6
        )
    }

    /// Compression policy optimized for on-device models
    public static var onDevice4k: ContextCompressionPolicy {
        ContextCompressionPolicy(
            maxSummarizedTokens: 2_800,
            minTokensToSummarize: 3_200,
            maxToolResultTokens: 700,
            keepLastMessages: 4
        )
    }
}

// MARK: - WorkingMemoryPolicy

/// Policy for working memory (scratchbook) configuration
public struct WorkingMemoryPolicy: Sendable {
    /// Whether working memory is enabled
    public var enabled: Bool

    /// Maximum number of items to store in working memory
    public var maxItems: Int

    /// Persistence strategy for working memory
    public var persistence: PersistenceStrategy

    /// Token limit for rendering working memory in context
    public var viewTokenLimit: Int

    /// Maximum number of items to render in context
    public var maxRenderedItems: Int

    /// Whether to automatically compact working memory when limits are exceeded
    public var autoCompact: Bool

    /// Creates a new working memory policy
    public init(
        enabled: Bool = true,
        maxItems: Int = 100,
        persistence: PersistenceStrategy = .transient,
        viewTokenLimit: Int = 800,
        maxRenderedItems: Int = 40,
        autoCompact: Bool = true
    ) {
        self.enabled = enabled
        self.maxItems = max(0, maxItems)
        self.persistence = persistence
        self.viewTokenLimit = max(0, viewTokenLimit)
        self.maxRenderedItems = max(0, maxRenderedItems)
        self.autoCompact = autoCompact
    }

    /// Default working memory policy
    public static var `default`: WorkingMemoryPolicy {
        WorkingMemoryPolicy(
            enabled: false,
            maxItems: 100,
            persistence: .transient,
            viewTokenLimit: 800,
            maxRenderedItems: 40,
            autoCompact: true
        )
    }

    /// Working memory policy optimized for on-device models
    public static var onDevice4k: WorkingMemoryPolicy {
        WorkingMemoryPolicy(
            enabled: true,
            maxItems: 50,
            persistence: .transient,
            viewTokenLimit: 400,
            maxRenderedItems: 20,
            autoCompact: true
        )
    }
}

// MARK: - PersistenceStrategy

extension WorkingMemoryPolicy {
    /// Strategy for persisting working memory items
    public enum PersistenceStrategy: Sendable {
        /// Working memory is kept in memory only (transient)
        case transient

        /// Working memory is persisted to the filesystem
        case filesystem(root: ColonyVirtualPath)
    }
}

// MARK: - Migration Support

extension ColonyResourcePolicy {
    /// Creates a resource policy from legacy policy types
    @available(*, deprecated, message: "Use ColonyResourcePolicy.init directly")
    public init(
        compactionPolicy: ColonyCompactionPolicy,
        summarizationPolicy: ColonySummarizationPolicy?,
        scratchbookPolicy: ColonyScratchbookPolicy
    ) {
        // Map compaction policy to context window
        let contextWindow: ContextWindowPolicy
        switch compactionPolicy {
        case .disabled:
            contextWindow = ContextWindowPolicy(
                maxTokens: Int.max,
                compactionThreshold: Int.max,
                summarizationThreshold: Int.max
            )
        case .maxMessages(let max):
            // Approximate tokens from messages (rough heuristic)
            contextWindow = ContextWindowPolicy(
                maxTokens: max * 200,
                compactionThreshold: max * 150,
                summarizationThreshold: max * 180
            )
        case .maxTokens(let max):
            contextWindow = ContextWindowPolicy(
                maxTokens: max,
                compactionThreshold: Int(Double(max) * 0.65),
                summarizationThreshold: Int(Double(max) * 0.8)
            )
        }

        // Map summarization policy to compression
        let compression: ContextCompressionPolicy?
        if let summarization = summarizationPolicy {
            compression = ContextCompressionPolicy(
                maxSummarizedTokens: summarization.triggerTokens,
                minTokensToSummarize: summarization.triggerTokens,
                maxToolResultTokens: 20_000,
                keepLastMessages: summarization.keepLastMessages
            )
        } else {
            compression = nil
        }

        // Map scratchbook policy to working memory
        let workingMemory = WorkingMemoryPolicy(
            enabled: true,
            maxItems: scratchbookPolicy.maxRenderedItems * 3,
            persistence: .filesystem(root: scratchbookPolicy.pathPrefix),
            viewTokenLimit: scratchbookPolicy.viewTokenLimit,
            maxRenderedItems: scratchbookPolicy.maxRenderedItems,
            autoCompact: scratchbookPolicy.autoCompact ?? true
        )

        self.contextWindow = contextWindow
        self.compression = compression
        self.workingMemory = workingMemory
    }
}
