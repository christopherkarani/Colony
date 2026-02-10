import CryptoKit
import Foundation
import HiveCore

#if canImport(FoundationModels)
import FoundationModels
#endif

public enum ColonyFoundationModelsClientError: Error, Sendable, CustomStringConvertible {
    case foundationModelsUnavailable
    case generationFailed(String)
    case invalidToolCallFormat(String)

    public var description: String {
        switch self {
        case .foundationModelsUnavailable:
            "Foundation Models are unavailable on this device or platform."
        case .generationFailed(let message):
            "Foundation Models generation failed: \(message)"
        case .invalidToolCallFormat(let message):
            "Invalid tool call format: \(message)"
        }
    }
}

extension ColonyFoundationModelsClientError: LocalizedError {
    public var errorDescription: String? {
        description
    }
}

public struct ColonyFoundationModelsClient: HiveModelClient, Sendable {
    public struct Configuration: Sendable {
        public enum ToolInstructionVerbosity: Sendable {
            case compact
            case verbose
        }

        public var additionalInstructions: String?
        public var prewarmSession: Bool
        public var toolInstructionVerbosity: ToolInstructionVerbosity

        public init(
            additionalInstructions: String? = nil,
            prewarmSession: Bool = false,
            toolInstructionVerbosity: ToolInstructionVerbosity = .compact
        ) {
            self.additionalInstructions = additionalInstructions
            self.prewarmSession = prewarmSession
            self.toolInstructionVerbosity = toolInstructionVerbosity
        }
    }

