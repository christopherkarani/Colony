import Foundation
import ColonyCore
import MembraneWax

public actor ColonyWaxMemoryBackend: ColonyMemoryBackend {
    private enum MetadataKey {
        static let entry = "colony.memory.entry"
        static let logicalID = "colony.memory.id"
        static let provenanceBackendID = "colony.memory.provenance.backendID"
        static let provenanceRecordID = "colony.memory.provenance.recordID"
        static let provenanceKind = "colony.memory.provenance.kind"
    }

    private let storage: WaxStorageBackend

    public init(storage: WaxStorageBackend) {
        self.storage = storage
    }

    public static func create(at url: URL) async throws -> ColonyWaxMemoryBackend {
        ColonyWaxMemoryBackend(storage: try await WaxStorageBackend.create(at: url))
    }

    public func recall(_ request: ColonyMemoryRecallRequest) async throws -> ColonyMemoryRecallResult {
        let limit = max(1, min(100, request.limit ?? 5))
        let query = request.query.trimmingCharacters(in: .whitespacesAndNewlines)
        let searchQuery = query.isEmpty ? "memory" : query
        let results = try await storage.searchRAG(
            query: searchQuery,
            topK: max(limit * 4, limit),
            includePointerPayloads: false
        )

        let items = results.items.compactMap { item -> ColonyMemoryItem? in
            guard item.metadata[MetadataKey.entry] == "true" else {
                return nil
            }

            var metadata = item.metadata
            metadata[MetadataKey.provenanceBackendID] = "wax"
            metadata[MetadataKey.provenanceRecordID] = String(item.frameId)
            metadata[MetadataKey.provenanceKind] = item.metadata["membrane.kind"] ?? "colony.memory"

            return ColonyMemoryItem(
                id: metadata[MetadataKey.logicalID] ?? String(item.frameId),
                content: item.text,
                tags: Self.tags(from: metadata),
                metadata: metadata,
                score: Double(item.score)
            )
        }

        return ColonyMemoryRecallResult(items: Array(items.prefix(limit)))
    }

    public func remember(_ request: ColonyMemoryRememberRequest) async throws -> ColonyMemoryRememberResult {
        let logicalID = "wax-" + UUID().uuidString.lowercased()
        var metadata = request.metadata
        metadata[MetadataKey.entry] = "true"
        metadata[MetadataKey.logicalID] = logicalID

        for tag in request.tags {
            metadata["tag:\(tag)"] = tag
        }

        try await storage.memory.save(request.content, metadata: metadata)
        return ColonyMemoryRememberResult(id: logicalID)
    }

    private static func tags(from metadata: [String: String]) -> [String] {
        metadata
            .compactMap { key, value in key.hasPrefix("tag:") ? value : nil }
            .sorted()
    }
}
