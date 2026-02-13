import Testing
@testable import ColonyResearchAssistantExample

@Test("auto mode selects mock when Foundation Models are unavailable")
func autoModeFallsBackToMockWhenUnavailable() throws {
    let resolver = ResearchAssistantModelResolver(isFoundationAvailable: { false })
    let resolved = try resolver.resolve(mode: .auto)
    #expect(resolved.selection == .mock)
}

@Test("auto mode selects Foundation Models when available")
func autoModeUsesFoundationWhenAvailable() throws {
    let resolver = ResearchAssistantModelResolver(isFoundationAvailable: { true })
    let resolved = try resolver.resolve(mode: .auto)
    #expect(resolved.selection == .foundation)
}

@Test("foundation mode fails deterministically when Foundation Models are unavailable")
func foundationModeFailsWhenUnavailable() throws {
    let resolver = ResearchAssistantModelResolver(isFoundationAvailable: { false })
    do {
        _ = try resolver.resolve(mode: .foundation)
        #expect(Bool(false))
    } catch let error as ResearchAssistantModelSelectionError {
        #expect(error == .foundationModeRequiresAvailableModel)
    }
}
