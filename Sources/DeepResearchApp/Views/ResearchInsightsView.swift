import SwiftUI
import Charts

struct ResearchInsightsView: View {
    let messages: [ChatMessage]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            DSSectionHeader("Research Insights", icon: "chart.bar")

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                InsightStatCard(
                    title: "Sources Found",
                    value: "\(sourcesCount)",
                    icon: "link",
                    color: .dsIndigo
                )

                InsightStatCard(
                    title: "Searches Executed",
                    value: "\(searchCount)",
                    icon: "magnifyingglass",
                    color: .dsTeal
                )

                InsightStatCard(
                    title: "Messages",
                    value: "\(messages.count)",
                    icon: "bubble.left.and.bubble.right",
                    color: .dsAmber
                )

                InsightStatCard(
                    title: "Tools Used",
                    value: "\(totalToolCalls)",
                    icon: "wrench.and.screwdriver",
                    color: .dsEmerald
                )
            }

            if !searchesPerMessage.isEmpty {
                SearchActivityChart(data: searchesPerMessage)
            }

            if !topicTags.isEmpty {
                TopicTagCloud(topics: topicTags)
            }
        }
        .dsCard(padding: 20)
    }

    private var sourcesCount: Int {
        messages.flatMap(\.toolCalls)
            .filter { $0.name == "tavily_extract" && $0.status == .completed }
            .count
    }

    private var searchCount: Int {
        messages.flatMap(\.toolCalls)
            .filter { $0.name == "tavily_search" && $0.status == .completed }
            .count
    }

    private var totalToolCalls: Int {
        messages.flatMap(\.toolCalls).count
    }

    private var searchesPerMessage: [SearchActivityEntry] {
        var entries: [SearchActivityEntry] = []
        var messageIndex = 0
        for message in messages where message.role == .assistant {
            messageIndex += 1
            let count = message.toolCalls.filter { $0.name == "tavily_search" }.count
            if count > 0 {
                entries.append(SearchActivityEntry(step: messageIndex, count: count))
            }
        }
        return entries
    }

    private var topicTags: [String] {
        var topics: [String] = []
        let toolNames = Set(messages.flatMap(\.toolCalls).map(\.name))
        if toolNames.contains("tavily_search") {
            topics.append("Web Search")
        }
        if toolNames.contains("tavily_extract") {
            topics.append("Content Extraction")
        }
        if toolNames.contains("write_todos") || toolNames.contains("read_todos") {
            topics.append("Task Planning")
        }
        if toolNames.contains("scratch_add") || toolNames.contains("scratch_read") {
            topics.append("Note Taking")
        }

        let assistantMessages = messages.filter { $0.role == .assistant && !$0.content.isEmpty }
        if assistantMessages.count > 2 {
            topics.append("Multi-step Analysis")
        }
        if searchCount >= 3 {
            topics.append("Deep Dive")
        }
        return topics
    }
}

// MARK: - Stat Card

struct InsightStatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .font(.caption.bold())
                    .foregroundStyle(color)

                Spacer()

                Text(value)
                    .font(.title2.bold())
                    .foregroundStyle(.dsNavy)
            }

            Text(title)
                .font(.caption)
                .foregroundStyle(.dsSlate)
        }
        .padding(12)
        .background(color.opacity(0.06))
        .clipShape(.rect(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(color.opacity(0.12), lineWidth: 1)
        }
    }
}

// MARK: - Search Activity Chart

struct SearchActivityEntry: Identifiable {
    let id = UUID()
    let step: Int
    let count: Int
}

struct SearchActivityChart: View {
    let data: [SearchActivityEntry]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Search Activity")
                .font(.subheadline.bold())
                .foregroundStyle(.dsNavy)

            Chart(data) { entry in
                BarMark(
                    x: .value("Step", "Step \(entry.step)"),
                    y: .value("Searches", entry.count)
                )
                .foregroundStyle(Color.dsIndigo)
                .cornerRadius(4)
                .accessibilityLabel("Step \(entry.step): \(entry.count) searches")
            }
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisValueLabel()
                        .foregroundStyle(Color.dsSlate)
                }
            }
            .chartXAxis {
                AxisMarks { value in
                    AxisValueLabel()
                        .foregroundStyle(Color.dsSlate)
                }
            }
            .frame(height: max(80, CGFloat(data.count) * 32 + 40))
        }
    }
}

// MARK: - Topic Tag Cloud

struct TopicTagCloud: View {
    let topics: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Topics Identified")
                .font(.subheadline.bold())
                .foregroundStyle(.dsNavy)

            FlowLayout(spacing: 8) {
                ForEach(topics, id: \.self) { topic in
                    TopicTag(text: topic, color: tagColor(for: topic))
                }
            }
        }
    }

    private func tagColor(for topic: String) -> Color {
        let colors: [Color] = [.dsIndigo, .dsTeal, .dsAmber, .dsEmerald, .dsVibrantPurple]
        let index = abs(topic.hashValue) % colors.count
        return colors[index]
    }
}

struct TopicTag: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.caption.bold())
            .foregroundStyle(color)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(color.opacity(0.1))
            .clipShape(.capsule)
            .overlay {
                Capsule()
                    .stroke(color.opacity(0.2), lineWidth: 1)
            }
    }
}
