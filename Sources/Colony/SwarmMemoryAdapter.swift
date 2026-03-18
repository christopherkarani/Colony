import Foundation
import ColonyCore
import Swarm

/// Adapts Swarm's `Memory` protocol to Colony's `ColonyMemoryBackend`.
///
/// This adapter bridges two different memory paradigms:
/// - **Colony** uses structured recall (query → scored items with IDs) and remember (content → stored ID).
/// - **Swarm** uses conversational memory (query → token-budgeted context string) and message-based storage.
///
/// When backed by `WaxMemory`, recall uses Wax's hybrid FTS5 + vector search with token budgeting.
/// When backed by `InMemoryBackend`, provides simple in-memory recall for testing.
///
/// ## Usage
///
/// ```swift
/// // Persistent Wax-backed memory
/// let waxMemory = try await WaxMemory(url: dbURL)
/// let adapter = SwarmMemoryAdapter(waxMemory)
///
/// // Use with Colony runtime
/// let runtime = try ColonyAgentFactory().makeRuntime(
///     profile: .cloud,
///     modelName: "gpt-4",
///     memory: adapter
/// )
/// ```
public final class SwarmMemoryAdapter: ColonyMemoryBackend, @unchecked Sendable {
    private let memory: any Memory
    private let lock = NSLock()
    private var nextID: UInt64 = 1

    /// Creates an adapter wrapping any Swarm `Memory` implementation.
    ///
    /// - Parameter memory: The Swarm memory backend to wrap.
    ///   Use `WaxMemory` for persistent, GPU-accelerated RAG,
    ///   or `InMemoryBackend` for testing.
    public init(_ memory: any Memory) {
        self.memory = memory
    }

    public func recall(_ request: ColonyMemoryRecallRequest) async throws -> ColonyMemoryRecallResult {
        let limit = request.limit ?? 5
        // Heuristic: ~800 tokens per item slot gives a reasonable context budget.
        let tokenBudget = limit * 800
        let context = await memory.context(for: request.query, tokenLimit: tokenBudget)

        guard !context.isEmpty else {
            return ColonyMemoryRecallResult(items: [])
        }

        let item = ColonyMemoryItem(
            id: "swarm-recall",
            content: context,
            tags: [],
            metadata: ["source": "swarm-memory"],
            score: 1.0
        )
        return ColonyMemoryRecallResult(items: [item])
    }

    public func remember(_ request: ColonyMemoryRememberRequest) async throws -> ColonyMemoryRememberResult {
        let id: String = {
            lock.lock()
            defer { lock.unlock() }
            let current = nextID
            nextID += 1
            return "swarm-mem-\(current)"
        }()

        var metadata = request.metadata
        for tag in request.tags {
            metadata["tag:\(tag)"] = tag
        }

        await memory.add(
            MemoryMessage(
                role: .user,
                content: request.content,
                metadata: metadata
            )
        )

        return ColonyMemoryRememberResult(id: id)
    }
}
