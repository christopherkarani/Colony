import Foundation

// MARK: - InsightsExtractor

/// Extracts structured ``ResearchInsights`` from a markdown research report
/// using deterministic local parsing.
///
/// The extraction is designed to be called *after* the agent has finished
/// producing its final answer so the markdown text renders immediately while
/// insights populate asynchronously.
struct InsightsExtractor: Sendable {

    // MARK: - Errors

    func extract(from markdownReport: String) async throws -> ResearchInsights {
        let normalized = markdownReport.trimmingCharacters(in: .whitespacesAndNewlines)
        let summary = summarize(markdown: normalized)
        let keyTopics = extractTopics(markdown: normalized)
        let statistics = extractStatistics(markdown: normalized)
        let confidenceLevel = estimateConfidence(markdown: normalized)
        return ResearchInsights(
            summary: summary,
            keyTopics: keyTopics,
            statistics: statistics,
            confidenceLevel: confidenceLevel
        )
    }

    /// Always available because extraction is local/deterministic.
    static var isAvailable: Bool {
        true
    }

    private func summarize(markdown: String) -> String {
        let lines = markdown
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.isEmpty == false && $0.hasPrefix("#") == false }
        if let first = lines.first {
            return String(first.prefix(220))
        }
        return "No summary available."
    }

    private func extractTopics(markdown: String) -> [String] {
        var topics: [String] = []
        let lines = markdown.split(separator: "\n")
        for raw in lines {
            let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.hasPrefix("## ") || line.hasPrefix("### ") {
                let cleaned = line
                    .replacingOccurrences(of: "#", with: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if cleaned.isEmpty == false {
                    topics.append(cleaned)
                }
            }
            if topics.count >= 8 { break }
        }
        return Array(Set(topics)).sorted().prefix(8).map { $0 }
    }

    private func extractStatistics(markdown: String) -> [ResearchStat] {
        let pattern = #"([A-Za-z][A-Za-z0-9\s/_-]{2,30})[:\s]+([0-9]+(?:\.[0-9]+)?)\s*(%|ms|s|x|k|m|b|tokens|items|docs|users|requests)?"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return []
        }

        let range = NSRange(markdown.startIndex..<markdown.endIndex, in: markdown)
        let matches = regex.matches(in: markdown, options: [], range: range)

        var stats: [ResearchStat] = []
        stats.reserveCapacity(min(8, matches.count))

        for match in matches.prefix(8) {
            guard
                let labelRange = Range(match.range(at: 1), in: markdown),
                let valueRange = Range(match.range(at: 2), in: markdown)
            else { continue }

            let label = String(markdown[labelRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            let rawValue = String(markdown[valueRange])
            guard let value = Double(rawValue) else { continue }

            let unit: String
            if let unitRange = Range(match.range(at: 3), in: markdown) {
                unit = String(markdown[unitRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            } else {
                unit = "count"
            }

            stats.append(ResearchStat(label: label, value: value, unit: unit))
        }

        return stats
    }

    private func estimateConfidence(markdown: String) -> String {
        let lower = markdown.lowercased()
        let citations = lower.components(separatedBy: "](").count - 1
        let hasLimitations = lower.contains("limitations") || lower.contains("gaps")
        let hasNumbers = lower.range(of: #"\d"#, options: .regularExpression) != nil

        if citations >= 4 && hasNumbers && hasLimitations {
            return "high"
        }
        if citations >= 2 || hasNumbers {
            return "medium"
        }
        return "low"
    }
}
