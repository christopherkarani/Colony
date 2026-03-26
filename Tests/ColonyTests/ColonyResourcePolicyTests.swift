import Testing
@testable import ColonyCore

@Suite("ColonyResourcePolicy Tests")
struct ColonyResourcePolicyTests {

    // MARK: - ContextWindowPolicy Tests

    @Test("ContextWindowPolicy default values")
    func contextWindowPolicyDefault() {
        let policy = ContextWindowPolicy.default

        #expect(policy.maxTokens == 200_000)
        #expect(policy.compactionThreshold == 12_000)
        #expect(policy.summarizationThreshold == 170_000)
    }

    @Test("ContextWindowPolicy onDevice4k values")
    func contextWindowPolicyOnDevice4k() {
        let policy = ContextWindowPolicy.onDevice4k

        #expect(policy.maxTokens == 4_000)
        #expect(policy.compactionThreshold == 2_600)
        #expect(policy.summarizationThreshold == 3_200)
    }

    @Test("ContextWindowPolicy enforces minimum values")
    func contextWindowPolicyEnforcesMinimums() {
        let policy = ContextWindowPolicy(
            maxTokens: 0,
            compactionThreshold: -1,
            summarizationThreshold: -100
        )

        #expect(policy.maxTokens == 1)
        #expect(policy.compactionThreshold == 1)
        #expect(policy.summarizationThreshold == 1)
    }

    // MARK: - ContextCompressionPolicy Tests

    @Test("ContextCompressionPolicy default values")
    func compressionPolicyDefault() {
        let policy = ContextCompressionPolicy.default

        #expect(policy.maxSummarizedTokens == 150_000)
        #expect(policy.minTokensToSummarize == 170_000)
        #expect(policy.maxToolResultTokens == 20_000)
        #expect(policy.keepLastMessages == 6)
    }

    @Test("ContextCompressionPolicy onDevice4k values")
    func compressionPolicyOnDevice4k() {
        let policy = ContextCompressionPolicy.onDevice4k

        #expect(policy.maxSummarizedTokens == 2_800)
        #expect(policy.minTokensToSummarize == 3_200)
        #expect(policy.maxToolResultTokens == 700)
        #expect(policy.keepLastMessages == 4)
    }

    @Test("ContextCompressionPolicy enforces minimum values")
    func compressionPolicyEnforcesMinimums() {
        let policy = ContextCompressionPolicy(
            maxSummarizedTokens: 0,
            minTokensToSummarize: -1,
            maxToolResultTokens: -10,
            keepLastMessages: -5
        )

        #expect(policy.maxSummarizedTokens == 1)
        #expect(policy.minTokensToSummarize == 1)
        #expect(policy.maxToolResultTokens == 1)
        #expect(policy.keepLastMessages == 0)
    }

    // MARK: - WorkingMemoryPolicy Tests

    @Test("WorkingMemoryPolicy default values")
    func workingMemoryPolicyDefault() {
        let policy = WorkingMemoryPolicy.default

        #expect(policy.enabled == false)
        #expect(policy.maxItems == 100)
        #expect(policy.viewTokenLimit == 800)
        #expect(policy.maxRenderedItems == 40)
        #expect(policy.autoCompact == true)

        if case .transient = policy.persistence {
            // Expected
        } else {
            Issue.record("Expected transient persistence strategy")
        }
    }

    @Test("WorkingMemoryPolicy onDevice4k values")
    func workingMemoryPolicyOnDevice4k() {
        let policy = WorkingMemoryPolicy.onDevice4k

        #expect(policy.enabled == true)
        #expect(policy.maxItems == 50)
        #expect(policy.viewTokenLimit == 400)
        #expect(policy.maxRenderedItems == 20)
        #expect(policy.autoCompact == true)
    }

    @Test("WorkingMemoryPolicy enforces minimum values")
    func workingMemoryPolicyEnforcesMinimums() {
        let policy = WorkingMemoryPolicy(
            enabled: true,
            maxItems: -10,
            viewTokenLimit: -5,
            maxRenderedItems: -1,
            autoCompact: false
        )

        #expect(policy.maxItems == 0)
        #expect(policy.viewTokenLimit == 0)
        #expect(policy.maxRenderedItems == 0)
        #expect(policy.autoCompact == false)
    }

    @Test("WorkingMemoryPolicy filesystem persistence")
    func workingMemoryPolicyFilesystemPersistence() throws {
        let path = try ColonyVirtualPath("/scratchbook")
        let policy = WorkingMemoryPolicy(
            enabled: true,
            persistence: .filesystem(root: path)
        )

        #expect(policy.enabled == true)

        if case .filesystem(let root) = policy.persistence {
            #expect(root == path)
        } else {
            Issue.record("Expected filesystem persistence strategy")
        }
    }

    // MARK: - ColonyResourcePolicy Tests

    @Test("ColonyResourcePolicy default values")
    func resourcePolicyDefault() {
        let policy = ColonyResourcePolicy.default

        #expect(policy.contextWindow.maxTokens == 200_000)
        #expect(policy.compression?.maxSummarizedTokens == 150_000)
        #expect(policy.workingMemory.enabled == false)
    }

