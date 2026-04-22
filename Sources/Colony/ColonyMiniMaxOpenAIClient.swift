import Foundation

public enum ColonyMiniMaxClientError: Error, Sendable, LocalizedError {
    case invalidResponse(body: String)
    case emptyResponseBody
    case requestFailed(statusCode: Int, body: String)
    case decodingFailed(body: String, underlying: String)
    case transportFailed(String)

    public var errorDescription: String? {
        switch self {
        case .invalidResponse(let body):
            "MiniMax returned an invalid response. Body: \(body)"
        case .emptyResponseBody:
            "MiniMax returned an empty response body."
        case .requestFailed(let statusCode, let body):
            "MiniMax request failed with status \(statusCode): \(body)"
        case .decodingFailed(let body, let underlying):
            "MiniMax returned undecodable JSON: \(underlying). Body: \(body)"
        case .transportFailed(let message):
            "MiniMax transport failed: \(message)"
        }
    }
}

/// OpenAI-compatible MiniMax client.
///
/// MiniMax recommends `https://api.minimax.io/v1` for international users.
/// The OpenAI-compatible API keeps interleaved thinking inside `content`
/// when `reasoning_split` is disabled, which fits Hive's message model well.
public struct ColonyMiniMaxOpenAIClient: ColonyModelClient, Sendable {
    public struct Configuration: Sendable {
        public var apiKey: String
        public var baseURL: URL
        public var model: String
        public var maxTokens: Int?
        public var reasoningSplit: Bool
        public var timeoutInterval: TimeInterval
        public var maxRetryAttempts: Int
        public var initialRetryDelay: TimeInterval
        public var maxRetryDelay: TimeInterval
        public var enableCurlFallback: Bool

        public init(
            apiKey: String,
            baseURL: URL = URL(string: "https://api.minimax.io/v1")!,
            model: String = "MiniMax-M2.7",
            maxTokens: Int? = 4_096,
            reasoningSplit: Bool = false,
            timeoutInterval: TimeInterval = 180,
            maxRetryAttempts: Int = 3,
            initialRetryDelay: TimeInterval = 0.25,
            maxRetryDelay: TimeInterval = 2,
            enableCurlFallback: Bool = true
        ) {
            self.apiKey = apiKey
            self.baseURL = baseURL
            self.model = model
            self.maxTokens = maxTokens
            self.reasoningSplit = reasoningSplit
            self.timeoutInterval = timeoutInterval
            self.maxRetryAttempts = max(1, maxRetryAttempts)
            self.initialRetryDelay = max(0, initialRetryDelay)
            self.maxRetryDelay = max(initialRetryDelay, maxRetryDelay)
            self.enableCurlFallback = enableCurlFallback
        }
    }

    private let configuration: Configuration
    private let session: URLSession

    public init(
        configuration: Configuration,
        session: URLSession = .shared
    ) {
        self.configuration = configuration
        self.session = session
    }

    public init(
        apiKey: String,
        baseURL: URL = URL(string: "https://api.minimax.io/v1")!,
        model: String = "MiniMax-M2.7",
        maxTokens: Int? = 4_096,
        reasoningSplit: Bool = false,
        timeoutInterval: TimeInterval = 180,
        maxRetryAttempts: Int = 3,
        initialRetryDelay: TimeInterval = 0.25,
        maxRetryDelay: TimeInterval = 2,
        enableCurlFallback: Bool = true,
        session: URLSession = .shared
    ) {
        self.init(
            configuration: Configuration(
                apiKey: apiKey,
                baseURL: baseURL,
                model: model,
                maxTokens: maxTokens,
                reasoningSplit: reasoningSplit,
                timeoutInterval: timeoutInterval,
                maxRetryAttempts: maxRetryAttempts,
                initialRetryDelay: initialRetryDelay,
                maxRetryDelay: maxRetryDelay,
                enableCurlFallback: enableCurlFallback
            ),
            session: session
        )
    }

