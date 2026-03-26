import Foundation

/// A single item in the persistent memory store.
public struct ColonyMemoryItem: Sendable, Codable, Equatable {
    /// Unique identifier for this memory item.
    public var id: String
    /// The content/text of this memory item.
    public var content: String
    /// Tags for categorizing and filtering this item.
    public var tags: [String]
    /// Arbitrary key-value metadata.
    public var metadata: [String: String]
    /// Relevance score from a search query (set by the service after search).
    public var score: Double?

    public init(
        id: String,
        content: String,
        tags: [String] = [],
        metadata: [String: String] = [:],
        score: Double? = nil
    ) {
        self.id = id
        self.content = content
        self.tags = tags
        self.metadata = metadata
        self.score = score
    }
}

// MARK: - New Request/Response Types (verb-based)

/// Request to search for memory items.
public struct ColonyMemorySearchRequest: Sendable, Codable, Equatable {
    /// The search query string.
    public var query: String
    /// Maximum number of results to return, or `nil` for implementation default.
    public var limit: Int?

    public init(query: String, limit: Int? = nil) {
        self.query = query
        self.limit = limit
    }
}

/// Response containing search results.
public struct ColonyMemorySearchResponse: Sendable, Codable, Equatable {
    /// Matching memory items, ordered by relevance.
    public var items: [ColonyMemoryItem]

    public init(items: [ColonyMemoryItem]) {
        self.items = items
    }
}

/// Request to store a new memory item.
public struct ColonyMemoryStoreRequest: Sendable, Codable, Equatable {
    /// The content to store.
    public var content: String
    /// Tags to associate with this item.
    public var tags: [String]
    /// Arbitrary metadata to store alongside the content.
    public var metadata: [String: String]

    public init(
        content: String,
        tags: [String] = [],
        metadata: [String: String] = [:]
    ) {
        self.content = content
        self.tags = tags
        self.metadata = metadata
    }
}

/// Response after storing a memory item.
public struct ColonyMemoryStoreResponse: Sendable, Codable, Equatable {
    /// The unique identifier assigned to the stored item.
    public var id: String

    public init(id: String) {
        self.id = id
    }
}

// MARK: - Deprecated Request/Response Types

public typealias ColonyMemoryRecallRequest = ColonyMemorySearchRequest

public typealias ColonyMemoryRecallResult = ColonyMemorySearchResponse

public typealias ColonyMemoryRememberRequest = ColonyMemoryStoreRequest

public typealias ColonyMemoryRememberResult = ColonyMemoryStoreResponse

// MARK: - Service Protocol

/// Service protocol for persistent memory operations.
///
/// Implement this protocol to provide custom memory backends for Colony.
/// Memory services store and retrieve semi-permanent information that persists
/// across agent invocations.
public protocol ColonyMemoryService: Sendable {
    /// Searches for memory items matching the query.
    ///
    /// - Parameter request: The search request containing a query string
    /// - Returns: Search results ordered by relevance
    func search(_ request: ColonyMemorySearchRequest) async throws -> ColonyMemorySearchResponse

    /// Stores a new memory item.
    ///
    /// - Parameter request: The store request containing content and metadata
    /// - Returns: A response containing the assigned ID for the new item
    func store(_ request: ColonyMemoryStoreRequest) async throws -> ColonyMemoryStoreResponse
}

// MARK: - Deprecated Protocol Name

public typealias ColonyMemoryBackend = ColonyMemoryService

// MARK: - Deprecated Method Shims

public extension ColonyMemoryService {
    func recall(_ request: ColonyMemoryRecallRequest) async throws -> ColonyMemoryRecallResult {
        try await search(request)
    }

    func remember(_ request: ColonyMemoryRememberRequest) async throws -> ColonyMemoryRememberResult {
        try await store(request)
    }
}

// MARK: - In-Memory Implementation

public actor ColonyInMemoryMemoryBackend: ColonyMemoryService {
    private struct StoredMemory: Sendable {
        var id: String
        var content: String
        var tags: [String]
        var metadata: [String: String]
    }

    private var nextID: UInt64
    private var items: [StoredMemory]

    public init(
        nextID: UInt64 = 1,
        items: [ColonyMemoryItem] = []
    ) {
        let seededNextID = Self.nextIDFloor(from: items)
        self.nextID = max(1, max(nextID, seededNextID))
        self.items = items.map {
            StoredMemory(
                id: $0.id,
                content: $0.content,
                tags: $0.tags,
                metadata: $0.metadata
            )
        }
    }

    public func search(_ request: ColonyMemorySearchRequest) async throws -> ColonyMemorySearchResponse {
        let query = request.query.trimmingCharacters(in: .whitespacesAndNewlines)
        let limit = min(100, max(1, request.limit ?? 5))

        let scored: [(item: StoredMemory, score: Double)] = items.map { item in
            (item, score(query: query, item: item))
        }

        let filtered: [(item: StoredMemory, score: Double)]
        if query.isEmpty {
            filtered = scored
        } else {
            filtered = scored.filter { $0.score > 0 }
        }

        let sorted = filtered.sorted { lhs, rhs in
            if lhs.score == rhs.score {
                return lhs.item.id.utf8.lexicographicallyPrecedes(rhs.item.id.utf8)
            }
            return lhs.score > rhs.score
        }

        let searchItems = sorted.prefix(limit).map { ranked in
            ColonyMemoryItem(
                id: ranked.item.id,
                content: ranked.item.content,
                tags: ranked.item.tags,
                metadata: ranked.item.metadata,
                score: ranked.score
            )
        }
        return ColonyMemorySearchResponse(items: searchItems)
    }

    public func store(_ request: ColonyMemoryStoreRequest) async throws -> ColonyMemoryStoreResponse {
        let id = "mem-" + String(nextID)
        nextID += 1

        items.append(
            StoredMemory(
                id: id,
                content: request.content,
                tags: request.tags,
                metadata: request.metadata
            )
        )
        return ColonyMemoryStoreResponse(id: id)
    }

    private func score(query: String, item: StoredMemory) -> Double {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedQuery.isEmpty == false else { return 1.0 }

        let queryTerms = Self.terms(in: trimmedQuery)
        guard queryTerms.isEmpty == false else { return 0 }

        let haystack = ([item.content] + item.tags + item.metadata.map { "\($0.key) \($0.value)" })
            .joined(separator: " ")
        let memoryTerms = Self.terms(in: haystack)
        guard memoryTerms.isEmpty == false else { return 0 }

        let overlap = queryTerms.intersection(memoryTerms).count
        if overlap > 0 {
            return Double(overlap) / Double(queryTerms.count)
        }

        if haystack.lowercased().contains(trimmedQuery.lowercased()) {
            return 0.25
        }

        return 0
    }

    private static func terms(in text: String) -> Set<String> {
        let lowercase = text.lowercased()
        let components = lowercase.split { character in
            character.isLetter == false && character.isNumber == false
        }
        return Set(components.map(String.init).filter { $0.isEmpty == false })
    }

    private static func nextIDFloor(from items: [ColonyMemoryItem]) -> UInt64 {
        let maxExisting = items.reduce(0 as UInt64) { currentMax, item in
            guard item.id.hasPrefix("mem-") else { return currentMax }
            let suffix = item.id.dropFirst("mem-".count)
            guard let parsed = UInt64(suffix) else { return currentMax }
            return max(currentMax, parsed)
        }
        return maxExisting + 1
    }
}
