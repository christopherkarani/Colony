import Foundation

enum OllamaAPIError: Error, Sendable, CustomStringConvertible {
    case invalidURL(String)
    case httpError(statusCode: Int, body: String)
    case decodingError(String)
    case streamingError(String)

    var description: String {
        switch self {
        case .invalidURL(let url):
            "Invalid Ollama URL: \(url)"
        case .httpError(let statusCode, let body):
            "Ollama HTTP error \(statusCode): \(body)"
        case .decodingError(let message):
            "Ollama decoding error: \(message)"
        case .streamingError(let message):
            "Ollama streaming error: \(message)"
        }
    }
}

extension OllamaAPIError: LocalizedError {
    var errorDescription: String? {
        description
    }
}

struct OllamaAPIClient: Sendable {
    let baseURL: URL

    init(baseURL: URL = URL(string: "http://localhost:11434")!) {
        self.baseURL = baseURL
    }

    // MARK: - List Models

    func listModels() async throws -> [OllamaModelInfo] {
        let url = baseURL.appendingPathComponent("api/tags")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw OllamaAPIError.httpError(statusCode: -1, body: "Non-HTTP response")
        }

        guard httpResponse.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? "(unreadable)"
            throw OllamaAPIError.httpError(statusCode: httpResponse.statusCode, body: body)
        }

        do {
            let decoded = try JSONDecoder().decode(OllamaTagsResponse.self, from: data)
            return decoded.models
        } catch {
            throw OllamaAPIError.decodingError(error.localizedDescription)
        }
    }

    // MARK: - Chat Stream

    func chatStream(
        model: String,
        messages: [OllamaChatMessage],
        tools: [OllamaToolDef]?
    ) -> AsyncThrowingStream<OllamaChatChunk, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let url = baseURL.appendingPathComponent("api/chat")
                    var request = URLRequest(url: url)
                    request.httpMethod = "POST"
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")

                    let body = OllamaChatRequest(
                        model: model,
                        messages: messages,
                        stream: true,
                        tools: tools
                    )

                    let encoder = JSONEncoder()
                    request.httpBody = try encoder.encode(body)

                    let (bytes, response) = try await URLSession.shared.bytes(for: request)

                    guard let httpResponse = response as? HTTPURLResponse else {
                        throw OllamaAPIError.httpError(statusCode: -1, body: "Non-HTTP response")
                    }

                    guard httpResponse.statusCode == 200 else {
                        var errorBody = ""
                        for try await line in bytes.lines {
                            errorBody += line
                        }
                        throw OllamaAPIError.httpError(statusCode: httpResponse.statusCode, body: errorBody)
                    }

                    let decoder = JSONDecoder()

                    for try await line in bytes.lines {
                        if Task.isCancelled { break }

                        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty else { continue }

                        guard let lineData = trimmed.data(using: .utf8) else {
                            throw OllamaAPIError.decodingError("Line is not valid UTF-8")
                        }

                        let chunk: OllamaChatChunk
                        do {
                            chunk = try decoder.decode(OllamaChatChunk.self, from: lineData)
                        } catch {
                            throw OllamaAPIError.decodingError("Failed to decode chunk: \(error.localizedDescription)")
                        }

                        continuation.yield(chunk)

                        if chunk.done {
                            break
                        }
                    }

                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }
}
