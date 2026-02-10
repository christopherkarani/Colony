#!/usr/bin/env swift
// Diagnostic: probe Foundation Models availability and generation

#if canImport(FoundationModels)
import FoundationModels
import Foundation

print("FoundationModels framework: imported")

if #available(macOS 26.0, *) {
    let model = SystemLanguageModel.default
    let availability = model.availability
    print("SystemLanguageModel.default.availability: \(availability)")

    switch availability {
    case .available:
        print("  -> .available (model is ready)")
    case .unavailable:
        print("  -> .unavailable (model is not available)")
    default:
        print("  -> other state: \(availability)")
    }

    // Try an actual generation
    print("\nAttempting a test generation...")
    let session = LanguageModelSession(model: .default, tools: [])
    do {
        let response = try await session.respond(to: "Say hello in one word.")
        print("Generation succeeded: \(response.content)")
    } catch {
        print("Generation FAILED:")
        print("  Error type: \(type(of: error))")
        print("  Error: \(error)")
        print("  Localized: \(error.localizedDescription)")
        if let nsError = error as NSError? {
            print("  NSError domain: \(nsError.domain)")
            print("  NSError code: \(nsError.code)")
            print("  NSError userInfo: \(nsError.userInfo)")
        }
    }
} else {
    print("macOS 26.0+ not available")
}
#else
print("FoundationModels framework: NOT available (canImport failed)")
#endif
