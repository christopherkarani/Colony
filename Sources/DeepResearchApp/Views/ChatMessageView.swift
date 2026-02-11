import SwiftUI

struct ChatMessageView: View {
    let message: ChatMessage

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            if message.role == .user {
                Spacer(minLength: 80)
            }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 10) {
                MessageRoleLabel(role: message.role)

                if message.role == .assistant && message.isStreaming {
                    ThinkingCard(message: message)
                } else {
                    MessageBubble(message: message)
                    if !message.toolCalls.isEmpty {
                        CompletedToolSummary(toolCalls: message.toolCalls)
                    }
                }
            }

            if message.role != .user {
                Spacer(minLength: 80)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Role Label

struct MessageRoleLabel: View {
    let role: ChatMessage.ChatMessageRole

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: role == .user ? "person.fill" : "sparkles")
                .font(.dsCaption2)
                .foregroundStyle(role == .user ? .dsVibrantPurple : .dsTeal)

            Text(role == .user ? "You" : "Research Assistant")
                .font(.dsCaption)
                .foregroundStyle(.dsSlate)
        }
    }
}

// MARK: - Thinking Card (shown during streaming)

/// Compact card shown while the assistant is working. Displays an animated
/// indicator, the latest tool activity, and running/completed tool badges.
struct ThinkingCard: View {
    let message: ChatMessage

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Status line
            HStack(spacing: 10) {
                ProgressView()
                    .controlSize(.small)
                    .tint(.dsIndigo)

                Text(statusText)
                    .font(.dsSubheadline)
                    .foregroundStyle(.dsNavy)
                    .dsTextShimmer(isActive: true)

                Spacer()
            }

            // Tool call badges - minimal inline presentation
            if !message.toolCalls.isEmpty {
                ToolCallBadgeGroup(toolCalls: message.toolCalls)
            }
        }
        .padding(16)
        .background(Color.dsCardBackground)
        .clipShape(.rect(cornerRadius: 12))
        .modifier(ApplyShadows(shadows: DSShadow.level1))
    }

    private var statusText: String {
        if let lastRunning = message.toolCalls.last(where: { $0.status == .running }) {
            return "Running \(lastRunning.name)..."
        }
        if message.toolCalls.allSatisfy({ $0.status == .completed || $0.status == .failed }) &&
           !message.toolCalls.isEmpty {
            return "Synthesizing..."
        }
        return "Thinking..."
    }
}

// MARK: - Message Bubble

struct MessageBubble: View {
    let message: ChatMessage

    var body: some View {
        Group {
            if message.role == .user {
                Text(message.content)
                    .font(.dsBody)
                    .foregroundStyle(.white)
            } else if message.content.isEmpty {
                Text("No response generated.")
                    .font(.dsBody)
                    .foregroundStyle(.dsLightSlate)
                    .italic()
            } else {
                HStack(alignment: .bottom, spacing: 4) {
                    Text(markdownContent)
                        .font(.dsBody)
                        .foregroundStyle(.dsNavy)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)

                    if message.isStreaming {
                        StreamingCursor()
                    }
                }
            }
        }
        .padding(16)
        .background(bubbleBackground)
        .clipShape(.rect(cornerRadius: 16))
        .modifier(ApplyShadows(shadows: DSShadow.level1))
    }

    private var markdownContent: AttributedString {
        let cleaned = Self.sanitizeContent(message.content)
        do {
            return try AttributedString(markdown: cleaned)
        } catch {
            // Fallback to plain text if markdown parsing fails
            return AttributedString(cleaned)
        }
    }

    /// Safety net: strips any residual tool artifacts from the final content.
    private static func sanitizeContent(_ raw: String) -> String {
        var text = raw

        // Remove fenced code blocks that look like raw tool JSON
        let fencedPattern = /```+\s*json?\s*\n[\s\S]*?```+/
        while let match = text.firstMatch(of: fencedPattern) {
            text.replaceSubrange(match.range, with: "")
        }

        // Remove <tool...> tags
        let toolTagPattern = /<tool[\s\S]*?>/
        while let match = text.firstMatch(of: toolTagPattern) {
            text.replaceSubrange(match.range, with: "")
        }

        // Remove tool invocation noise lines
        let lines = text.components(separatedBy: "\n")
        let filtered = lines.filter { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed == "json" || trimmed == "```json" || trimmed == "```" { return false }
            if trimmed.hasPrefix("Tool(") || trimmed.hasPrefix("Tool call ") { return false }
            if trimmed.contains("was cancelled") && trimmed.contains("tool call") { return false }
            if trimmed.hasPrefix("[id: ") || trimmed.hasPrefix("fm:") { return false }
            if trimmed.lowercased().hasPrefix("<tool") { return false }
            return true
        }
        text = filtered.joined(separator: "\n")

        // Drop any trailing incomplete tool markup fragment.
        if let tagStart = text.range(of: "<tool", options: [.backwards, .caseInsensitive]) {
            let suffix = text[tagStart.lowerBound...]
            if !suffix.contains(">") {
                text = String(text[..<tagStart.lowerBound])
            }
        }

        // Drop tail from an unmatched fenced block (common when a run fails mid-stream).
        let fenceMarker = "```"
        let fenceCount = text.components(separatedBy: fenceMarker).count - 1
        if fenceCount % 2 == 1, let unmatchedStart = text.range(of: fenceMarker, options: .backwards) {
            text = String(text[..<unmatchedStart.lowerBound])
        }

        // Collapse excessive blank lines
        while text.contains("\n\n\n") {
            text = text.replacingOccurrences(of: "\n\n\n", with: "\n\n")
        }

        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    @ViewBuilder
    private var bubbleBackground: some View {
        if message.role == .user {
            Color.dsIndigo
        } else {
            Color.dsCardBackground
        }
    }
}

