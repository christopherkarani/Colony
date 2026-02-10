import Colony
import Foundation

enum ModelProviderError: Error, Sendable {
    case invalidBaseURL(String)
    case missingOllamaModel
}

extension ModelProviderError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .invalidBaseURL(let value):
            return "Invalid Ollama base URL: \(value)"
        case .missingOllamaModel:
            return "Select an Ollama model in Settings before starting a run."
        }
    }
}

enum ModelProviderFactory {
    struct Configuration: Equatable, Sendable {
        let backend: BackendType
        let ollamaBaseURL: String
        let selectedOllamaModel: String

        init(
            backend: BackendType,
            ollamaBaseURL: String,
            selectedOllamaModel: String
        ) {
            self.backend = backend
            self.ollamaBaseURL = ollamaBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
            self.selectedOllamaModel = selectedOllamaModel
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    static func makeClient(settings: AppSettings) throws -> AnyHiveModelClient {
        try makeClient(
            configuration: Configuration(
                backend: settings.selectedBackend,
                ollamaBaseURL: settings.ollamaBaseURL,
                selectedOllamaModel: settings.selectedOllamaModel
            )
        )
    }

    static func makeClient(configuration: Configuration) throws -> AnyHiveModelClient {
        switch configuration.backend {
        case .foundationModels:
            return AnyHiveModelClient(ColonyFoundationModelsClient())

        case .ollama:
            guard !configuration.selectedOllamaModel.isEmpty else {
                throw ModelProviderError.missingOllamaModel
            }
            guard let baseURL = URL(string: configuration.ollamaBaseURL) else {
                throw ModelProviderError.invalidBaseURL(configuration.ollamaBaseURL)
            }
            let apiClient = OllamaAPIClient(baseURL: baseURL)
            let ollamaClient = OllamaModelClient(
                apiClient: apiClient,
                modelName: configuration.selectedOllamaModel
            )
            return AnyHiveModelClient(ollamaClient)
        }
    }
}
