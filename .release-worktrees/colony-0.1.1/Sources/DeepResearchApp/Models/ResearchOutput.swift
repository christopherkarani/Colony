import Foundation

// MARK: - Research Insights

/// Structured output representing parsed research findings.
///
/// When running on devices that support Foundation Models, the `@Generable`
/// macro enables the on-device model to produce this type directly as
/// structured output. On other platforms the types remain plain `Codable`
/// structs so the rest of the app can reference them without conditional
/// compilation at every call site.

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
