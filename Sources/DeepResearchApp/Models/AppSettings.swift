import SwiftUI

enum BackendType: String, Codable, Sendable, CaseIterable {
    case foundationModels = "foundation"
    case ollama = "ollama"

    var displayName: String {
        switch self {
        case .foundationModels: return "Foundation Models"
        case .ollama: return "Ollama"
        }
    }
}

@Observable
final class AppSettings: @unchecked Sendable {
    @ObservationIgnored
    @AppStorage("selectedBackend") var selectedBackend: BackendType = .foundationModels

    @ObservationIgnored
    @AppStorage("ollamaBaseURL") var ollamaBaseURL: String = "http://localhost:11434"

    @ObservationIgnored
    @AppStorage("selectedOllamaModel") var selectedOllamaModel: String = ""

    @ObservationIgnored
    @AppStorage("tavilyAPIKey") var tavilyAPIKey: String = ""

    var selectedModelName: String {
        selectedBackend == .foundationModels ? "foundation-models" : selectedOllamaModel
    }
}
