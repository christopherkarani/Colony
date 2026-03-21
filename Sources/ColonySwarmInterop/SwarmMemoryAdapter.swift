import Foundation
import ColonyCore
import Colony
import Swarm

/// Adapts Swarm's `Memory` protocol to Colony's `ColonyMemoryBackend`.
///
/// This adapter bridges two different memory paradigms:
/// - **Colony** uses structured recall (query → scored items with IDs) and remember (content → stored ID).
/// - **Swarm** uses conversational memory (query → token-budgeted context string) and message-based storage.
///
/// When backed by `WaxMemory`, recall can fall back to Wax's contextual query result when no local messages exist.
/// When backed by `PersistentMemory(backend: InMemoryBackend())`, recall provides simple in-memory query scoring.
///
/// ## Usage
///
/// ```swift
/// // Persistent Wax-backed memory
/// let waxMemory = try await WaxMemory(url: dbURL)
/// let adapter = ColonySwarmMemoryAdapter(waxMemory)
///
/// // Persistent in-memory backend for tests
/// let adapter = ColonySwarmMemoryAdapter(backend: InMemoryBackend(), conversationID: "test")
///
/// // Use with Colony runtime
/// let bootstrap = ColonyBootstrap()
/// let runtime = try await bootstrap.makeRuntime(options: .init(
///     profile: .cloud,
///     modelName: "gpt-4",
///     memory: adapter
/// ))
/// ```
public struct ColonySwarmMemoryAdapter: ColonyMemoryBackend, Sendable {
    private let memory: any Memory

    /// Creates an adapter wrapping any Swarm `Memory` implementation.
    ///
    /// - Parameter memory: The Swarm memory backend to wrap.
    ///   Use `WaxMemory` for persistent, GPU-accelerated RAG,
    ///   or `PersistentMemory(backend: InMemoryBackend())` for testing.
    public init(_ memory: any Memory) {
        self.memory = memory
    }

    public init(
        backend: any PersistentMemoryBackend,
        conversationID: String = UUID().uuidString,
        maxMessages: Int = 0,
        tokenEstimator: any TokenEstimator = CharacterBasedTokenEstimator.shared
    ) {
        self.memory = PersistentMemory(
            backend: backend,
            conversationId: conversationID,
            maxMessages: maxMessages,
            tokenEstimator: tokenEstimator
        )
    }

    public func recall(_ request: ColonyMemory.RecallRequest) async throws -> ColonyMemory.RecallResult {
        let limit = request.limit ?? 5
        let normalizedLimit = min(100, max(1, limit))
        let trimmedQuery = request.query.trimmingCharacters(in: .whitespacesAndNewlines)
        let messages = await memory.allMessages()

        let ranked: [(message: MemoryMessage, score: Double, index: Int)] = messages.enumerated().compactMap { index, message in
            let score = Self.score(query: trimmedQuery, message: message)
            if trimmedQuery.isEmpty || score > 0 {
                return (message, score, index)
            }
            return nil
        }

        if !ranked.isEmpty {
            let items = ranked
                .sorted { lhs, rhs in
                    if lhs.score == rhs.score {
                        return lhs.index > rhs.index
                    }
                    return lhs.score > rhs.score
                }
                .prefix(normalizedLimit)
                .map { entry in
                    ColonyMemory.Item(
                        id: entry.message.id.uuidString,
                        content: entry.message.formattedContent,
                        tags: Self.tags(from: entry.message.metadata),
                        metadata: entry.message.metadata,
                        score: entry.score
                    )
                }
            return ColonyMemory.RecallResult(items: items)
        }

        guard messages.isEmpty else { return ColonyMemory.RecallResult(items: []) }

        let tokenBudget = normalizedLimit * 800
        let context = await memory.context(for: request.query, tokenLimit: tokenBudget)
        guard !context.isEmpty else { return ColonyMemory.RecallResult(items: []) }

        return ColonyMemory.RecallResult(items: [
            ColonyMemory.Item(
                id: "swarm-recall",
                content: context,
                tags: [],
                metadata: ["source": "swarm-memory"],
                score: 1.0
            )
        ])
    }

    public func remember(_ request: ColonyMemory.RememberRequest) async throws -> ColonyMemory.RememberResult {
        var metadata = request.metadata
        for tag in request.tags {
            metadata["tag:\(tag)"] = tag
        }

        let message = MemoryMessage(
            id: UUID(),
            role: .user,
            content: request.content,
            metadata: metadata
        )
        await memory.add(message)

        return ColonyMemory.RememberResult(id: message.id.uuidString)
    }

    private static func score(query: String, message: MemoryMessage) -> Double {
        guard !query.isEmpty else { return 1.0 }

        let queryTerms = terms(in: query)
        guard !queryTerms.isEmpty else { return 0 }

        let haystack = ([message.content, message.formattedContent] + message.metadata.map { "\($0.key) \($0.value)" })
            .joined(separator: " ")
        let messageTerms = terms(in: haystack)
        guard !messageTerms.isEmpty else { return 0 }

        let overlap = queryTerms.intersection(messageTerms).count
        if overlap > 0 {
            return Double(overlap) / Double(queryTerms.count)
        }

        if haystack.localizedCaseInsensitiveContains(query) {
            return 0.25
        }

        return 0
    }

    private static func terms(in text: String) -> Set<String> {
        let components = text.lowercased().split { character in
            !character.isLetter && !character.isNumber
        }
        return Set(components.map(String.init).filter { !$0.isEmpty })
    }

    private static func tags(from metadata: [String: String]) -> [String] {
        metadata
            .compactMap { key, value in key.hasPrefix("tag:") ? value : nil }
            .sorted()
    }
}
