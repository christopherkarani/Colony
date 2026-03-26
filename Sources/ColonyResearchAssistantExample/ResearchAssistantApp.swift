import Foundation
import Colony

enum ResearchAssistantAppError: Error, Sendable, Equatable, CustomStringConvertible {
    case rootPathNotDirectory(String)

    var description: String {
        switch self {
        case .rootPathNotDirectory(let path):
            return "The provided root path is not a readable directory: \(path)"
        }
    }
}

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

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: options.root, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw ResearchAssistantAppError.rootPathNotDirectory(options.root)
        }

        let rootURL = URL(fileURLWithPath: options.root, isDirectory: true)
        let filesystem = ColonyDiskFileSystemBackend(root: rootURL)
        let runtime = try ColonyAgentFactory()
            .profile(options.profile.colonyProfile)
            .model(name: "colony-research-assistant")
            .model(resolved.client)
            .filesystem(filesystem)
            .configure { config in
                config.capabilities = [.planning, .filesystem, .subagents]
                config.toolApprovalPolicy = .allowList([
                    "ls",
                    "read_file",
                    "glob",
                    "grep",
                    "read_todos",
                    "write_todos",
                    ColonyBuiltInToolDefinitions.taskName,
                ])
                config.summarizationPolicy = nil
                config.toolResultEvictionTokenLimit = nil
                config.additionalSystemPrompt = Self.researchAssistantSystemPrompt
            }
            .build()

        print("Colony Research Assistant (\(resolved.selection.rawValue))")
        print("Root: \(options.root)")
        print("Profile: \(options.profile.rawValue)")
        print("Type /exit or /quit to quit.")

        while true {
            print("research> ", terminator: "")
            fflush(stdout)
            guard let line = readLine() else {
                print("")
                break
            }

            let input = line.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            if input.isEmpty {
                continue
            }
            let lowercased = input.lowercased()
            if lowercased == "/exit" || lowercased == "/quit" {
                break
            }

            do {
                let handle = await runtime.runControl.start(ColonyRunStartRequest(input: input))
                let answer = try await resolveOutcomeLoop(handle: handle, runtime: runtime)
                print(answer)
            } catch let error as OnDeviceModelError {
                print("Model error: \(error)")
                print("Hint: try running with --model-mode mock to use the built-in mock model.")
            } catch {
                print("Error: \(error)")
            }
        }
    }

    private func resolveOutcomeLoop(
        handle: ColonyRun.Handle,
        runtime: ColonyRuntime
    ) async throws -> String {
        var currentHandle = handle

        while true {
            let outcome = try await currentHandle.outcome.value
            switch outcome {
            case let .finished(output, _):
                return renderFinalAnswer(from: output)

            case let .cancelled(output, _):
                let answer = renderFinalAnswer(from: output)
                return "Run was cancelled.\n\(answer)"

            case let .outOfSteps(maxSteps, output, _):
                let answer = renderFinalAnswer(from: output)
                return "Run reached max steps (\(maxSteps)).\n\(answer)"

            case let .interrupted(interruption):
                switch interruption.payload {
                case .toolApprovalRequired(let toolCalls):
                    let decision = promptForApproval(toolCalls: toolCalls)
                    currentHandle = await runtime.runControl.resume(
                        ColonyRunResumeRequest(
                            interruptID: interruption.interruptID,
                            decision: decision
                        )
                    )
                }
            }
        }
    }

    private func renderFinalAnswer(from output: ColonyRun.Output) -> String {
        switch output {
        case .fullStore(let store):
            return (try? store.get(ColonySchema.Channels.finalAnswer)) ?? "(no final answer)"
        case .channels(let values):
            let finalAnswer = values.first(where: { $0.channelID == ColonyChannelID(hiveChannelID: ColonySchema.Channels.finalAnswer.id) })?.value as? String
            return finalAnswer ?? "(no final answer)"
        }
    }

    private func promptForApproval(toolCalls: [ColonyToolCall]) -> ColonyToolApprovalDecision {
        let names = toolCalls.map { $0.name }.joined(separator: ", ")
        print("Tool approval required for: \(names)")
        print("Approve? [y/N/c(ancel)]: ", terminator: "")
        fflush(stdout)
        let response = readLine()?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).lowercased() ?? ""
        if response == "y" || response == "yes" {
            return .approved
        }
        if response == "c" || response == "cancel" || response == "cancelled" {
            return .rejected
        }
        return .rejected
    }

    private static let researchAssistantSystemPrompt: String = """
Research assistant mode:
- Start by writing and maintaining a concise TODO plan.
- Gather evidence with filesystem tools (`glob`, `grep`, `read_file`) before concluding.
- Delegate deeper focused analysis with `task` and `subagent_type: "general-purpose"` when useful.
- Cite concrete evidence with /path:line references in your findings.
- Avoid write/edit/execute operations unless the user explicitly requests mutation or command execution.
"""
}
