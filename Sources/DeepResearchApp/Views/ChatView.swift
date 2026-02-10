import SwiftUI

#if canImport(FoundationModels)
import FoundationModels
#endif

struct ChatView: View {
    let conversationID: UUID

    @Environment(SettingsViewModel.self) var settingsVM
    @State private var chatVM = ChatViewModel()
    @State private var inputText: String = ""

    var body: some View {
        VStack(spacing: 0) {
            chatHeader

            messageList

            if let error = chatVM.error, !error.isEmpty {
                errorBanner(error)
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
            }

            insightsSection

            if chatVM.isProcessing {
                ResearchProgressView(
                    phase: chatVM.currentPhase,
                    isProcessing: chatVM.isProcessing
                )
                .padding(.horizontal, 20)
                .padding(.bottom, 4)
            }

            MessageInputView(
                text: $inputText,
                isDisabled: chatVM.isInputDisabled,
                onSend: sendMessage
            )
        }
        .background(Color.dsBackground)
        .onAppear {
            chatVM.configure(with: settingsVM, conversationID: conversationID)
            if settingsVM.settings.selectedBackend == .ollama {
                Task {
                    await settingsVM.checkConnection()
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in
            chatVM.handleSettingsUpdate(settingsVM.settings)
        }
        .sheet(isPresented: Binding(
            get: { chatVM.pendingApproval != nil },
            set: { if !$0 { chatVM.pendingApproval = nil } }
        )) {
            if let approval = chatVM.pendingApproval {
                ToolApprovalSheet(
                    toolNames: approval.toolNames,
                    onApprove: { chatVM.approveTools() },
                    onReject: { chatVM.rejectTools() }
                )
            }
        }
    }

    private var chatHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Research Session")
                    .font(.dsHeadline)
                    .foregroundStyle(.dsNavy)

                Text(chatVM.currentPhase.rawValue)
                    .font(.dsCaption)
                    .foregroundStyle(.dsSlate)

                Text("Active: \(chatVM.activeProviderModelSummary)")
                    .font(.dsCaption2)
                    .foregroundStyle(.dsLightSlate)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            if settingsVM.settings.selectedBackend == .ollama {
                DSStatusBadge(
                    text: "Ollama \(settingsVM.ollamaConnectionStatus.rawValue)",
                    color: ollamaStatusColor(settingsVM.ollamaConnectionStatus)
                )
            }

            if chatVM.isProcessing {
                DSStatusBadge(text: "Researching", color: .dsIndigo)
            } else if !chatVM.messages.isEmpty {
                DSStatusBadge(text: "Ready", color: .dsEmerald)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(Color.dsCardBackground)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.dsBorder)
                .frame(height: 1)
        }
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 20) {
                    ForEach(chatVM.messages) { message in
                        ChatMessageView(message: message)
                            .id(message.id)
                    }

                    // Invisible anchor at the very bottom
                    Color.clear
                        .frame(height: 1)
                        .id("bottom-anchor")
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 24)
            }
            .scrollIndicators(.hidden)
            .onChange(of: chatVM.messages.count) {
                scrollToBottom(proxy)
            }
            .onChange(of: chatVM.messages.last?.content) {
                scrollToBottom(proxy)
            }
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        withAnimation(DSAnimation.quick) {
            proxy.scrollTo("bottom-anchor", anchor: .bottom)
        }
    }

    // MARK: - Insights Section

    @ViewBuilder
    private var insightsSection: some View {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, iOS 26.0, visionOS 26.0, *) {
            insightsContent
        }
        #endif
    }

    #if canImport(FoundationModels)
    @available(macOS 26.0, iOS 26.0, visionOS 26.0, *)
    @ViewBuilder
    private var insightsContent: some View {
        if chatVM.isExtractingInsights {
            HStack(spacing: 10) {
                ProgressView()
                    .controlSize(.small)
                    .tint(.dsIndigo)
                Text("Extracting insights...")
                    .font(.dsCallout)
                    .foregroundStyle(.dsSlate)
                    .dsTextShimmer(isActive: true)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .dsGlassCard()
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        } else if let insights = chatVM.insights {
            ResearchChartsView(insights: insights)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
    #endif

    // MARK: - Actions

    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        inputText = ""
        Task {
            await chatVM.send(text)
        }
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.dsCaption)
                .foregroundStyle(.dsNavy)

            Text(message)
                .font(.dsCaption)
                .foregroundStyle(.dsNavy)
                .textSelection(.enabled)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.dsError.opacity(0.75))
        .clipShape(.rect(cornerRadius: 10))
    }

    private func ollamaStatusColor(_ status: SettingsViewModel.ConnectionStatus) -> Color {
        switch status {
        case .connected:
            return .dsEmerald
        case .disconnected:
            return .dsError
        case .unknown:
            return .dsSlate
        }
    }
}
