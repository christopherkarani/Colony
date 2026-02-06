import Foundation
import Dispatch
import Darwin

enum ResearchAssistantEntrypoint {
    static func run(arguments: [String]) async -> Int32 {
        do {
            let options = try ResearchAssistantOptions.parse(arguments: arguments)
            let app = ResearchAssistantApp(options: options)
            try await app.run()
            return 0
        } catch let error as ResearchAssistantOptionsError {
            fputs("Error: \(error)\n", stderr)
            return 2
        } catch let error as ResearchAssistantModelSelectionError {
            fputs("Error: \(error)\n", stderr)
            return 3
        } catch let error as ResearchAssistantAppError {
            fputs("Error: \(error)\n", stderr)
            return 4
        } catch {
            fputs("Error: \(error)\n", stderr)
            return 1
        }
    }
}

Task {
    let exitCode = await ResearchAssistantEntrypoint.run(arguments: Array(CommandLine.arguments.dropFirst()))
    Darwin.exit(exitCode)
}

dispatchMain()
