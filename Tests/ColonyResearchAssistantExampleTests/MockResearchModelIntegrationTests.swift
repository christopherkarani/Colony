import ColonyCore
import Testing
import Colony
@testable import ColonyResearchAssistantExample

@Test("Mock research model completes through task-subagent-tool loop with final summary")
func mockResearchModelCompletesTaskLoop() async throws {
    let fs = ColonyInMemoryFileSystemBackend(
        files: [
            try ColonyVirtualPath("/README.md"): "Sample project readme",
        ]
    )

    let factory = ColonyAgentFactory()
    let runtime = try factory.makeRuntime(.init(
        profile: .onDevice4k,
        modelName: "test-model",
        model: ColonyModel(client: MockResearchModel()),
        services: ColonyRuntimeServices(filesystem: fs),
        configure: { config in
            config.model.capabilities = [.planning, .filesystem, .subagents]
            config.safety.toolApprovalPolicy = .never
            config.safety.mandatoryApprovalRiskLevels = []
            config.context.summarizationPolicy = nil
            config.context.toolResultEvictionTokenLimit = nil
        }
    ))

    let handle = await runtime.sendUserMessage("Research this repository architecture.")
    let outcome = try await handle.outcome.value

    guard case let .finished(transcript, _) = outcome else {
        #expect(Bool(false))
        return
    }

    let finalAnswer = transcript.finalAnswer ?? ""
    #expect(finalAnswer.isEmpty == false)
    #expect(finalAnswer.contains("MOCK_RESEARCH_SUMMARY"))
    #expect(finalAnswer.contains("MOCK_SUBAGENT_FINDINGS"))
    #expect(finalAnswer.contains("Subagent registry not configured.") == false)

    let messages = transcript.messages
    guard let assistantTaskMessage = messages.first(where: { message in
        message.role == .assistant && message.toolCalls.contains(where: { $0.name.rawValue == ColonyBuiltInTool.task.rawValue })
    }) else {
        #expect(Bool(false))
        return
    }

    guard let taskCallID = assistantTaskMessage.toolCalls.first(where: { $0.name.rawValue == ColonyBuiltInTool.task.rawValue })?.id else {
        #expect(Bool(false))
        return
    }

    let matchingToolMessage = messages.first(where: { message in
        message.role == .tool && message.toolCallID == taskCallID
    })
    #expect(matchingToolMessage != nil)
}
