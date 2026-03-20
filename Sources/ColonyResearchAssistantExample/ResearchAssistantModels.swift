import Colony
import ColonyCore
import Foundation

enum ResearchAssistantModelSelection: String, Sendable, Equatable {
    case foundation
    case mock
}

enum ResearchAssistantModelSelectionError: Error, Sendable, Equatable, CustomStringConvertible {
    case foundationModeRequiresAvailableModel

    var description: String {
        switch self {
        case .foundationModeRequiresAvailableModel:
            return "Foundation model mode was requested, but on-device Foundation Models are unavailable. Use --model-mode auto or --model-mode mock."
        }
    }
}

struct ResearchAssistantResolvedModel: Sendable {
    var selection: ResearchAssistantModelSelection
    var model: ColonyModel
}

struct ResearchAssistantModelResolver: Sendable {
    var isFoundationAvailable: @Sendable () -> Bool

    init(isFoundationAvailable: @escaping @Sendable () -> Bool = { ColonyFoundationModelsClient.isAvailable }) {
        self.isFoundationAvailable = isFoundationAvailable
    }

    func resolve(mode: ResearchAssistantModelMode) throws -> ResearchAssistantResolvedModel {
        switch mode {
        case .auto:
            if isFoundationAvailable() {
                return ResearchAssistantResolvedModel(
                    selection: .foundation,
                    model: .foundationModels()
                )
            }
            return ResearchAssistantResolvedModel(
                selection: .mock,
                model: ColonyModel(client: MockResearchModel())
            )
        case .foundation:
            if isFoundationAvailable() {
                return ResearchAssistantResolvedModel(
                    selection: .foundation,
                    model: .foundationModels()
                )
            }
            throw ResearchAssistantModelSelectionError.foundationModeRequiresAvailableModel
        case .mock:
            return ResearchAssistantResolvedModel(
                selection: .mock,
                model: ColonyModel(client: MockResearchModel())
            )
        }
    }
}

final class MockResearchModel: ColonyModelClient, @unchecked Sendable {
    private let lock = NSLock()
    private var toolCallCounter: Int = 0

    func complete(_ request: ColonyModelRequest) async throws -> ColonyModelResponse {
        try await streamFinal(request)
    }

    func stream(_ request: ColonyModelRequest) -> AsyncThrowingStream<ColonyModelStreamChunk, Error> {
        let response = makeResponse(for: request)
        return AsyncThrowingStream { continuation in
            continuation.yield(.final(response))
            continuation.finish()
        }
    }

    private func makeResponse(for request: ColonyModelRequest) -> ColonyModelResponse {
        if isSubagentRequest(request) {
            return ColonyModelResponse(
                message: ColonyChatMessage(
                    id: UUID().uuidString,
                    role: .assistant,
                    content: makeSubagentFindings(for: latestUserPrompt(in: request)),
                    toolCalls: []
                )
            )
        }

        if request.messages.contains(where: { message in
            message.role == .system && message.content.contains("Tool execution rejected by user.")
        }) {
            return ColonyModelResponse(
                message: ColonyChatMessage(
                    id: UUID().uuidString,
                    role: .assistant,
                    content: "MOCK_RESEARCH_SUMMARY\n\nTool execution was rejected by the user; no additional evidence was collected.",
                    toolCalls: []
                )
            )
        }

        guard let latest = latestNonSystemMessage(in: request) else {
            return ColonyModelResponse(
                message: ColonyChatMessage(
                    id: UUID().uuidString,
                    role: .assistant,
                    content: "MOCK_RESEARCH_SUMMARY\n\nNo user input was provided.",
                    toolCalls: []
                )
            )
        }

        switch latest.role {
        case .user:
            let delegatedPrompt = """
Research request:
\(latest.content)

Return:
1. Key findings tied to repository files.
2. Citations using /path:line format.
3. Open risks or unknowns.
"""

            let call = ColonyToolCall(
                id: nextToolCallID(),
                name: ColonyToolName(rawValue: ColonyBuiltInTool.task.rawValue),
                argumentsJSON: #"{"prompt":"\#(jsonEscaped(delegatedPrompt))","subagent_type":"general-purpose"}"#
            )

            return ColonyModelResponse(
                message: ColonyChatMessage(
                    id: UUID().uuidString,
                    role: .assistant,
                    content: "Delegating research to a focused subagent.",
                    toolCalls: [call]
                )
            )

        case .tool:
            let synthesized = latest.content.trimmingCharacters(in: .whitespacesAndNewlines)
            let body = synthesized.isEmpty ? "(subagent returned no content)" : synthesized
            return ColonyModelResponse(
                message: ColonyChatMessage(
                    id: UUID().uuidString,
                    role: .assistant,
                    content: "MOCK_RESEARCH_SUMMARY\n\n\(body)",
                    toolCalls: []
                )
            )

        case .assistant, .system:
            return ColonyModelResponse(
                message: ColonyChatMessage(
                    id: UUID().uuidString,
                    role: .assistant,
                    content: "MOCK_RESEARCH_SUMMARY\n\nWaiting for user research prompt.",
                    toolCalls: []
                )
            )
        }
    }

    private func nextToolCallID() -> String {
        lock.lock()
        defer { lock.unlock() }
        toolCallCounter += 1
        return "mock-task-\(toolCallCounter)"
    }

    private func latestNonSystemMessage(in request: ColonyModelRequest) -> ColonyChatMessage? {
        request.messages.last(where: { $0.role != .system && $0.operation == nil })
    }

    private func latestUserPrompt(in request: ColonyModelRequest) -> String {
        request.messages.last(where: { $0.role == .user && $0.operation == nil })?.content ?? "unspecified request"
    }

    private func isSubagentRequest(_ request: ColonyModelRequest) -> Bool {
        let hasSubagentMarker = request.messages.contains(where: { message in
            message.role == .system && message.content.contains("Subagent mode")
        })
        let hasTaskTool = request.tools.contains(where: { $0.name.rawValue == ColonyBuiltInTool.task.rawValue })
        return hasSubagentMarker || hasTaskTool == false
    }

    private func makeSubagentFindings(for prompt: String) -> String {
        """
MOCK_SUBAGENT_FINDINGS
- Investigated: \(prompt)
- Evidence: /README.md:1
- Recommendation: use glob/grep/read_file on relevant modules before editing.
"""
    }

    private func jsonEscaped(_ string: String) -> String {
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
}
