import Foundation
import ColonyCore

package struct ColonyDefaultSubagentRegistry: ColonySubagentRegistry {
    private enum RegistryError: Error, Sendable, Equatable {
        case unsupportedSubagentType(String)
        case runInterrupted
        case runCancelled
        case runOutOfSteps(maxSteps: Int)
        case missingFullStoreOutput
    }

    private let profile: ColonyProfile
    private let modelName: String
    private let model: SwarmAnyModelClient
    private let clock: any SwarmClock
    private let logger: any SwarmLogger
    private let filesystem: (any ColonyFileSystemBackend)?

    public init(
        modelName: String,
        model: SwarmAnyModelClient,
        clock: any SwarmClock,
        logger: any SwarmLogger,
        filesystem: (any ColonyFileSystemBackend)? = nil
    ) {
        self.init(
            profile: .onDevice4k,
            modelName: modelName,
            model: model,
            clock: clock,
            logger: logger,
            filesystem: filesystem
        )
    }

    public init(
        profile: ColonyProfile,
        modelName: String,
        model: SwarmAnyModelClient,
        clock: any SwarmClock,
        logger: any SwarmLogger,
        filesystem: (any ColonyFileSystemBackend)? = nil
    ) {
        self.profile = profile
        self.modelName = modelName
        self.model = model
        self.clock = clock
        self.logger = logger
        self.filesystem = filesystem
    }

    public func listSubagents() -> [ColonySubagentDescriptor] {
        [
            ColonySubagentDescriptor(
                name: "general-purpose",
                description: "General-purpose helper."
            ),
            ColonySubagentDescriptor(
                name: "compactor",
                description: "Compacts offloaded history into a dense summary + next actions."
            ),
        ]
    }

    public func run(_ request: ColonySubagentRequest) async throws -> ColonySubagentResult {
        let type = request.subagentType
        let isGeneral = type == .general
        let isCompactor = type == .compactor
        guard isGeneral || isCompactor else {
            throw RegistryError.unsupportedSubagentType(request.subagentType.rawValue)
        }

        let delegatedPrompt = try await renderDelegatedPrompt(request)

        var configuration = ColonyAgentFactory.configuration(profile: profile, modelName: modelName)
        configuration.capabilities = subagentCapabilities(
            base: configuration.capabilities,
            filesystem: filesystem
        )
        configuration.toolApprovalPolicy = .never

        if isCompactor {
            configuration.additionalSystemPrompt = mergeAdditionalSystemPrompt(
                base: configuration.additionalSystemPrompt,
                extra: """
                Compactor mode:
                - Prefer Scratchbook for summary + next actions.
                - Offloaded history file is the source of truth.
                - No `task` tool; recursive subagents disabled.
                """
            )
        }
        let finalizedConfiguration = configuration

        let runtime = try ColonyBuilder()
            .profile(profile)
            .threadID(ColonyThreadID("subagent:\(UUID().uuidString)"))
            .model(name: modelName)
            .model(model)
            .filesystem(filesystem)
            .clock(clock)
            .logger(logger)
            .configure { config in
                config = finalizedConfiguration
            }
            .configureRunOptions { options in
                options.checkpointPolicy = .disabled
            }
            .build()

        let handle = await runtime.sendUserMessage(delegatedPrompt)

        let outcome = try await handle.outcome.value
        let store: ColonyRun.Store
        switch outcome {
        case .finished(let output, _), .cancelled(let output, _), .outOfSteps(_, let output, _):
            guard case let .fullStore(fullStore) = output else {
                throw RegistryError.missingFullStoreOutput
            }
            store = fullStore

        case .interrupted:
            throw RegistryError.runInterrupted
        }

        let messages = try store.get(ColonySchema.Channels.messages)
        let toolMessages = messages.filter { $0.role == .tool }
        if let toolError = toolMessages.first(where: { $0.content.hasPrefix("Error:") }) {
            return ColonySubagentResult(content: toolError.content)
        }

        let finalAnswer = try store.get(ColonySchema.Channels.finalAnswer)
        return ColonySubagentResult(content: finalAnswer ?? "")
    }

    private func renderDelegatedPrompt(_ request: ColonySubagentRequest) async throws -> String {
        var sections: [String] = [request.prompt]

        if let context = request.context {
            sections.append(renderStructuredContext(context))
        }

        if request.fileReferences.isEmpty == false {
            sections.append(try await renderFileContextSnippets(request.fileReferences))
        }

        return sections.joined(separator: "\n\n")
    }

    private func renderStructuredContext(_ context: ColonySubagentContext) -> String {
        var lines: [String] = ["Structured context:"]

        if let objective = context.objective, objective.isEmpty == false {
            lines.append("objective: \(objective)")
        }

        lines.append("constraints:")
        if context.constraints.isEmpty {
            lines.append("(none)")
        } else {
            lines.append(contentsOf: context.constraints.map { "- \($0)" })
        }

        lines.append("acceptance_criteria:")
        if context.acceptanceCriteria.isEmpty {
            lines.append("(none)")
        } else {
            lines.append(contentsOf: context.acceptanceCriteria.map { "- \($0)" })
        }

        lines.append("notes:")
        if context.notes.isEmpty {
            lines.append("(none)")
        } else {
            lines.append(contentsOf: context.notes.map { "- \($0)" })
        }

        return lines.joined(separator: "\n")
    }

    private func renderFileContextSnippets(
        _ references: [ColonySubagentFileReference]
    ) async throws -> String {
        var blocks: [String] = ["File context snippets:"]

        for ref in references {
            let offset = max(0, ref.offset ?? 0)
            let limit = max(1, ref.limit ?? 100)

            var lines: [String] = [
                "path: \(ref.path.rawValue)",
                "requested_offset: \(ref.offset ?? 0)",
                "requested_limit: \(ref.limit ?? 100)",
            ]

            guard let filesystem else {
                lines.append("excerpt: (filesystem not configured)")
                blocks.append(lines.joined(separator: "\n"))
                continue
            }

            do {
                let content = try await filesystem.read(at: ref.path)
                lines.append("excerpt:\n" + formatWithLineNumbers(text: content, offset: offset, limit: limit))
            } catch {
                lines.append("excerpt_error: \(error)")
            }

            blocks.append(lines.joined(separator: "\n"))
        }

        return blocks.joined(separator: "\n\n")
    }

    private func formatWithLineNumbers(text: String, offset: Int, limit: Int) -> String {
        let allLines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let slice = allLines.dropFirst(offset).prefix(limit)
        var result: [String] = []
        result.reserveCapacity(slice.count)
        for (index, line) in slice.enumerated() {
            let lineNumber = offset + index + 1
            result.append(String(format: "%6d\t%@", lineNumber, line))
        }
        return result.joined(separator: "\n")
    }

    private func subagentCapabilities(
        base: ColonyCapabilities,
        filesystem: (any ColonyFileSystemBackend)?
    ) -> ColonyCapabilities {
        var capabilities: ColonyCapabilities = [.planning]
        if filesystem != nil, base.contains(.filesystem) {
            capabilities.insert(.filesystem)
        }
        if filesystem != nil, base.contains(.scratchbook) {
            capabilities.insert(.scratchbook)
        }
        // Intentionally omit `.subagents` to prevent recursion by default.
        return capabilities
    }

    private func mergeAdditionalSystemPrompt(
        base: String?,
        extra: String
    ) -> String {
        let trimmedExtra = extra.trimmingCharacters(in: .whitespacesAndNewlines)
        if let base, base.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            return base + "\n\n" + trimmedExtra
        }
        return trimmedExtra
    }
}
