import Foundation
import Colony

struct ResearchAssistantApp: Sendable {
    let options: ResearchAssistantOptions
    let modelResolver: ResearchAssistantModelResolver

    init(
        options: ResearchAssistantOptions,
        modelResolver: ResearchAssistantModelResolver = ResearchAssistantModelResolver()
    ) {
        self.options = options
        self.modelResolver = modelResolver
    }

    func run() async throws {
        let resolved = try modelResolver.resolve(mode: options.modelMode)
        let rootURL = URL(fileURLWithPath: options.root, isDirectory: true)
        let filesystem = ColonyDiskFileSystemBackend(root: rootURL)
        let factory = ColonyAgentFactory()

        let runtime = try factory.makeRuntime(
            profile: options.profile == .cloud ? .cloud : .onDevice4k,
            modelName: "colony-research-assistant",
            model: resolved.client,
            filesystem: filesystem
        )

        print("Colony Research Assistant (\(resolved.selection))")
        print("Type /exit to quit.")

        while let line = readLine() {
            let input = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if input.isEmpty {
                continue
            }
            if input == "/exit" || input == "/quit" {
                break
            }

            let handle = await runtime.sendUserMessage(input)
            let outcome = try await handle.outcome.value
            if case let .finished(output, _) = outcome,
               case let .fullStore(store) = output,
               let answer = try store.get(ColonySchema.Channels.finalAnswer)
            {
                print(answer)
            } else {
                print("Run did not complete with a final answer.")
            }
        }
    }
}
