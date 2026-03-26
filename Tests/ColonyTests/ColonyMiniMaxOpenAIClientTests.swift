import Foundation
import Testing
@_spi(ColonyInternal) import Swarm
@testable import Colony

@Suite("Colony MiniMax OpenAI Client Tests", .serialized)
struct ColonyMiniMaxOpenAIClientTests {
    @Test("client formats request for MiniMax OpenAI-compatible endpoint")
    func formatsRequest() async throws {
        let recorder = RequestRecorder()
        let session = makeSession { request in
            recorder.capture(request)
            return [
                .http(
                    statusCode: 200,
                    body: """
                    {
                      "id": "chatcmpl-123",
                      "choices": [
                        {
                          "message": {
                            "role": "assistant",
                            "content": "<think>plan</think>",
                            "tool_calls": [
                              {
                                "id": "call-1",
                                "type": "function",
                                "function": {
                                  "name": "read_observation",
                                  "arguments": "{}"
                                }
                              }
                            ]
                          }
                        }
                      ]
                    }
                    """
                )
            ]
        }

        let client = ColonyMiniMaxOpenAIClient(
            apiKey: "test-key",
            model: "MiniMax-M2.7",
            session: session
        )

        let response = try await client.complete(
            HiveChatRequest(
                model: "MiniMax-M2.7",
                messages: [
                    HiveChatMessage(id: "system-1", role: .system, content: "You are a coding agent."),
                    HiveChatMessage(id: "user-1", role: .user, content: "Inspect the game state.")
                ],
                tools: [
                    HiveToolDefinition(
                        name: "read_observation",
                        description: "Read game state.",
                        parametersJSONSchema: #"{"type":"object","properties":{}}"#
                    )
                ]
            )
        )

        let request = try #require(recorder.request)
        #expect(request.url?.absoluteString == "https://api.minimax.io/v1/chat/completions")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-key")

        let body = try #require(request.httpBody)
        let payload = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        #expect(payload?["model"] as? String == "MiniMax-M2.7")
        #expect(payload?["reasoning_split"] as? Bool == false)
        #expect((payload?["messages"] as? [[String: Any]])?.count == 2)
        #expect((payload?["tools"] as? [[String: Any]])?.count == 1)

        #expect(response.message.content == "<think>plan</think>")
        #expect(response.message.toolCalls.count == 1)
        #expect(response.message.toolCalls.first?.name == "read_observation")
    }

    @Test("client preserves assistant tool calls and tool results in follow-up requests")
    func preservesToolCallHistory() async throws {
        let recorder = RequestRecorder()
        let session = makeSession { request in
            recorder.capture(request)
            return [
                .http(
                    statusCode: 200,
                    body: """
                    {
                      "id": "chatcmpl-456",
                      "choices": [
                        {
                          "message": {
                            "role": "assistant",
                            "content": "done"
                          }
                        }
                      ]
                    }
                    """
                )
            ]
        }

        let client = ColonyMiniMaxOpenAIClient(
            apiKey: "test-key",
            model: "MiniMax-M2.7",
            session: session
        )

        _ = try await client.complete(
            HiveChatRequest(
                model: "MiniMax-M2.7",
                messages: [
                    HiveChatMessage(id: "user-1", role: .user, content: "Start"),
                    HiveChatMessage(
                        id: "assistant-1",
                        role: .assistant,
                        content: "<think>Need state.</think>",
                        toolCalls: [
                            HiveToolCall(id: "call-1", name: "read_observation", argumentsJSON: "{}")
                        ]
                    ),
                    HiveChatMessage(
                        id: "tool-1",
                        role: .tool,
                        content: #"{"scene":"titleMenu"}"#,
                        name: "read_observation",
                        toolCallID: "call-1"
                    )
                ],
                tools: []
            )
        )

        let request = try #require(recorder.request)
        let body = try #require(request.httpBody)
        let payload = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        let messages = try #require(payload?["messages"] as? [[String: Any]])

        let assistant = try #require(messages.first(where: { $0["role"] as? String == "assistant" }))
        let toolCalls = try #require(assistant["tool_calls"] as? [[String: Any]])
        #expect((toolCalls.first?["id"] as? String) == "call-1")

        let tool = try #require(messages.first(where: { $0["role"] as? String == "tool" }))
        #expect(tool["tool_call_id"] as? String == "call-1")
        #expect(tool["content"] as? String == #"{"scene":"titleMenu"}"#)
    }

