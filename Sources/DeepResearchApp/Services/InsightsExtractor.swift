import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

// MARK: - InsightsExtractor

/// Extracts structured ``ResearchInsights`` from a markdown research report
/// using the on-device Foundation Models `@Generable` pipeline.
///
/// The extraction is designed to be called *after* the agent has finished
/// producing its final answer so the markdown text renders immediately while
/// insights populate asynchronously.
struct InsightsExtractor: Sendable {

    // MARK: - Errors

    enum ExtractionError: Error, Sendable {
        case unavailable
    }

    // MARK: - Public Methods

    /// Analyze a completed markdown research report and return structured insights.
    ///
    /// - Parameter markdownReport: The full markdown text produced by the research agent.
    /// - Returns: A ``ResearchInsights`` value containing summary, topics, statistics and confidence.
    /// - Throws: ``ExtractionError/unavailable`` when Foundation Models are not present.
    #if canImport(FoundationModels)
    @available(macOS 26.0, iOS 26.0, visionOS 26.0, *)
    func extract(from markdownReport: String) async throws -> ResearchInsights {
        let session = LanguageModelSession()
        let prompt = """
        Analyze this research report and return only valid JSON matching this schema:
        {
          "summary": "1-2 sentence summary",
          "keyTopics": ["topic 1", "topic 2"],
          "statistics": [
            { "label": "stat label", "value": 0, "unit": "unit" }
          ],
          "confidenceLevel": "low|medium|high"
        }

        Rules:
        - Return JSON only. Do not wrap it in Markdown.
        - Use an empty array when no statistics are present.
        - Keep `keyTopics` to at most 8 items.
        - `confidenceLevel` must be one of: low, medium, high.

        Report:
        \(markdownReport)
        """
        let response = try await session.respond(to: prompt)
        let payload = try extractJSONObject(from: response.content)
        return try JSONDecoder().decode(ResearchInsights.self, from: Data(payload.utf8))
    }
    #endif

    /// Returns `true` when the on-device Foundation Models runtime is available.
    static var isAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, iOS 26.0, visionOS 26.0, *) {
            return SystemLanguageModel.default.availability == .available
        }
        return false
        #else
        return false
        #endif
    }

    #if canImport(FoundationModels)
    @available(macOS 26.0, iOS 26.0, visionOS 26.0, *)
    private func extractJSONObject(from content: String) throws -> String {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.first == "{", trimmed.last == "}" {
            return trimmed
        }

        if let fencedRange = trimmed.range(of: #"```json\s*(\{[\s\S]*\})\s*```"#, options: .regularExpression) {
            let fenced = String(trimmed[fencedRange])
            return fenced
                .replacingOccurrences(of: #"^```json\s*"#, with: "", options: .regularExpression)
                .replacingOccurrences(of: #"\s*```$"#, with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        guard let start = trimmed.firstIndex(of: "{"),
              let end = trimmed.lastIndex(of: "}")
        else {
            throw ExtractionError.unavailable
        }
        return String(trimmed[start...end])
    }
    #endif
}
