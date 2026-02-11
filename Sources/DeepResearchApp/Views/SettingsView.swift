import SwiftUI

struct SettingsView: View {
    @Environment(SettingsViewModel.self) var settingsVM

    var body: some View {
        @Bindable var settings = settingsVM.settings

        ScrollView {
            VStack(spacing: 20) {
                SettingsHeaderSection()

                BackendSettingsCard(selectedBackend: $settings.selectedBackend)

                if settingsVM.settings.selectedBackend == .ollama {
                    OllamaSettingsCard(
                        baseURL: $settings.ollamaBaseURL,
                        selectedModel: $settings.selectedOllamaModel,
                        availableModels: settingsVM.availableOllamaModels,
                        isLoadingModels: settingsVM.isLoadingModels,
                        connectionStatus: settingsVM.ollamaConnectionStatus,
                        onRefresh: {
                            Task {
                                await settingsVM.fetchOllamaModels()
                            }
                        }
                    )
                }

                TavilySettingsCard(apiKey: $settings.tavilyAPIKey)
            }
            .padding(24)
        }
        .scrollIndicators(.hidden)
        .background(Color.dsBackground)
        .frame(width: 500, height: 500)
        .onAppear {
            Task {
                await settingsVM.fetchOllamaModels()
            }
        }
        .onChange(of: settings.selectedBackend) {
            guard settings.selectedBackend == .ollama else { return }
            Task {
                await settingsVM.fetchOllamaModels()
            }
        }
        .onChange(of: settings.ollamaBaseURL) {
            guard settings.selectedBackend == .ollama else { return }
            settingsVM.scheduleOllamaModelRefresh()
        }
    }
}

// MARK: - Settings Header

struct SettingsHeaderSection: View {
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 6) {
                Text("Settings")
                    .font(.dsLargeTitle)
                    .foregroundStyle(.dsNavy)

                Text("Configure your research environment")
                    .font(.dsSubheadline)
                    .foregroundStyle(.dsSlate)
            }
            Spacer()
        }
    }
}

// MARK: - Backend Card

struct BackendSettingsCard: View {
    @Binding var selectedBackend: BackendType

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            DSSectionHeader("Model Backend", icon: "cpu")

            VStack(spacing: 12) {
                Picker("Backend", selection: $selectedBackend) {
                    ForEach(BackendType.allCases, id: \.self) { backend in
                        Text(backend.displayName).tag(backend)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            .dsCard()
        }
    }
}

// MARK: - Ollama Card

struct OllamaSettingsCard: View {
    @Binding var baseURL: String
    @Binding var selectedModel: String
    let availableModels: [OllamaModelInfo]
    let isLoadingModels: Bool
    let connectionStatus: SettingsViewModel.ConnectionStatus
    let onRefresh: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            DSSectionHeader("Ollama Configuration", icon: "server.rack")

            VStack(spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Base URL")
                        .font(.dsSubheadline)
                        .foregroundStyle(.dsNavy)

                    TextField("http://localhost:11434", text: $baseURL)
                        .textFieldStyle(.plain)
                        .font(.dsBody)
                        .padding(12)
                        .background(Color.dsSurface)
                        .clipShape(.rect(cornerRadius: 10))
                        .overlay {
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color.dsBorder, lineWidth: 1.5)
                        }
                        .submitLabel(.go)
                        .onSubmit(onRefresh)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Model")
                        .font(.dsSubheadline)
                        .foregroundStyle(.dsNavy)

                    Picker("Model", selection: $selectedModel) {
                        Text("Select a model").tag("")
                        ForEach(availableModels) { model in
                            Text(model.name).tag(model.name)
                        }
                    }
                    .font(.dsBody)
                    .labelsHidden()
                }

                HStack {
                    Button("Refresh Models", systemImage: "arrow.clockwise", action: onRefresh)
                        .buttonStyle(.dsSecondary)
                        .disabled(isLoadingModels)

                    Spacer()

                    OllamaConnectionBadge(status: connectionStatus)
                }
            }
            .dsCard()
        }
    }
}

// MARK: - Tavily Card

struct TavilySettingsCard: View {
    @Binding var apiKey: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            DSSectionHeader("Tavily Search", icon: "magnifyingglass")

            VStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("API Key")
                        .font(.dsSubheadline)
                        .foregroundStyle(.dsNavy)

                    SecureField("Enter your API key", text: $apiKey)
                        .textFieldStyle(.plain)
                        .font(.dsBody)
                        .padding(12)
                        .background(Color.dsSurface)
                        .clipShape(.rect(cornerRadius: 10))
                        .overlay {
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color.dsBorder, lineWidth: 1.5)
                        }
                }

                HStack(spacing: 8) {
                    Image(systemName: "info.circle")
                        .font(.dsCaption)
                        .foregroundStyle(.dsSlate)

                    Text("Get a free API key at tavily.com")
                        .font(.dsCaption)
                        .foregroundStyle(.dsSlate)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .dsCard()
        }
    }
}

// MARK: - Connection Badge

struct OllamaConnectionBadge: View {
    let status: SettingsViewModel.ConnectionStatus

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)

            Text(status.rawValue)
                .font(.dsCaption)
                .foregroundStyle(.dsSlate)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(statusColor.opacity(0.08))
        .clipShape(.capsule)
    }

    private var statusColor: Color {
        switch status {
        case .connected: .dsEmerald
        case .disconnected: .dsError
        case .unknown: .dsSlate
        }
    }
}
