import Foundation
import Testing
@testable import ColonyResearchAssistantExample

@Test("Options defaults resolve to auto, on-device, and cwd root")
func optionsDefaults() throws {
    let options = try ResearchAssistantOptions.parse(arguments: [], cwd: "/tmp/colony")
    #expect(options.modelMode == .auto)
    #expect(options.profile == .onDevice)
    #expect(options.root == "/tmp/colony")
}

@Test("Invalid --model-mode fails with usage error")
func invalidModelModeFails() throws {
    do {
        _ = try ResearchAssistantOptions.parse(arguments: ["--model-mode", "bad-mode"], cwd: "/tmp/colony")
        #expect(Bool(false))
    } catch let error as ResearchAssistantOptionsError {
        guard case let .usage(message) = error else {
            #expect(Bool(false))
            return
        }
        #expect(message.contains("--model-mode"))
    }
}

@Test("Invalid --profile fails with usage error")
func invalidProfileFails() throws {
    do {
        _ = try ResearchAssistantOptions.parse(arguments: ["--profile", "unknown"], cwd: "/tmp/colony")
        #expect(Bool(false))
    } catch let error as ResearchAssistantOptionsError {
        guard case let .usage(message) = error else {
            #expect(Bool(false))
            return
        }
        #expect(message.contains("--profile"))
    }
}

@Test("Missing --root value fails with usage error")
func missingRootValueFails() throws {
    do {
        _ = try ResearchAssistantOptions.parse(arguments: ["--root"], cwd: "/tmp/colony")
        #expect(Bool(false))
    } catch let error as ResearchAssistantOptionsError {
        guard case let .usage(message) = error else {
            #expect(Bool(false))
            return
        }
        #expect(message.contains("--root"))
    }
}