    @Test("ColonyResourcePolicy onDevice4k values")
    func resourcePolicyOnDevice4k() {
        let policy = ColonyResourcePolicy.onDevice4k

        #expect(policy.contextWindow.maxTokens == 4_000)
        #expect(policy.compression?.maxSummarizedTokens == 2_800)
        #expect(policy.workingMemory.enabled == true)
    }

    @Test("ColonyResourcePolicy custom initialization")
    func resourcePolicyCustomInit() {
        let contextWindow = ContextWindowPolicy(
            maxTokens: 10_000,
            compactionThreshold: 8_000,
            summarizationThreshold: 9_000
        )

        let compression = ContextCompressionPolicy(
            maxSummarizedTokens: 7_000,
            minTokensToSummarize: 9_000,
            maxToolResultTokens: 5_000,
            keepLastMessages: 10
        )

        let workingMemory = WorkingMemoryPolicy(
            enabled: true,
            maxItems: 200,
            persistence: .transient,
            viewTokenLimit: 1_000,
            maxRenderedItems: 50,
            autoCompact: false
        )

        let policy = ColonyResourcePolicy(
            contextWindow: contextWindow,
            compression: compression,
            workingMemory: workingMemory
        )

        #expect(policy.contextWindow.maxTokens == 10_000)
        #expect(policy.compression?.maxSummarizedTokens == 7_000)
        #expect(policy.workingMemory.maxItems == 200)
        #expect(policy.workingMemory.autoCompact == false)
    }

    @Test("ColonyResourcePolicy without compression")
    func resourcePolicyWithoutCompression() {
        let policy = ColonyResourcePolicy(
            contextWindow: .default,
            compression: nil,
            workingMemory: .default
        )

        #expect(policy.compression == nil)
    }

    // MARK: - Migration Support Tests

    @Test("Migration from legacy compaction policy - disabled")
    func migrationFromDisabledCompaction() {
        let legacyCompaction = ColonyCompactionPolicy.disabled
        let policy = ColonyResourcePolicy(
            compactionPolicy: legacyCompaction,
            summarizationPolicy: nil,
            scratchbookPolicy: ColonyScratchbookPolicy()
        )

        #expect(policy.contextWindow.maxTokens == Int.max)
        #expect(policy.compression == nil)
    }

    @Test("Migration from legacy compaction policy - maxMessages")
    func migrationFromMaxMessagesCompaction() {
        let legacyCompaction = ColonyCompactionPolicy.maxMessages(100)
        let policy = ColonyResourcePolicy(
            compactionPolicy: legacyCompaction,
            summarizationPolicy: nil,
            scratchbookPolicy: ColonyScratchbookPolicy()
        )

        #expect(policy.contextWindow.maxTokens == 20_000) // 100 * 200
        #expect(policy.contextWindow.compactionThreshold == 15_000) // 100 * 150
    }

    @Test("Migration from legacy compaction policy - maxTokens")
    func migrationFromMaxTokensCompaction() {
        let legacyCompaction = ColonyCompactionPolicy.maxTokens(10_000)
        let policy = ColonyResourcePolicy(
            compactionPolicy: legacyCompaction,
            summarizationPolicy: nil,
            scratchbookPolicy: ColonyScratchbookPolicy()
        )

        #expect(policy.contextWindow.maxTokens == 10_000)
        #expect(policy.contextWindow.compactionThreshold == 6_500) // 65% of max
        #expect(policy.contextWindow.summarizationThreshold == 8_000) // 80% of max
    }

    @Test("Migration from legacy summarization policy")
    func migrationFromSummarizationPolicy() throws {
        let legacySummarization = ColonySummarizationPolicy(
            triggerTokens: 50_000,
            keepLastMessages: 8,
            historyPathPrefix: try ColonyVirtualPath("/history")
        )

        let policy = ColonyResourcePolicy(
            compactionPolicy: .maxTokens(100_000),
            summarizationPolicy: legacySummarization,
            scratchbookPolicy: ColonyScratchbookPolicy()
        )

        #expect(policy.compression?.maxSummarizedTokens == 50_000)
        #expect(policy.compression?.minTokensToSummarize == 50_000)
        #expect(policy.compression?.keepLastMessages == 8)
    }

    @Test("Migration from legacy scratchbook policy")
    func migrationFromScratchbookPolicy() throws {
        let legacyScratchbook = ColonyScratchbookPolicy(
            pathPrefix: try ColonyVirtualPath("/scratch"),
            viewTokenLimit: 500,
            maxRenderedItems: 30,
            autoCompact: false
        )

        let policy = ColonyResourcePolicy(
            compactionPolicy: .disabled,
            summarizationPolicy: nil,
            scratchbookPolicy: legacyScratchbook
        )

        #expect(policy.workingMemory.enabled == true)
        #expect(policy.workingMemory.maxItems == 90) // 30 * 3
        #expect(policy.workingMemory.viewTokenLimit == 500)
        #expect(policy.workingMemory.maxRenderedItems == 30)
        #expect(policy.workingMemory.autoCompact == false)

        if case .filesystem(let root) = policy.workingMemory.persistence {
            let expectedPath = try ColonyVirtualPath("/scratch")
            #expect(root == expectedPath)
        } else {
            Issue.record("Expected filesystem persistence")
        }
    }
}