    public static var isAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, visionOS 26.0, *) {
            return SystemLanguageModel.default.availability == .available
        }
        return false
        #else
        return false
        #endif
    }

    public init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
    }

    public func complete(_ request: HiveChatRequest) async throws -> HiveChatResponse {
        try await streamFinal(request)
    }

    public func stream(_ request: HiveChatRequest) -> AsyncThrowingStream<HiveChatStreamChunk, Error> {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, visionOS 26.0, *) {
            return streamAvailable(request)
        } else {
            return streamUnavailable()
        }
        #else
        return streamUnavailable()
        #endif
    }

    // MARK: - Private

    private let configuration: Configuration

    private static let toolCallOpenTag = "<tool_call>"
    private static let toolCallCloseTag = "</tool_call>"

    private func streamUnavailable() -> AsyncThrowingStream<HiveChatStreamChunk, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish(throwing: ColonyFoundationModelsClientError.foundationModelsUnavailable)
        }
    }

    private func messageID() -> String {
        UUID().uuidString
    }

    private func toolCallID(name: String, argumentsJSON: String, index: Int) -> String {
        var bytes = Data()
        bytes.append(contentsOf: "FMTC1".utf8)
        bytes.append(contentsOf: name.utf8)
        bytes.append(0x00)
        bytes.append(contentsOf: argumentsJSON.utf8)
        bytes.append(0x00)
        var indexBE = UInt32(index).bigEndian
        withUnsafeBytes(of: &indexBE) { bytes.append(contentsOf: $0) }
        let hash = SHA256.hash(data: bytes)
        return "fm:" + hash.map { String(format: "%02x", $0) }.joined()
    }

    private func makeResponse(
        rawModelText: String,
        toolsAllowed: Set<String>
    ) throws -> HiveChatResponse {
        let parsed = try parseFinalAssistantOutput(
            raw: rawModelText,
            toolsAllowed: toolsAllowed
        )
        let message = HiveChatMessage(
            id: messageID(),
            role: .assistant,
            content: parsed.visibleText,
            toolCalls: parsed.toolCalls
        )
        return HiveChatResponse(message: message)
    }

    private func makePrompt(from request: HiveChatRequest) -> (instructions: String?, prompt: String, toolsAllowed: Set<String>) {
        var systemParts: [String] = []
        var promptLines: [String] = []

        let toolsAllowed = Set(request.tools.map(\.name))
        let toolInstructions = makeToolInstructions(tools: request.tools)

        for message in request.messages {
            guard message.op == nil else { continue }

            switch message.role {
            case .system:
                systemParts.append(message.content)

            case .user:
                promptLines.append("User:\n\(message.content)")

            case .assistant:
                var assistantBlock = message.content
                if message.toolCalls.isEmpty == false {
                    let toolCallsText = message.toolCalls.map(renderToolCallMarkup(from:)).joined(separator: "\n")
                    if assistantBlock.isEmpty {
                        assistantBlock = toolCallsText
                    } else {
                        assistantBlock += "\n" + toolCallsText
                    }
                }
                promptLines.append("Assistant:\n\(assistantBlock)")

            case .tool:
                let toolName = message.name ?? "tool"
                let callID = message.toolCallID ?? "unknown"
                promptLines.append("Tool(\(toolName)) [id: \(callID)]:\n\(message.content)")
            }
        }

        var instructionsParts: [String] = []
        if systemParts.isEmpty == false {
            instructionsParts.append(systemParts.joined(separator: "\n\n"))
        }
        if let toolInstructions {
            instructionsParts.append(toolInstructions)
        }
        if let additional = configuration.additionalInstructions,
           additional.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        {
            instructionsParts.append(additional)
        }

        let instructions = instructionsParts.isEmpty ? nil : instructionsParts.joined(separator: "\n\n")
        let prompt = promptLines.joined(separator: "\n\n")
        return (instructions: instructions, prompt: prompt, toolsAllowed: toolsAllowed)
    }

    func makeToolInstructions(tools: [HiveToolDefinition]) -> String? {
        guard tools.isEmpty == false else { return nil }

        switch configuration.toolInstructionVerbosity {
        case .compact:
            let toolList = tools
                .sorted { $0.name.utf8.lexicographicallyPrecedes($1.name.utf8) }
                .map { tool in
                    let argsSummary = compactArgumentSummary(from: tool.parametersJSONSchema)
                    if argsSummary.isEmpty {
                        return "- \(tool.name)"
                    }
                    return "- \(tool.name)\n  args: \(argsSummary)"
                }
                .joined(separator: "\n")

            return """
            Tool calling:
            - Emit tool calls as JSON wrapped in tags:
              \(Self.toolCallOpenTag){"name":"tool_name","arguments":{...}}\(Self.toolCallCloseTag)
            - Emit one block per call.
            - If you emit tool calls, do not emit other assistant text.

            Available tools:
            \(toolList)
            """
        case .verbose:
            let toolList = tools
                .sorted { $0.name.utf8.lexicographicallyPrecedes($1.name.utf8) }
                .map { tool in
                    """
                    - \(tool.name): \(tool.description)
                      parameters_json_schema: \(tool.parametersJSONSchema)
                    """
                }
                .joined(separator: "\n")

            return """
            Tool calling:
            - If you need to call a tool, emit one or more tool call blocks.
            - A tool call block MUST be valid JSON wrapped with tags, with no surrounding text:
              \(Self.toolCallOpenTag){"name":"tool_name","arguments":{...}}\(Self.toolCallCloseTag)
            - If you emit any tool call blocks, do NOT include other assistant text outside tool calls.

            Available tools:
            \(toolList)
            """
        }
    }

    private func compactArgumentSummary(from schemaJSON: String) -> String {
        guard let data = schemaJSON.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return ""
        }

        let properties = (object["properties"] as? [String: Any])?
            .keys
            .sorted { $0.utf8.lexicographicallyPrecedes($1.utf8) } ?? []
        let requiredKeys = Set((object["required"] as? [String] ?? []).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) })

        guard properties.isEmpty == false else { return "(none)" }

        let maxKeys = 8
        let visibleKeys = properties.prefix(maxKeys).map { key in
            requiredKeys.contains(key) ? "\(key)*" : key
        }

        var summary = visibleKeys.joined(separator: ", ")
        if properties.count > maxKeys {
            summary += ", +\(properties.count - maxKeys) more"
        }
        return summary
    }

    private func renderToolCallMarkup(from call: HiveToolCall) -> String {
        "\(Self.toolCallOpenTag){\"id\":\"\(jsonEscaped(call.id))\",\"name\":\"\(jsonEscaped(call.name))\",\"arguments\":\(call.argumentsJSON)}\(Self.toolCallCloseTag)"
    }

    private func jsonEscaped(_ string: String) -> String {
        // Minimal JSON string escaping for embedding IDs/names in markup JSON.
        var escaped = ""
        escaped.reserveCapacity(string.count)
        for scalar in string.unicodeScalars {
            switch scalar {
            case "\"":
                escaped.append("\\\"")
            case "\\":
                escaped.append("\\\\")
            case "\n":
                escaped.append("\\n")
            case "\r":
                escaped.append("\\r")
            case "\t":
                escaped.append("\\t")
            default:
                escaped.unicodeScalars.append(scalar)
            }
        }
        return escaped
    }

    private struct ParsedAssistantOutput: Sendable {
        let visibleText: String
        let toolCalls: [HiveToolCall]
    }

    private func parseFinalAssistantOutput(
        raw: String,
        toolsAllowed: Set<String>
    ) throws -> ParsedAssistantOutput {
        let parsed = parseToolCallBlocks(raw: raw, requireClosedTags: true)

        var toolCalls: [HiveToolCall] = []
        toolCalls.reserveCapacity(parsed.blocks.count)

        for (index, innerJSON) in parsed.blocks.enumerated() {
            let call = try parseToolCallJSON(
                innerJSON,
                index: index,
                toolsAllowed: toolsAllowed
            )
            toolCalls.append(call)
        }

        let visibleText = parsed.visible.trimmingCharacters(in: .whitespacesAndNewlines)
        return ParsedAssistantOutput(visibleText: visibleText, toolCalls: toolCalls)
    }

    private struct ToolCallBlockParseResult: Sendable {
        let visible: String
        let blocks: [String]
    }

    private func parseToolCallBlocks(
        raw: String,
        requireClosedTags: Bool
    ) -> ToolCallBlockParseResult {
        var blocks: [String] = []
        var visibleParts: [String] = []
        visibleParts.reserveCapacity(8)

        var searchStart = raw.startIndex
        while let open = raw.range(of: Self.toolCallOpenTag, range: searchStart ..< raw.endIndex) {
            visibleParts.append(String(raw[searchStart ..< open.lowerBound]))
            let afterOpen = open.upperBound

            guard let close = raw.range(of: Self.toolCallCloseTag, range: afterOpen ..< raw.endIndex) else {
                // In streaming, an open tag may exist without the closing tag yet.
                // For sanitization, hide the trailing partial tool call. For final parsing, treat as invalid.
                if requireClosedTags {
                    // Let the caller throw a deterministic error.
                    return ToolCallBlockParseResult(visible: raw, blocks: ["__UNTERMINATED__"])
                } else {
                    return ToolCallBlockParseResult(visible: visibleParts.joined(), blocks: blocks)
                }
            }

            blocks.append(String(raw[afterOpen ..< close.lowerBound]))
            searchStart = close.upperBound
        }

        visibleParts.append(String(raw[searchStart ..< raw.endIndex]))
        return ToolCallBlockParseResult(visible: visibleParts.joined(), blocks: blocks)
    }

    private func sanitizedVisibleTextForStreaming(raw: String) -> String {
        parseToolCallBlocks(raw: raw, requireClosedTags: false).visible
    }

    private func parseToolCallJSON(
        _ innerJSON: String,
        index: Int,
        toolsAllowed: Set<String>
    ) throws -> HiveToolCall {
        if innerJSON == "__UNTERMINATED__" {
            throw ColonyFoundationModelsClientError.invalidToolCallFormat("Unterminated \(Self.toolCallOpenTag) block.")
        }

        let trimmed = innerJSON.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = trimmed.data(using: .utf8) else {
            throw ColonyFoundationModelsClientError.invalidToolCallFormat("Tool call JSON is not valid UTF-8.")
        }

        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: data, options: [])
        } catch {
            throw ColonyFoundationModelsClientError.invalidToolCallFormat("Failed to decode JSON: \(error.localizedDescription)")
        }

        guard let dict = object as? [String: Any] else {
            throw ColonyFoundationModelsClientError.invalidToolCallFormat("Expected a JSON object.")
        }

        guard let name = (dict["name"] as? String) ?? (dict["tool"] as? String) else {
            throw ColonyFoundationModelsClientError.invalidToolCallFormat("Missing \"name\".")
        }

        if toolsAllowed.isEmpty == false, toolsAllowed.contains(name) == false {
            throw ColonyFoundationModelsClientError.invalidToolCallFormat("Unknown tool name: \(name)")
        }

        let id = (dict["id"] as? String) ?? (dict["tool_call_id"] as? String)

        let argumentsValue: Any = dict["arguments"] ?? dict["args"] ?? [:]
        let argumentsJSON: String

        if let argumentsString = argumentsValue as? String {
            argumentsJSON = argumentsString
        } else {
            do {
                let argumentsData = try JSONSerialization.data(
                    withJSONObject: argumentsValue,
                    options: [.sortedKeys]
                )
                argumentsJSON = String(decoding: argumentsData, as: UTF8.self)
            } catch {
                throw ColonyFoundationModelsClientError.invalidToolCallFormat(
                    "Failed to encode tool arguments JSON: \(error.localizedDescription)"
                )
            }
        }

        return HiveToolCall(
            id: id ?? toolCallID(name: name, argumentsJSON: argumentsJSON, index: index),
            name: name,
            argumentsJSON: argumentsJSON
        )
    }

    private func delta(previous: String, current: String) -> String {
        if current.hasPrefix(previous) {
            return String(current.dropFirst(previous.count))
        }
        if previous.hasPrefix(current) {
            return current
        }
        return current
    }

    #if canImport(FoundationModels)
    @available(iOS 26.0, macOS 26.0, visionOS 26.0, *)
    private func streamAvailable(_ request: HiveChatRequest) -> AsyncThrowingStream<HiveChatStreamChunk, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    guard Self.isAvailable else {
                        throw ColonyFoundationModelsClientError.foundationModelsUnavailable
                    }

                    let (instructions, prompt, toolsAllowed) = makePrompt(from: request)
                    let session = makeSession(instructions: instructions)
                    if configuration.prewarmSession {
                        session.prewarm(promptPrefix: nil)
                    }

                    let options = GenerationOptions()
                    let stream = session.streamResponse(to: prompt, options: options)

                    var previousVisible = ""
                    var lastRaw = ""

                    for try await snapshot in stream {
                        if Task.isCancelled {
                            continuation.finish()
                            return
                        }

                        var raw = snapshot.content
                        if raw == "null", lastRaw.isEmpty {
                            raw = ""
                        }
                        lastRaw = raw

                        let currentVisible = sanitizedVisibleTextForStreaming(raw: raw)
                        let chunk = delta(previous: previousVisible, current: currentVisible)
                        previousVisible = currentVisible

                        if chunk.isEmpty == false {
                            continuation.yield(.token(chunk))
                        }
                    }

                    let response = try makeResponse(
                        rawModelText: lastRaw,
                        toolsAllowed: toolsAllowed
                    )
                    continuation.yield(.final(response))
                    continuation.finish()
                } catch let error as ColonyFoundationModelsClientError {
                    continuation.finish(throwing: error)
                } catch {
                    continuation.finish(throwing: ColonyFoundationModelsClientError.generationFailed(error.localizedDescription))
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    @available(iOS 26.0, macOS 26.0, visionOS 26.0, *)
    private func makeSession(instructions: String?) -> LanguageModelSession {
        if let instructions, instructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            return LanguageModelSession(model: .default, tools: [], instructions: { instructions })
        }
        return LanguageModelSession(model: .default, tools: [])
    }
    #endif
}
