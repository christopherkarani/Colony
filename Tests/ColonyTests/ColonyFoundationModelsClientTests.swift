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
