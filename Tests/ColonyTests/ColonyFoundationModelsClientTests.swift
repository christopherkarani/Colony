import Testing
@testable import Colony

private let sampleTools: [HiveToolDefinition] = [
    HiveToolDefinition(
        name: "tool_alpha",
        description: "Alpha tool description.",
        parametersJSONSchema: #"{"type":"object","properties":{"value":{"type":"string"}},"required":["value"]}"#
    ),
    HiveToolDefinition(
        name: "tool_beta",
        description: "Beta tool description.",
        parametersJSONSchema: #"{"type":"object","properties":{"count":{"type":"integer"}}}"#
    ),
]

@Test("FoundationModels configuration defaults to compact tool instructions")
func foundationModelsConfig_defaultsToCompactToolInstructions() {
    let config = ColonyFoundationModelsClient.Configuration()
    #expect(config.toolInstructionVerbosity == .compact)
}

@Test("FoundationModels compact tool instructions omit per-tool schemas")
func foundationModelsClient_compactToolInstructions_omitSchemas() {
    let compactClient = ColonyFoundationModelsClient(
        configuration: .init(toolInstructionVerbosity: .compact)
    )
    let verboseClient = ColonyFoundationModelsClient(
        configuration: .init(toolInstructionVerbosity: .verbose)
    )

    let compact = compactClient.makeToolInstructions(tools: sampleTools)
    let verbose = verboseClient.makeToolInstructions(tools: sampleTools)

    #expect(compact != nil)
    #expect(verbose != nil)
    #expect(compact?.contains("parameters_json_schema:") == false)
    #expect(verbose?.contains("parameters_json_schema:") == true)
    #expect(compact?.contains("- tool_alpha") == true)
    #expect(compact?.contains("- tool_beta") == true)
    #expect(compact?.contains("args: value*") == true)
    #expect(compact?.contains("args: count") == true)
    #expect((compact?.count ?? 0) < (verbose?.count ?? 0))
}

@Test("FoundationModels parser rejects unterminated tool call blocks")
func foundationModelsParser_rejectsUnterminatedToolCallBlock() {
    let client = ColonyFoundationModelsClient()
    let raw = #"assistant reply <tool_call>{"name":"tool_alpha","arguments":{"value":"x"}}"#

    do {
        _ = try client.parseAssistantOutputForTesting(raw: raw, toolsAllowed: ["tool_alpha"])
        #expect(Bool(false))
    } catch let error as ColonyFoundationModelsClientError {
        switch error {
        case .invalidToolCallFormat(let message):
            #expect(message.contains("Unterminated") == true)
        default:
            #expect(Bool(false))
        }
    } catch {
        #expect(Bool(false))
    }
}

@Test("FoundationModels parser rejects malformed tool call JSON")
func foundationModelsParser_rejectsMalformedToolCallJSON() {
    let client = ColonyFoundationModelsClient()
    let raw = #"assistant <tool_call>{"name":"tool_alpha","arguments":{"value":"x"}</tool_call>"#

    do {
        _ = try client.parseAssistantOutputForTesting(raw: raw, toolsAllowed: ["tool_alpha"])
        #expect(Bool(false))
    } catch let error as ColonyFoundationModelsClientError {
        switch error {
        case .invalidToolCallFormat(let message):
            #expect(message.contains("Failed to decode JSON") == true)
        default:
            #expect(Bool(false))
        }
    } catch {
        #expect(Bool(false))
    }
}

@Test("FoundationModels parser rejects unknown tool names")
func foundationModelsParser_rejectsUnknownToolName() {
    let client = ColonyFoundationModelsClient()
    let raw = #"assistant <tool_call>{"id":"call-1","name":"tool_gamma","arguments":{"value":"x"}}</tool_call>"#

    do {
        _ = try client.parseAssistantOutputForTesting(raw: raw, toolsAllowed: ["tool_alpha"])
        #expect(Bool(false))
    } catch let error as ColonyFoundationModelsClientError {
        switch error {
        case .invalidToolCallFormat(let message):
            #expect(message.contains("Unknown tool name") == true)
        default:
            #expect(Bool(false))
        }
    } catch {
        #expect(Bool(false))
    }
}

@Test("FoundationModels parser accepts string-valued arguments payloads")
func foundationModelsParser_acceptsStringArgumentsPayload() throws {
    let client = ColonyFoundationModelsClient()
    let raw = #"assistant <tool_call>{"id":"call-1","name":"tool_alpha","arguments":"{\"value\":\"x\"}"}</tool_call>"#

    let parsed = try client.parseAssistantOutputForTesting(raw: raw, toolsAllowed: ["tool_alpha"])
    #expect(parsed.visibleText == "assistant")
    #expect(parsed.toolCalls.count == 1)
    #expect(parsed.toolCalls.first?.id == "call-1")
    #expect(parsed.toolCalls.first?.name == "tool_alpha")
    #expect(parsed.toolCalls.first?.argumentsJSON == #"{"value":"x"}"#)
}
