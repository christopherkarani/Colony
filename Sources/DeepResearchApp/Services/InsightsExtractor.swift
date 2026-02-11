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
        Analyze this research report and extract structured insights. \
        Identify the key topics, any statistics or numeric data mentioned, \
        and assess the overall confidence level (low, medium, or high) \
        based on source quality and consistency of findings.

        Report:
        \(markdownReport)
        """
        let response = try await session.respond(to: prompt, generating: ResearchInsights.self)
        return response.content
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
}
