import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

// MARK: - Research Insights

/// Structured output representing parsed research findings.
///
/// When running on devices that support Foundation Models, the `@Generable`
/// macro enables the on-device model to produce this type directly as
/// structured output. On other platforms the types remain plain `Codable`
/// structs so the rest of the app can reference them without conditional
/// compilation at every call site.

#if canImport(FoundationModels)

@available(macOS 26.0, iOS 26.0, visionOS 26.0, *)
@Generable
struct ResearchInsights: Sendable, Codable {
    @Guide(description: "A concise 1-2 sentence summary of findings")
    var summary: String

    @Guide(description: "Key topics discovered, max 8")
    var keyTopics: [String]

    @Guide(description: "Statistical findings from the research")
    var statistics: [ResearchStat]

    @Guide(description: "Confidence level in the findings: low, medium, or high")
    var confidenceLevel: String
}

@available(macOS 26.0, iOS 26.0, visionOS 26.0, *)
@Generable
struct ResearchStat: Sendable, Codable {
    @Guide(description: "Label for this statistic")
    var label: String

    @Guide(description: "Numeric value")
    var value: Double

    @Guide(description: "Unit of measurement")
    var unit: String
}

#else

// MARK: - Fallback (non-Apple platforms)

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

#endif
