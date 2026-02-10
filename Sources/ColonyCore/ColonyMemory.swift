import Foundation

public struct ColonyMemoryItem: Sendable, Codable, Equatable {
    public var id: String
    public var content: String
    public var tags: [String]
    public var metadata: [String: String]
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

public struct ColonyMemoryRecallRequest: Sendable, Codable, Equatable {
    public var query: String
    public var limit: Int?

    public init(query: String, limit: Int? = nil) {
        self.query = query
        self.limit = limit
    }
}

public struct ColonyMemoryRecallResult: Sendable, Codable, Equatable {
    public var items: [ColonyMemoryItem]

    public init(items: [ColonyMemoryItem]) {
        self.items = items
    }
}

public struct ColonyMemoryRememberRequest: Sendable, Codable, Equatable {
    public var content: String
    public var tags: [String]
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

public struct ColonyMemoryRememberResult: Sendable, Codable, Equatable {
    public var id: String

    public init(id: String) {
        self.id = id
    }
}

public protocol ColonyMemoryBackend: Sendable {
    func recall(_ request: ColonyMemoryRecallRequest) async throws -> ColonyMemoryRecallResult
    func remember(_ request: ColonyMemoryRememberRequest) async throws -> ColonyMemoryRememberResult
}

public actor ColonyInMemoryMemoryBackend: ColonyMemoryBackend {
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

    public func recall(_ request: ColonyMemoryRecallRequest) async throws -> ColonyMemoryRecallResult {
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

        let recallItems = sorted.prefix(limit).map { ranked in
            ColonyMemoryItem(
                id: ranked.item.id,
                content: ranked.item.content,
                tags: ranked.item.tags,
                metadata: ranked.item.metadata,
                score: ranked.score
            )
        }
        return ColonyMemoryRecallResult(items: recallItems)
    }

    public func remember(_ request: ColonyMemoryRememberRequest) async throws -> ColonyMemoryRememberResult {
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
        return ColonyMemoryRememberResult(id: id)
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