// MARK: - Completed Tool Summary (shown after streaming finishes)

/// Minimal inline summary of tools used, shown below the final answer.
struct CompletedToolSummary: View {
    let toolCalls: [ChatMessage.ToolCallInfo]

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark.circle.fill")
                .font(.dsCaption2)
                .foregroundStyle(.dsEmerald)

            Text(summaryText)
                .font(.dsCaption2)
                .foregroundStyle(.dsSlate)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.dsSurface)
        .clipShape(.capsule)
    }

    private var summaryText: String {
        let completed = toolCalls.filter { $0.status == .completed }.count
        let uniqueNames = Set(toolCalls.map(\.name))
        if uniqueNames.count == 1 {
            return "\(uniqueNames.first!) completed"
        }
        return "\(completed) tools completed"
    }
}

// MARK: - Tool Call Badges

struct ToolCallBadgeGroup: View {
    let toolCalls: [ChatMessage.ToolCallInfo]

    var body: some View {
        FlowLayout(spacing: 8) {
            ForEach(toolCalls) { toolCall in
                ToolCallBadge(toolCall: toolCall)
            }
        }
    }
}

struct ToolCallBadge: View {
    let toolCall: ChatMessage.ToolCallInfo

    var body: some View {
        HStack(spacing: 5) {
            statusIcon
            Text(toolCall.name)
                .font(.dsCaption2)
                .foregroundStyle(.dsNavy)
                .dsTextShimmer(isActive: toolCall.status == .running)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(statusBackground)
        .clipShape(.capsule)
        .dsPulse(isActive: toolCall.status == .pending)
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch toolCall.status {
        case .pending:
            Image(systemName: "clock")
                .font(.dsCaption2)
                .foregroundStyle(.dsSlate)
        case .running:
            ProgressView()
                .controlSize(.mini)
                .tint(.dsIndigo)
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .font(.dsCaption2)
                .foregroundStyle(.dsEmerald)
        case .failed:
            Image(systemName: "xmark.circle.fill")
                .font(.dsCaption2)
                .foregroundStyle(.dsError)
        }
    }

    private var statusBackground: Color {
        switch toolCall.status {
        case .pending: .dsSurface
        case .running: .dsIndigo.opacity(0.08)
        case .completed: .dsEmerald.opacity(0.08)
        case .failed: .dsError.opacity(0.08)
        }
    }
}

// MARK: - Flow Layout

struct FlowLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrange(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                proposal: .unspecified
            )
        }
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0
        var totalSize: CGSize = .zero

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)

            if currentX + size.width > maxWidth, currentX > 0 {
                currentX = 0
                currentY += lineHeight + spacing
                lineHeight = 0
            }

            positions.append(CGPoint(x: currentX, y: currentY))
            lineHeight = max(lineHeight, size.height)
            currentX += size.width + spacing
            totalSize.width = max(totalSize.width, currentX - spacing)
        }

        totalSize.height = currentY + lineHeight
        return (totalSize, positions)
    }
}
