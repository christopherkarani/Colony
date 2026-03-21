import Colony
import ColonyCore
import Foundation

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
        let filesystem = ColonyFileSystem.DiskBackend(root: rootURL)

        let runtime = try await Colony.agent(
            model: resolved.model,
            profile: options.profile.colonyProfile,
            capabilities: [.planning, .filesystem, .subagents],
            checkpointing: .inMemory
        ) {
            .filesystem(filesystem)
        } configure: { config in
            config.safety.toolApprovalPolicy = .allowList([
                .ls,
                .readFile,
                .glob,
                .grep,
                .readTodos,
                .writeTodos,
                .task,
            ])
            config.context.summarizationPolicy = nil
            config.context.toolResultEvictionTokenLimit = nil
            config.prompts.additionalSystemPrompt = Self.researchAssistantSystemPrompt
        }

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

            let input = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if input.isEmpty {
                continue
            }
            let lowercased = input.lowercased()
            if lowercased == "/exit" || lowercased == "/quit" {
                break
            }

            do {
                let handle = await runtime.sendUserMessage(input)
                let answer = try await resolveOutcomeLoop(handle: handle, runtime: runtime)
                print(answer)
            } catch let error as ColonyFoundationModelsClientError {
                print("Model error: \(error)")
                print("Hint: try running with --model-mode mock to use the built-in mock model.")
            } catch {
                print("Error: \(error)")
            }
        }
    }

    private func resolveOutcomeLoop(
        handle: ColonyRunHandle,
        runtime: ColonyRuntime
    ) async throws -> String {
        var currentHandle = handle

        while true {
            let outcome = try await currentHandle.outcome.value
            switch outcome {
            case let .finished(transcript, _):
                return renderFinalAnswer(from: transcript)

            case let .cancelled(transcript, _):
                let answer = renderFinalAnswer(from: transcript)
                return "Run was cancelled.\n\(answer)"

            case let .outOfSteps(maxSteps, transcript, _):
                let answer = renderFinalAnswer(from: transcript)
                return "Run reached max steps (\(maxSteps)).\n\(answer)"

            case let .interrupted(interruption):
                let decision = promptForApproval(toolCalls: interruption.toolCalls)
                currentHandle = await runtime.resumeToolApproval(
                    interruptID: interruption.interruptID,
                    decision: decision
                )
            }
        }
    }

    private func renderFinalAnswer(from transcript: ColonyTranscript) -> String {
        transcript.finalAnswer ?? "(no final answer)"
    }

    private func promptForApproval(toolCalls: [ColonyToolCall]) -> ColonyToolApprovalDecision {
        let names = toolCalls.map(\.name.rawValue).joined(separator: ", ")
        print("Tool approval required for: \(names)")
        print("Approve? [y/N/c(ancel)]: ", terminator: "")
        fflush(stdout)
        let response = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        if response == "y" || response == "yes" {
            return .approved
        }
        if response == "c" || response == "cancel" || response == "cancelled" {
            return .cancelled
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
