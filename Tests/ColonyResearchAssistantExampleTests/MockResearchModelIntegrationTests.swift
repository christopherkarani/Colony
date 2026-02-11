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
    let runtime = try factory.makeRuntime(
        profile: .onDevice4k,
        modelName: "test-model",
        model: AnyHiveModelClient(MockResearchModel()),
        filesystem: fs,
        configure: { config in
            config.capabilities = [.planning, .filesystem, .subagents]
            config.toolApprovalPolicy = .never
            config.mandatoryApprovalRiskLevels = []
            config.summarizationPolicy = nil
            config.toolResultEvictionTokenLimit = nil
        }
    )

    let handle = await runtime.runControl.start(.init(input: "Research this repository architecture."))
    let outcome = try await handle.outcome.value

    guard case let .finished(output, _) = outcome, case let .fullStore(store) = output else {
        #expect(Bool(false))
        return
    }

    let finalAnswer = try store.get(ColonySchema.Channels.finalAnswer) ?? ""
    #expect(finalAnswer.isEmpty == false)
    #expect(finalAnswer.contains("MOCK_RESEARCH_SUMMARY"))
    #expect(finalAnswer.contains("MOCK_SUBAGENT_FINDINGS"))
    #expect(finalAnswer.contains("Subagent registry not configured.") == false)

    let messages = try store.get(ColonySchema.Channels.messages)
    guard let assistantTaskMessage = messages.first(where: { message in
        message.role == .assistant && message.toolCalls.contains(where: { $0.name == ColonyBuiltInToolDefinitions.taskName })
    }) else {
        #expect(Bool(false))
        return
    }

    guard let taskCallID = assistantTaskMessage.toolCalls.first(where: { $0.name == ColonyBuiltInToolDefinitions.taskName })?.id else {
        #expect(Bool(false))
        return
    }

    let matchingToolMessage = messages.first(where: { message in
        message.role == .tool && message.toolCallID == taskCallID
    })
    #expect(matchingToolMessage != nil)
}
