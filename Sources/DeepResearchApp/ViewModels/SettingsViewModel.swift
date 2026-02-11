import SwiftUI
import Colony

@Observable
@MainActor
final class SettingsViewModel {
    var availableOllamaModels: [OllamaModelInfo] = []
    var isLoadingModels: Bool = false
    var ollamaConnectionStatus: ConnectionStatus = .unknown
    var settings = AppSettings()
    @ObservationIgnored private var modelRefreshTask: Task<Void, Never>? = nil

    enum ConnectionStatus: String {
        case unknown = "Not checked"
        case connected = "Connected"
        case disconnected = "Not reachable"
    }

    func fetchOllamaModels() async {
        isLoadingModels = true
        defer { isLoadingModels = false }

        do {
            let normalizedBaseURL = settings.ollamaBaseURL
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard let url = URL(string: normalizedBaseURL) else {
                availableOllamaModels = []
                settings.selectedOllamaModel = ""
                ollamaConnectionStatus = .disconnected
                return
            }
            let client = OllamaAPIClient(baseURL: url)
            let models = try await client.listModels()
            availableOllamaModels = models
            if let firstModel = models.first {
                let selectedModel = settings.selectedOllamaModel
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let selectedExists = models.contains(where: { $0.name == selectedModel })
                if selectedModel.isEmpty || !selectedExists {
                    settings.selectedOllamaModel = firstModel.name
                }
            } else {
                settings.selectedOllamaModel = ""
            }
            ollamaConnectionStatus = .connected
        } catch {
            availableOllamaModels = []
            ollamaConnectionStatus = .disconnected
        }
    }

    func checkConnection() async {
        do {
            let normalizedBaseURL = settings.ollamaBaseURL
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard let url = URL(string: normalizedBaseURL) else {
                ollamaConnectionStatus = .disconnected
                return
            }
            let client = OllamaAPIClient(baseURL: url)
            _ = try await client.listModels()
            ollamaConnectionStatus = .connected
        } catch {
            ollamaConnectionStatus = .disconnected
        }
    }

    func scheduleOllamaModelRefresh(delayNanoseconds: UInt64 = 400_000_000) {
        modelRefreshTask?.cancel()
        modelRefreshTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: delayNanoseconds)
            guard let self, !Task.isCancelled else { return }
            await self.fetchOllamaModels()
        }
    }

    deinit {
        modelRefreshTask?.cancel()
    }
}
