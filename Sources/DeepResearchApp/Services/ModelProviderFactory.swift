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
    struct ResolvedModel: Sendable {
        let model: ColonyModel
    }

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

    static func makeResolvedModel(settings: AppSettings) throws -> ResolvedModel {
        try makeResolvedModel(
            configuration: Configuration(
                backend: settings.selectedBackend,
                ollamaBaseURL: settings.ollamaBaseURL,
                selectedOllamaModel: settings.selectedOllamaModel
            )
        )
    }

    static func makeResolvedModel(configuration: Configuration) throws -> ResolvedModel {
        switch configuration.backend {
        case .foundationModels:
            return ResolvedModel(
                model: .foundationModels()
            )

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
            return ResolvedModel(
                model: ColonyModel(
                    client: ollamaClient,
                    capabilities: ollamaClient.colonyModelCapabilities
                )
            )
        }
    }
}
