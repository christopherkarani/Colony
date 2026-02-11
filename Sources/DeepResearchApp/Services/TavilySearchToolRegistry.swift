import Foundation
import Colony

// MARK: - Tavily API Request/Response Types

private struct TavilySearchRequest: Encodable, Sendable {
    let api_key: String
    let query: String
    let search_depth: String
    let max_results: Int
    let include_answer: Bool
}

private struct TavilySearchResponse: Decodable, Sendable {
    let answer: String?
    let results: [TavilyResult]
}

private struct TavilyResult: Decodable, Sendable {
    let title: String
    let url: String
    let content: String
    let score: Double?
}

private struct TavilyExtractRequest: Encodable, Sendable {
    let api_key: String
    let urls: [String]
}

private struct TavilyExtractResponse: Decodable, Sendable {
    let results: [TavilyExtractResult]
}

private struct TavilyExtractResult: Decodable, Sendable {
    let url: String
    let rawContent: String

    private enum CodingKeys: String, CodingKey {
        case url
        case rawContent = "raw_content"
    }
}

// MARK: - Argument Types

private struct TavilySearchArgs: Decodable, Sendable {
    let query: String
    let search_depth: String?
    let max_results: Int?
    let include_answer: Bool?
}

private struct TavilyExtractArgs: Decodable, Sendable {
    let urls: [String]
}

// MARK: - Tool Registry

struct TavilySearchToolRegistry: HiveToolRegistry, Sendable {
    let apiKey: String

    private static let searchToolName = "tavily_search"
    private static let extractToolName = "tavily_extract"

    private static let searchURL = URL(string: "https://api.tavily.com/search")!
    private static let extractURL = URL(string: "https://api.tavily.com/extract")!

    func listTools() -> [HiveToolDefinition] {
        [
            HiveToolDefinition(
                name: Self.searchToolName,
                description: "Search the web using Tavily. Returns relevant results with titles, URLs, and content snippets.",
                parametersJSONSchema: """
                {"type":"object","properties":{"query":{"type":"string","description":"Search query"},"search_depth":{"type":"string","enum":["basic","advanced"],"description":"Search depth. 'advanced' for detailed results."},"max_results":{"type":"integer","description":"Max results 1-10, default 5"},"include_answer":{"type":"boolean","description":"Include AI-generated answer summary"}},"required":["query"]}
                """
            ),
            HiveToolDefinition(
                name: Self.extractToolName,
                description: "Extract content from web pages using Tavily. Returns the raw text content of the specified URLs.",
                parametersJSONSchema: """
                {"type":"object","properties":{"urls":{"type":"array","items":{"type":"string"},"description":"URLs to extract content from"}},"required":["urls"]}
                """
            ),
        ]
    }

    func invoke(_ call: HiveToolCall) async throws -> HiveToolResult {
        switch call.name {
        case Self.searchToolName:
            return await invokeSearch(call)
        case Self.extractToolName:
            return await invokeExtract(call)
        default:
            return HiveToolResult(
                toolCallID: call.id,
                content: "Error: Unknown tool '\(call.name)'. Available tools: \(Self.searchToolName), \(Self.extractToolName)."
            )
        }
    }

    // MARK: - Search

    private func invokeSearch(_ call: HiveToolCall) async -> HiveToolResult {
        let args: TavilySearchArgs
        do {
            args = try decodeArgs(call.argumentsJSON, as: TavilySearchArgs.self)
        } catch {
            return HiveToolResult(toolCallID: call.id, content: "Error: Failed to parse search arguments: \(error)")
        }

        let requestBody = TavilySearchRequest(
            api_key: apiKey,
            query: args.query,
            search_depth: args.search_depth ?? "basic",
            max_results: min(max(args.max_results ?? 5, 1), 10),
            include_answer: args.include_answer ?? true
        )

        do {
            let data = try await executeRequest(url: Self.searchURL, body: requestBody)
            let response = try JSONDecoder().decode(TavilySearchResponse.self, from: data)
            let formatted = formatSearchResults(query: args.query, response: response)
            return HiveToolResult(toolCallID: call.id, content: formatted)
        } catch {
            return HiveToolResult(toolCallID: call.id, content: "Error: Tavily search failed: \(error)")
        }
    }

    // MARK: - Extract

    private func invokeExtract(_ call: HiveToolCall) async -> HiveToolResult {
        let args: TavilyExtractArgs
        do {
            args = try decodeArgs(call.argumentsJSON, as: TavilyExtractArgs.self)
        } catch {
            return HiveToolResult(toolCallID: call.id, content: "Error: Failed to parse extract arguments: \(error)")
        }

        guard args.urls.isEmpty == false else {
            return HiveToolResult(toolCallID: call.id, content: "Error: No URLs provided for extraction.")
        }

        let requestBody = TavilyExtractRequest(
            api_key: apiKey,
            urls: args.urls
        )

        do {
            let data = try await executeRequest(url: Self.extractURL, body: requestBody)
            let response = try JSONDecoder().decode(TavilyExtractResponse.self, from: data)
            let formatted = formatExtractResults(response: response)
            return HiveToolResult(toolCallID: call.id, content: formatted)
        } catch {
            return HiveToolResult(toolCallID: call.id, content: "Error: Tavily extract failed: \(error)")
        }
    }

    // MARK: - Networking

    private func executeRequest<T: Encodable>(url: URL, body: T) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)

        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
            let responseBody = String(decoding: data, as: UTF8.self)
            throw TavilyError.httpError(statusCode: httpResponse.statusCode, body: responseBody)
        }

        return data
    }

    // MARK: - Formatting

    private func formatSearchResults(query: String, response: TavilySearchResponse) -> String {
        var lines: [String] = []
        lines.append("## Search Results for: \(query)")
        lines.append("")

        if let answer = response.answer, answer.isEmpty == false {
            lines.append("**AI Answer:** \(answer)")
            lines.append("")
        }

        if response.results.isEmpty {
            lines.append("No results found.")
        } else {
            for (index, result) in response.results.enumerated() {
                lines.append("### \(index + 1). \(result.title)")
                lines.append("URL: \(result.url)")
                lines.append(result.content)
                lines.append("")
            }
        }

        return lines.joined(separator: "\n")
    }

    private func formatExtractResults(response: TavilyExtractResponse) -> String {
        var lines: [String] = []
        lines.append("## Extracted Content")
        lines.append("")

        if response.results.isEmpty {
            lines.append("No content extracted.")
        } else {
            for (index, result) in response.results.enumerated() {
                lines.append("### \(index + 1). \(result.url)")
                lines.append(result.rawContent)
                lines.append("")
            }
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - Helpers

    private func decodeArgs<T: Decodable>(_ json: String, as type: T.Type) throws -> T {
        let trimmed = json.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = trimmed.data(using: .utf8) else {
            throw TavilyError.invalidArguments
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
}

// MARK: - Errors

private enum TavilyError: Error, Sendable, CustomStringConvertible {
    case invalidArguments
    case httpError(statusCode: Int, body: String)

    var description: String {
        switch self {
        case .invalidArguments:
            return "Invalid or malformed JSON arguments."
        case .httpError(let statusCode, let body):
            return "HTTP \(statusCode): \(body)"
        }
    }
}
