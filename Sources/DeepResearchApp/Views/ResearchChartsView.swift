import SwiftUI
import Charts

#if canImport(FoundationModels)
import FoundationModels
#endif

// MARK: - ResearchChartsView

/// Displays structured ``ResearchInsights`` as a rich card-based layout
/// featuring a summary banner, bar chart of statistics, topic pills, and a
/// confidence gauge -- styled with the Stripe-inspired design system.
#if canImport(FoundationModels)
@available(macOS 26.0, iOS 26.0, visionOS 26.0, *)
struct ResearchChartsView: View {
    let insights: ResearchInsights

    private let chartColors: [Color] = [
        .dsIndigo, .dsVibrantPurple, .dsTeal, .dsEmerald, .dsAmber,
        .dsIndigo.opacity(0.7), .dsTeal.opacity(0.7), .dsEmerald.opacity(0.7),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            summaryBanner
            if !insights.statistics.isEmpty {
                statisticsChart
            }
            if !insights.keyTopics.isEmpty {
                topicTags
            }
            confidenceIndicator
        }
        .dsCard(padding: 20)
    }

    // MARK: - Summary Banner

    private var summaryBanner: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "lightbulb.fill")
                    .font(.subheadline.bold())
                    .foregroundStyle(.dsAmber)

                Text("Insights")
                    .font(.title3.bold())
                    .foregroundStyle(.dsNavy)
            }

            Text(insights.summary)
                .font(.subheadline)
                .foregroundStyle(.dsSlate)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.dsAmber.opacity(0.06))
        .clipShape(.rect(cornerRadius: 12))
    }

    // MARK: - Statistics Chart

    private var statisticsChart: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Key Statistics")
                .font(.subheadline.bold())
                .foregroundStyle(.dsNavy)

            Chart {
                ForEach(Array(insights.statistics.enumerated()), id: \.offset) { index, stat in
                    BarMark(
                        x: .value("Value", stat.value),
                        y: .value("Metric", stat.label)
                    )
                    .foregroundStyle(chartColors[index % chartColors.count])
                    .cornerRadius(4)
                    .accessibilityLabel("\(stat.label): \(formattedValue(stat.value, unit: stat.unit))")
                    .annotation(position: .trailing, alignment: .leading, spacing: 4) {
                        Text(formattedValue(stat.value, unit: stat.unit))
                            .font(.caption2.bold())
                            .foregroundStyle(.dsSlate)
                    }
                }
            }
            .chartYAxis {
                AxisMarks { _ in
                    AxisValueLabel()
                        .font(.caption)
                        .foregroundStyle(Color.dsSlate)
                }
            }
            .chartXAxis(.hidden)
            .frame(height: CGFloat(insights.statistics.count) * 40 + 20)
        }
    }

    // MARK: - Topic Tags

    private var topicTags: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Key Topics")
                .font(.subheadline.bold())
                .foregroundStyle(.dsNavy)

            FlowLayout(spacing: 8) {
                ForEach(Array(insights.keyTopics.enumerated()), id: \.offset) { index, topic in
                    Text(topic)
                        .font(.caption.bold())
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(chartColors[index % chartColors.count].opacity(0.1))
                        .foregroundStyle(chartColors[index % chartColors.count])
                        .clipShape(.capsule)
                        .overlay {
                            Capsule()
                                .stroke(chartColors[index % chartColors.count].opacity(0.2), lineWidth: 1)
                        }
                }
            }
        }
    }

    // MARK: - Confidence Indicator

    private var confidenceIndicator: some View {
        HStack(spacing: 8) {
            Text("Confidence")
                .font(.subheadline.bold())
                .foregroundStyle(.dsNavy)

            Spacer()

            HStack(spacing: 6) {
                Image(systemName: confidenceIcon)
                    .font(.caption.bold())
                    .foregroundStyle(confidenceColor)

                Text(insights.confidenceLevel.capitalized)
                    .font(.caption.bold())
                    .foregroundStyle(confidenceColor)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(confidenceColor.opacity(0.1))
            .clipShape(.capsule)
        }
    }

    // MARK: - Helpers

    private func formattedValue(_ value: Double, unit: String) -> String {
        let formatted = value.formatted(.number.precision(.fractionLength(0...2)))
        return "\(formatted) \(unit)"
    }

    private var confidenceColor: Color {
        switch insights.confidenceLevel.lowercased() {
        case "high": .dsEmerald
        case "medium": .dsAmber
        default: .dsError
        }
    }

    private var confidenceIcon: String {
        switch insights.confidenceLevel.lowercased() {
        case "high": "checkmark.seal.fill"
        case "medium": "exclamationmark.triangle.fill"
        default: "questionmark.circle.fill"
        }
    }
}
#endif
