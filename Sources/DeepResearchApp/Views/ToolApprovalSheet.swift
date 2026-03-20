import SwiftUI

/// Minimal inline tool approval card that integrates naturally into the chat flow
struct ToolApprovalSheet: View {
    let toolNames: [String]
    let onApprove: () -> Void
    let onReject: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header with icon and title
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.dsCallout)
                    .foregroundStyle(.dsAmber)

                Text("Approval Required")
                    .font(.dsSubheadline)
                    .foregroundStyle(.dsNavy)

                Spacer()
            }

            // Tool list - compact inline presentation
            FlowLayout(spacing: 6) {
                ForEach(toolNames, id: \.self) { name in
                    HStack(spacing: 4) {
                        Image(systemName: "wrench.fill")
                            .font(.dsCaption2)
                            .foregroundStyle(.dsIndigo)

                        Text(name)
                            .font(.dsCaption)
                            .foregroundStyle(.dsNavy)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.dsIndigo.opacity(0.08))
                    .clipShape(.capsule)
                }
            }

            // Action buttons - compact horizontal layout
            HStack(spacing: 10) {
                Button("Reject", action: onReject)
                    .buttonStyle(.dsSecondary)
                    .controlSize(.small)

                Button("Approve", action: onApprove)
                    .buttonStyle(.dsPrimary)
                    .controlSize(.small)

                Spacer()
            }
        }
        .padding(16)
        .background(Color.dsAmber.opacity(0.05))
        .clipShape(.rect(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.dsAmber.opacity(0.3), lineWidth: 1.5)
        }
        .modifier(ApplyShadows(shadows: DSShadow.level1))
    }
}

// FlowLayout is defined in ChatMessageView.swift but needs to be available here
// If not already global, it should be moved to DesignSystem.swift
