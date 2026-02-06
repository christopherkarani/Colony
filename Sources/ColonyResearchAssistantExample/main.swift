import Foundation

@main
struct ColonyResearchAssistantExampleMain {
    static func main() async {
        do {
            let options = try ResearchAssistantOptions.parse(arguments: Array(CommandLine.arguments.dropFirst()))
            let app = ResearchAssistantApp(options: options)
            try await app.run()
        } catch {
            fputs("Error: \(error)\n", stderr)
            Foundation.exit(1)
        }
    }
}
