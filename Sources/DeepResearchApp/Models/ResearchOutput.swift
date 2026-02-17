import Foundation

// MARK: - Research Insights

/// Structured output representing parsed research findings.
///
/// The type is intentionally plain `Codable`/`Sendable` so the app remains
/// portable across provider stacks and avoids macro/protocol collisions.
struct ResearchInsights: Sendable, Codable {
    var summary: String

    var keyTopics: [String]

    var statistics: [ResearchStat]

    var confidenceLevel: String
}

struct ResearchStat: Sendable, Codable {
    var label: String

    var value: Double

    var unit: String
}
