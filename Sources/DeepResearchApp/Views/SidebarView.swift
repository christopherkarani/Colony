import SwiftUI

struct SidebarView: View {
    @Environment(SidebarViewModel.self) var sidebarVM
    let onOpenSettings: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            sidebarHeader

            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(sortedConversations) { conversation in
                        SidebarRow(
                            conversation: conversation,
                            isSelected: sidebarVM.selectedConversationID == conversation.id,
                            onSelect: {
                                withAnimation(DSAnimation.quick) {
                                    sidebarVM.selectedConversationID = conversation.id
                                }
                            },
                            onDelete: {
                                sidebarVM.deleteConversation(conversation)
                            }
                        )
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .scrollIndicators(.hidden)
        }
        .background(Color.dsBackground)
        .onAppear {
            sidebarVM.loadConversations()
        }
    }

    private var sidebarHeader: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Deep Research")
                    .font(.dsTitle3)
                    .foregroundStyle(.dsNavy)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineLimit(2)
                    .minimumScaleFactor(0.9)

                Text("AI-Powered Insights")
                    .font(.dsCaption)
                    .foregroundStyle(.dsSlate)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button("New", systemImage: "plus") {
                sidebarVM.createNewConversation()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .font(.dsCaption)
            .foregroundStyle(.dsIndigo)

            Button("Settings", systemImage: "gearshape") {
                onOpenSettings()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .font(.dsCaption)
            .foregroundStyle(.dsSlate)
        }
        .padding(18)
        .background(Color.dsBackground)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.dsBorder)
                .frame(height: 1)
        }
    }

    private var sortedConversations: [Conversation] {
        sidebarVM.conversations.sorted { $0.createdAt > $1.createdAt }
    }
}

// MARK: - Sidebar Row

struct SidebarRow: View {
    let conversation: Conversation
    let isSelected: Bool
    let onSelect: () -> Void
    let onDelete: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                Circle()
                    .fill(isSelected ? Color.dsIndigo : Color.dsLightSlate.opacity(0.3))
                    .frame(width: 8, height: 8)

                VStack(alignment: .leading, spacing: 4) {
                    Text(conversation.title)
                        .font(.dsSubheadline)
                        .foregroundStyle(isSelected ? .dsIndigo : .dsNavy)
                        .lineLimit(3)
                        .truncationMode(.tail)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(conversation.createdAt, format: .relative(presentation: .named))
                        .font(.dsCaption)
                        .foregroundStyle(.dsSlate)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Spacer()

                if isHovered {
                    Button("Delete", systemImage: "trash", role: .destructive) {
                        onDelete()
                    }
                    .labelStyle(.iconOnly)
                    .font(.dsCaption)
                    .foregroundStyle(.dsSlate)
                    .buttonStyle(.plain)
                    .transition(.opacity)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? Color.dsIndigo.opacity(0.08) : (isHovered ? Color.dsSurface : .clear))
            )
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.dsIndigo.opacity(0.2), lineWidth: 1.5)
                }
            }
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(DSAnimation.quick) {
                isHovered = hovering
            }
        }
    }
}

// MARK: - Compact Secondary Button Style

struct DSSecondaryCompactButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.dsCaption)
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.white.opacity(0.2))
            .clipShape(.rect(cornerRadius: 8))
            .opacity(configuration.isPressed ? 0.7 : 1.0)
    }
}

extension ButtonStyle where Self == DSSecondaryCompactButtonStyle {
    static var dsSecondaryCompact: DSSecondaryCompactButtonStyle { DSSecondaryCompactButtonStyle() }
}