    public func generate(_ request: ColonyInferenceRequest) async throws -> ColonyInferenceResponse {
        ColonyInferenceResponse(try await complete(request.swarmChatRequest))
    }

    public func stream(_ request: ColonyInferenceRequest) -> AsyncThrowingStream<ColonyInferenceStreamChunk, Error> {
        let stream = stream(request.swarmChatRequest)
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await chunk in stream {
                        switch chunk {
                        case .token(let token):
                            continuation.yield(.token(token))
                        case .final(let response):
                            continuation.yield(.final(ColonyInferenceResponse(response)))
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

    package func complete(_ request: SwarmChatRequest) async throws -> SwarmChatResponse {
        let sanitizedMessages = sanitizeMessages(request.messages)
        let payload = OpenAIChatCompletionRequest(
            model: request.model.isEmpty ? configuration.model : request.model,
            messages: try sanitizedMessages.compactMap(convertMessage),
            tools: request.tools.isEmpty ? nil : request.tools.map(convertTool),
            maxTokens: configuration.maxTokens,
            reasoningSplit: configuration.reasoningSplit
        )

        var urlRequest = URLRequest(url: configuration.baseURL.appending(path: "chat/completions"))
        urlRequest.httpMethod = "POST"
        urlRequest.timeoutInterval = configuration.timeoutInterval
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("Bearer \(configuration.apiKey)", forHTTPHeaderField: "Authorization")
        urlRequest.httpBody = try JSONEncoder.minimax.encode(payload)

        var lastError: Error?
        for attempt in 1 ... configuration.maxRetryAttempts {
            do {
                let (data, response) = try await performRequest(urlRequest, attempt: attempt)
                return try decodeResponse(data: data, response: response)
            } catch {
                if error is CancellationError {
                    throw error
                }
                lastError = error
                guard shouldRetry(error: error, attempt: attempt) else {
                    throw error
                }
                try await Task.sleep(for: retryDelay(forAttempt: attempt))
            }
        }

        if let lastError, shouldUseCurlFallback(for: lastError) {
            let (data, response) = try performCurlFallback(urlRequest)
            return try decodeResponse(data: data, response: response)
        }

        throw lastError ?? ColonyMiniMaxClientError.invalidResponse(body: "<missing error>")
    }

    package func stream(_ request: SwarmChatRequest) -> AsyncThrowingStream<SwarmChatStreamChunk, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let response = try await complete(request)
                    if response.message.content.isEmpty == false {
                        continuation.yield(.token(response.message.content))
                    }
                    continuation.yield(.final(response))
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

    private func decodeResponse(data: Data, response: URLResponse) throws -> SwarmChatResponse {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ColonyMiniMaxClientError.invalidResponse(body: "<non-http response>")
        }

        let body = bodyPreview(from: data)
        guard (200 ..< 300).contains(httpResponse.statusCode) else {
            throw ColonyMiniMaxClientError.requestFailed(statusCode: httpResponse.statusCode, body: body)
        }

        guard dataContainsMeaningfulBody(data) else {
            throw ColonyMiniMaxClientError.emptyResponseBody
        }

        let completion: OpenAIChatCompletionResponse
        do {
            completion = try JSONDecoder.minimax.decode(OpenAIChatCompletionResponse.self, from: data)
        } catch {
            throw ColonyMiniMaxClientError.decodingFailed(body: body, underlying: String(describing: error))
        }

        guard let message = completion.choices.first?.message else {
            throw ColonyMiniMaxClientError.invalidResponse(body: body)
        }

        return SwarmChatResponse(
            message: SwarmChatMessage(
                id: message.id ?? completion.id ?? UUID().uuidString,
                role: .assistant,
                content: message.content ?? "",
                toolCalls: message.toolCalls?.map(convertToolCall) ?? []
            )
        )
    }

    private func performRequest(_ urlRequest: URLRequest, attempt: Int) async throws -> (Data, URLResponse) {
        guard attempt > 1 else {
            return try await session.data(for: urlRequest)
        }

        let retrySession = makeRetrySession()
        defer { retrySession.finishTasksAndInvalidate() }
        return try await retrySession.data(for: urlRequest)
    }

    private func shouldRetry(error: Error, attempt: Int) -> Bool {
        guard attempt < configuration.maxRetryAttempts else {
            return false
        }

        switch error {
        case ColonyMiniMaxClientError.emptyResponseBody:
            return true
        case ColonyMiniMaxClientError.requestFailed(let statusCode, _):
            return Self.retryableStatusCodes.contains(statusCode)
        case ColonyMiniMaxClientError.decodingFailed(let body, let underlying):
            return body == "<empty body>" || underlying.localizedCaseInsensitiveContains("Unexpected end of file")
        case ColonyMiniMaxClientError.invalidResponse(let body):
            return body == "<non-http response>"
        case let urlError as URLError:
            return Self.retryableURLErrorCodes.contains(urlError.code)
        default:
            return false
        }
    }

    private func shouldUseCurlFallback(for error: Error) -> Bool {
        guard configuration.enableCurlFallback else {
            return false
        }

        switch error {
        case ColonyMiniMaxClientError.emptyResponseBody:
            return true
        case ColonyMiniMaxClientError.decodingFailed(_, let underlying):
            return underlying.localizedCaseInsensitiveContains("Unexpected end of file")
        default:
            return false
        }
    }

    private func retryDelay(forAttempt attempt: Int) -> Duration {
        let multiplier = pow(2.0, Double(max(0, attempt - 1)))
        let delaySeconds = min(configuration.initialRetryDelay * multiplier, configuration.maxRetryDelay)
        return .milliseconds(Int64((delaySeconds * 1_000).rounded()))
    }

    private func makeRetrySession() -> URLSession {
        let configurationCopy = (session.configuration.copy() as? URLSessionConfiguration) ?? .ephemeral
        configurationCopy.urlCache = nil

        var additionalHeaders = configurationCopy.httpAdditionalHeaders ?? [:]
        additionalHeaders["Accept-Encoding"] = "identity"
        configurationCopy.httpAdditionalHeaders = additionalHeaders

        return URLSession(configuration: configurationCopy)
    }

    private func performCurlFallback(_ urlRequest: URLRequest) throws -> (Data, URLResponse) {
        guard let url = urlRequest.url else {
            throw ColonyMiniMaxClientError.transportFailed("missing request URL")
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/curl")

        let timeoutSeconds = max(1, Int(ceil(configuration.timeoutInterval)))
        process.arguments = [
            "--silent",
            "--show-error",
            "--location",
            "--http1.1",
            "--max-time", String(timeoutSeconds),
            "-X", urlRequest.httpMethod ?? "POST",
            url.absoluteString,
            "-H", "Content-Type: application/json",
            "-H", "Authorization: Bearer \(configuration.apiKey)",
            "--data-binary", "@-",
            "--write-out", "\n__MINIMAX_STATUS__:%{http_code}"
        ]

        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()
        if let body = urlRequest.httpBody {
            stdinPipe.fileHandleForWriting.write(body)
        }
        try? stdinPipe.fileHandleForWriting.close()

        process.waitUntilExit()

        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

        guard process.terminationStatus == 0 else {
            let stderr = String(data: stderrData, encoding: .utf8) ?? "<non-utf8 stderr>"
            throw ColonyMiniMaxClientError.transportFailed(stderr)
        }

        let marker = "\n__MINIMAX_STATUS__:"
        guard let output = String(data: stdoutData, encoding: .utf8),
              let range = output.range(of: marker, options: .backwards) else {
            throw ColonyMiniMaxClientError.transportFailed("curl did not return a status marker")
        }

        let body = Data(output[..<range.lowerBound].utf8)
        let statusString = output[range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
        guard let statusCode = Int(statusString) else {
            throw ColonyMiniMaxClientError.transportFailed("curl returned an invalid status code: \(statusString)")
        }

        let response = HTTPURLResponse(
            url: url,
            statusCode: statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!

        return (body, response)
    }

    private func convertMessage(_ message: SwarmChatMessage) throws -> OpenAIChatMessage? {
        guard message.op == nil else {
            return nil
        }

        switch message.role {
        case .system:
            return OpenAIChatMessage(role: "system", content: message.content)
        case .user:
            return OpenAIChatMessage(role: "user", content: message.content)
        case .assistant:
            let toolCalls = try message.toolCalls.map(convertOutgoingToolCall)
            return OpenAIChatMessage(
                role: "assistant",
                content: message.content.isEmpty ? nil : message.content,
                toolCalls: toolCalls.isEmpty ? nil : toolCalls
            )
        case .tool:
            return OpenAIChatMessage(
                role: "tool",
                content: message.content,
                toolCallID: message.toolCallID
            )
        }
    }

    private func sanitizeMessages(_ messages: [SwarmChatMessage]) -> [SwarmChatMessage] {
        guard messages.isEmpty == false else {
            return messages
        }

        let toolResultIDs: Set<String> = Set(
            messages.compactMap { message in
                guard message.role == .tool else { return nil }
                return message.toolCallID
            }
        )

        var announcedToolCallIDs: Set<String> = []
        var sanitized: [SwarmChatMessage] = []
        sanitized.reserveCapacity(messages.count)

        for message in messages {
            switch message.role {
            case .assistant:
                let filteredToolCalls = message.toolCalls.filter { toolResultIDs.contains($0.id) }
                announcedToolCallIDs.formUnion(filteredToolCalls.map { $0.id })

                if filteredToolCalls.count == message.toolCalls.count {
                    sanitized.append(message)
                    continue
                }

                if message.content.isEmpty, filteredToolCalls.isEmpty {
                    continue
                }

                sanitized.append(
                    SwarmChatMessage(
                        id: message.id,
                        role: message.role,
                        content: message.content,
                        name: message.name,
                        toolCallID: message.toolCallID,
                        toolCalls: filteredToolCalls,
                        op: message.op
                    )
                )
            case .tool:
                guard let toolCallID = message.toolCallID,
                      announcedToolCallIDs.contains(toolCallID) else {
                    continue
                }
                sanitized.append(message)
            default:
                sanitized.append(message)
            }
        }

        return sanitized
    }

    private func convertTool(_ tool: SwarmToolDefinition) -> OpenAIChatTool {
        OpenAIChatTool(
            function: OpenAIChatTool.FunctionDescriptor(
                name: tool.name,
                description: tool.description,
                parameters: JSONValue.parse(tool.parametersJSONSchema) ?? .object([:])
            )
        )
    }

    private func convertOutgoingToolCall(_ toolCall: SwarmToolCall) throws -> OpenAIChatToolCall {
        let argumentsData = Data(toolCall.argumentsJSON.utf8)
        let arguments = try JSONDecoder().decode(JSONValue.self, from: argumentsData)
        return OpenAIChatToolCall(
            id: toolCall.id,
            function: .init(name: toolCall.name, arguments: arguments.jsonString)
        )
    }

    private func convertToolCall(_ toolCall: OpenAIChatToolCall) -> SwarmToolCall {
        SwarmToolCall(
            id: toolCall.id,
            name: toolCall.function.name,
            argumentsJSON: toolCall.function.arguments
        )
    }

    private func dataContainsMeaningfulBody(_ data: Data) -> Bool {
        guard let string = String(data: data, encoding: .utf8) else {
            return data.isEmpty == false
        }
        return string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    private func bodyPreview(from data: Data) -> String {
        guard let string = String(data: data, encoding: .utf8) else {
            return data.isEmpty ? "<empty body>" : "<non-utf8 body>"
        }

        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else {
            return "<empty body>"
        }

        return String(trimmed.prefix(512))
    }

    private static let retryableStatusCodes: Set<Int> = [408, 409, 429, 500, 502, 503, 504]
    private static let retryableURLErrorCodes: Set<URLError.Code> = [
        .timedOut,
        .networkConnectionLost,
        .notConnectedToInternet,
        .cannotConnectToHost,
        .cannotFindHost,
        .dnsLookupFailed,
        .resourceUnavailable,
        .internationalRoamingOff,
        .callIsActive,
        .dataNotAllowed
    ]
}

private struct OpenAIChatCompletionRequest: Encodable {
    let model: String
    let messages: [OpenAIChatMessage]
    let tools: [OpenAIChatTool]?
    let maxTokens: Int?
    let reasoningSplit: Bool

    enum CodingKeys: String, CodingKey {
        case model
        case messages
        case tools
        case maxTokens = "max_tokens"
        case reasoningSplit = "reasoning_split"
    }
}

private struct OpenAIChatCompletionResponse: Decodable {
    struct Choice: Decodable {
        let message: OpenAIChatMessage
    }

    let id: String?
    let choices: [Choice]
}

private struct OpenAIChatMessage: Codable {
    let role: String
    let content: String?
    let toolCalls: [OpenAIChatToolCall]?
    let toolCallID: String?
    let id: String?

    enum CodingKeys: String, CodingKey {
        case role
        case content
        case toolCalls = "tool_calls"
        case toolCallID = "tool_call_id"
        case id
    }

    init(
        role: String,
        content: String?,
        toolCalls: [OpenAIChatToolCall]? = nil,
        toolCallID: String? = nil,
        id: String? = nil
    ) {
        self.role = role
        self.content = content
        self.toolCalls = toolCalls
        self.toolCallID = toolCallID
        self.id = id
    }
}

private struct OpenAIChatTool: Encodable {
    struct FunctionDescriptor: Encodable {
        let name: String
        let description: String
        let parameters: JSONValue
    }

    let type = "function"
    let function: FunctionDescriptor
}

private struct OpenAIChatToolCall: Codable {
    struct FunctionCall: Codable {
        let name: String
        let arguments: String
    }

    let id: String
    let type: String
    let function: FunctionCall

    init(id: String, type: String = "function", function: FunctionCall) {
        self.id = id
        self.type = type
        self.function = function
    }
}

private enum JSONValue: Codable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case array([JSONValue])
    case object([String: JSONValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let bool = try? container.decode(Bool.self) {
            self = .bool(bool)
        } else if let int = try? container.decode(Int.self) {
            self = .number(Double(int))
        } else if let double = try? container.decode(Double.self) {
            self = .number(double)
        } else if let string = try? container.decode(String.self) {
            self = .string(string)
        } else if let array = try? container.decode([JSONValue].self) {
            self = .array(array)
        } else if let object = try? container.decode([String: JSONValue].self) {
            self = .object(object)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value):
            try container.encode(value)
        case .number(let value):
            try container.encode(value)
        case .bool(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .object(let value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        }
    }

    static func parse(_ json: String) -> JSONValue? {
        guard let data = json.data(using: .utf8) else {
            return nil
        }
        return try? JSONDecoder().decode(JSONValue.self, from: data)
    }

    var jsonObject: Any {
        switch self {
        case .string(let value):
            return value
        case .number(let value):
            if value.rounded() == value {
                return Int(value)
            }
            return value
        case .bool(let value):
            return value
        case .array(let value):
            return value.map(\.jsonObject)
        case .object(let value):
            return value.mapValues(\.jsonObject)
        case .null:
            return NSNull()
        }
    }

    var jsonString: String {
        guard JSONSerialization.isValidJSONObject(jsonObject),
              let data = try? JSONSerialization.data(withJSONObject: jsonObject, options: [.sortedKeys]),
              let string = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return string
    }
}

private extension JSONEncoder {
    static let minimax: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()
}

private extension JSONDecoder {
    static let minimax = JSONDecoder()
}