    @Test("client drops orphaned tool results that lost their assistant tool call")
    func dropsOrphanedToolResults() async throws {
        let recorder = RequestRecorder()
        let session = makeSession { request in
            recorder.capture(request)
            return [
                .http(
                    statusCode: 200,
                    body: """
                    {
                      "id": "chatcmpl-orphan",
                      "choices": [
                        {
                          "message": {
                            "role": "assistant",
                            "content": "continue"
                          }
                        }
                      ]
                    }
                    """
                )
            ]
        }

        let client = ColonyMiniMaxOpenAIClient(
            apiKey: "test-key",
            model: "MiniMax-M2.7",
            session: session
        )

        _ = try await client.complete(
            HiveChatRequest(
                model: "MiniMax-M2.7",
                messages: [
                    HiveChatMessage(id: "user-1", role: .user, content: "Start"),
                    HiveChatMessage(
                        id: "assistant-1",
                        role: .assistant,
                        content: "",
                        toolCalls: [
                            HiveToolCall(id: "call-1", name: "read_observation", argumentsJSON: "{}")
                        ]
                    ),
                    HiveChatMessage(
                        id: "tool-1",
                        role: .tool,
                        content: #"{"scene":"titleMenu"}"#,
                        name: "read_observation",
                        toolCallID: "call-1"
                    ),
                    HiveChatMessage(
                        id: "tool-2",
                        role: .tool,
                        content: #"{"scene":"orphan"}"#,
                        name: "read_observation",
                        toolCallID: "call-missing"
                    )
                ],
                tools: []
            )
        )

        let request = try #require(recorder.request)
        let body = try #require(request.httpBody)
        let payload = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        let messages = try #require(payload?["messages"] as? [[String: Any]])

        #expect(messages.contains(where: { ($0["tool_call_id"] as? String) == "call-1" }))
        #expect(messages.contains(where: { ($0["tool_call_id"] as? String) == "call-missing" }) == false)
    }

    @Test("client retries an empty body and succeeds on a later valid response")
    func retriesEmptyBody() async throws {
        let session = makeSession { request in
            _ = request
            return [
                .http(statusCode: 200, body: ""),
                .http(
                    statusCode: 200,
                    body: """
                    {
                      "id": "chatcmpl-789",
                      "choices": [
                        {
                          "message": {
                            "role": "assistant",
                            "content": "ok"
                          }
                        }
                      ]
                    }
                    """
                )
            ]
        }

        let client = ColonyMiniMaxOpenAIClient(
            apiKey: "test-key",
            model: "MiniMax-M2.7",
            maxRetryAttempts: 2,
            initialRetryDelay: 0,
            maxRetryDelay: 0,
            session: session
        )

        let response = try await client.complete(
            HiveChatRequest(
                model: "MiniMax-M2.7",
                messages: [HiveChatMessage(id: "user-1", role: .user, content: "Retry")],
                tools: []
            )
        )

        #expect(response.message.content == "ok")
    }

    @Test("client throws deterministic error after persistent empty bodies")
    func failsAfterPersistentEmptyBody() async throws {
        let session = makeSession { _ in
            [
                .http(statusCode: 200, body: "   "),
                .http(statusCode: 200, body: ""),
                .http(statusCode: 200, body: "\n")
            ]
        }

        let client = ColonyMiniMaxOpenAIClient(
            apiKey: "test-key",
            model: "MiniMax-M2.7",
            maxRetryAttempts: 3,
            initialRetryDelay: 0,
            maxRetryDelay: 0,
            session: session
        )

        let threwExpectedError: Bool
        do {
            _ = try await client.complete(
                HiveChatRequest(
                    model: "MiniMax-M2.7",
                    messages: [HiveChatMessage(id: "user-1", role: .user, content: "Retry")],
                    tools: []
                )
            )
            threwExpectedError = false
        } catch ColonyMiniMaxClientError.emptyResponseBody {
            threwExpectedError = true
        } catch {
            threwExpectedError = false
        }

        #expect(threwExpectedError)
    }
}

private final class RequestRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private(set) var request: URLRequest?
    private(set) var requests: [URLRequest] = []

    func capture(_ request: URLRequest) {
        var normalizedRequest = request
        if normalizedRequest.httpBody == nil,
           let stream = normalizedRequest.httpBodyStream {
            normalizedRequest.httpBody = readBody(from: stream)
        }

        lock.lock()
        self.request = normalizedRequest
        self.requests.append(normalizedRequest)
        lock.unlock()
    }

    private func readBody(from stream: InputStream) -> Data {
        stream.open()
        defer { stream.close() }

        var data = Data()
        let bufferSize = 4_096
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }

        while stream.hasBytesAvailable {
            let count = stream.read(buffer, maxLength: bufferSize)
            guard count > 0 else { break }
            data.append(buffer, count: count)
        }

        return data
    }
}

private enum TestResponse: Sendable {
    case http(statusCode: Int, body: String)
    case error(URLError)
}

private final class ResponseSequence: @unchecked Sendable {
    private let lock = NSLock()
    private let responses: [TestResponse]
    private var index = 0

    init(_ responses: [TestResponse]) {
        self.responses = responses
    }

    func next() -> TestResponse {
        lock.lock()
        defer { lock.unlock() }
        guard index < responses.count else {
            return responses.last ?? .error(URLError(.badServerResponse))
        }
        let response = responses[index]
        index += 1
        return response
    }
}

private final class SequenceStore: @unchecked Sendable {
    private let lock = NSLock()
    private var provider: (@Sendable (URLRequest) throws -> [TestResponse])?
    private var sequences: [String: ResponseSequence] = [:]

    func configure(_ provider: @escaping @Sendable (URLRequest) throws -> [TestResponse]) {
        lock.lock()
        self.provider = provider
        sequences = [:]
        lock.unlock()
    }

    func sequence(for request: URLRequest) throws -> ResponseSequence {
        lock.lock()
        defer { lock.unlock() }
        guard let provider else {
            throw URLError(.badServerResponse)
        }

        let key = request.url?.absoluteString ?? UUID().uuidString
        if let sequence = sequences[key] {
            return sequence
        }

        let sequence = ResponseSequence(try provider(request))
        sequences[key] = sequence
        return sequence
    }
}

private final class TestURLProtocol: URLProtocol, @unchecked Sendable {
    static let store = SequenceStore()

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        do {
            let sequence = try Self.store.sequence(for: request)
            switch sequence.next() {
            case .http(let statusCode, let body):
                let response = HTTPURLResponse(
                    url: request.url ?? URL(string: "https://api.minimax.io/v1/chat/completions")!,
                    statusCode: statusCode,
                    httpVersion: "HTTP/1.1",
                    headerFields: ["Content-Type": "application/json"]
                )!
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: Data(body.utf8))
                client?.urlProtocolDidFinishLoading(self)
            case .error(let error):
                client?.urlProtocol(self, didFailWithError: error)
            }
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private func makeSession(
    handler: @escaping @Sendable (URLRequest) throws -> [TestResponse]
) -> URLSession {
    TestURLProtocol.store.configure(handler)

    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [TestURLProtocol.self]
    return URLSession(configuration: configuration)
}
