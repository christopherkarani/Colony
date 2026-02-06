import CryptoKit
import Foundation
import HiveCore
import ColonyCore

public enum ColonySchema: HiveSchema {
    public typealias Context = ColonyContext
    public typealias Input = String
    public typealias InterruptPayload = ColonyInterruptPayload
    public typealias ResumePayload = ColonyResumePayload

    public enum Channels {
        public static let messages = HiveChannelKey<ColonySchema, [HiveChatMessage]>(HiveChannelID("messages"))
        public static let llmInputMessages = HiveChannelKey<ColonySchema, [HiveChatMessage]?>(HiveChannelID("llmInputMessages"))
        public static let pendingToolCalls = HiveChannelKey<ColonySchema, [HiveToolCall]>(HiveChannelID("pendingToolCalls"))
        public static let finalAnswer = HiveChannelKey<ColonySchema, String?>(HiveChannelID("finalAnswer"))
        public static let todos = HiveChannelKey<ColonySchema, [ColonyTodo]>(HiveChannelID("todos"))

        public static let currentToolCall = HiveChannelKey<ColonySchema, HiveToolCall>(HiveChannelID("currentToolCall"))
    }

    public static let removeAllMessagesID = "__remove_all__"

    public static var channelSpecs: [AnyHiveChannelSpec<ColonySchema>] {
        let messagesCodec = HiveAnyCodec(HiveJSONCodec<[HiveChatMessage]>(id: "colony.messages.v1"))
        let toolCallsCodec = HiveAnyCodec(HiveJSONCodec<[HiveToolCall]>(id: "colony.pending-tool-calls.v1"))
        let currentToolCallCodec = HiveAnyCodec(HiveJSONCodec<HiveToolCall>(id: "colony.current-tool-call.v1"))
        let todosCodec = HiveAnyCodec(HiveJSONCodec<[ColonyTodo]>(id: "colony.todos.v1"))

        return [
            AnyHiveChannelSpec(
                HiveChannelSpec(
                    key: Channels.messages,
                    scope: .global,
                    reducer: ColonyReducers.messages(),
                    updatePolicy: .multi,
                    initial: { [] },
                    codec: messagesCodec,
                    persistence: .checkpointed
                )
            ),
            AnyHiveChannelSpec(
                HiveChannelSpec(
                    key: Channels.llmInputMessages,
                    scope: .global,
                    reducer: .lastWriteWins(),
                    updatePolicy: .single,
                    initial: { nil },
                    persistence: .untracked
                )
            ),
            AnyHiveChannelSpec(
                HiveChannelSpec(
                    key: Channels.pendingToolCalls,
                    scope: .global,
                    reducer: .lastWriteWins(),
                    updatePolicy: .single,
                    initial: { [] },
                    codec: toolCallsCodec,
                    persistence: .checkpointed
                )
            ),
            AnyHiveChannelSpec(
                HiveChannelSpec(
                    key: Channels.finalAnswer,
                    scope: .global,
                    reducer: .lastWriteWins(),
                    updatePolicy: .single,
                    initial: { nil },
                    codec: HiveAnyCodec(HiveJSONCodec<String?>(id: "colony.final-answer.v1")),
                    persistence: .checkpointed
                )
            ),
            AnyHiveChannelSpec(
                HiveChannelSpec(
                    key: Channels.todos,
                    scope: .global,
                    reducer: .lastWriteWins(),
                    updatePolicy: .single,
                    initial: { [] },
                    codec: todosCodec,
                    persistence: .checkpointed
                )
            ),
            AnyHiveChannelSpec(
                HiveChannelSpec(
                    key: Channels.currentToolCall,
                    scope: .taskLocal,
                    reducer: .lastWriteWins(),
                    updatePolicy: .single,
                    initial: { HiveToolCall(id: "", name: "", argumentsJSON: "{}") },
                    codec: currentToolCallCodec,
                    persistence: .checkpointed
                )
            ),
        ]
    }

    public static func inputWrites(
        _ input: String,
        inputContext: HiveInputContext
    ) throws -> [AnyHiveWrite<ColonySchema>] {
        let message = HiveChatMessage(
            id: ColonyMessageID.userMessageID(runID: inputContext.runID, stepIndex: inputContext.stepIndex),
            role: .user,
            content: input
        )
        return [
            AnyHiveWrite(Channels.messages, [message]),
            AnyHiveWrite(Channels.finalAnswer, nil),
        ]
    }
}

public struct ColonyContext: Sendable {
    public let configuration: ColonyConfiguration
    public let filesystem: (any ColonyFileSystemBackend)?
    public let shell: (any ColonyShellBackend)?
    public let subagents: (any ColonySubagentRegistry)?
    public let tokenizer: any ColonyTokenizer

    public init(
        configuration: ColonyConfiguration,
        filesystem: (any ColonyFileSystemBackend)?,
        shell: (any ColonyShellBackend)? = nil,
        subagents: (any ColonySubagentRegistry)? = nil,
        tokenizer: any ColonyTokenizer = ColonyApproximateTokenizer()
    ) {
        self.configuration = configuration
        self.filesystem = filesystem
        self.shell = shell
        self.subagents = subagents
        self.tokenizer = tokenizer
    }
}

public enum ColonyAgent {
    public static let nodePreModel = HiveNodeID("preModel")
    public static let nodeModel = HiveNodeID("model")
    public static let nodeRouteAfterModel = HiveNodeID("routeAfterModel")
    public static let nodeTools = HiveNodeID("tools")
    public static let nodeToolExecute = HiveNodeID("toolExecute")

    public static func compile(graphVersionOverride: String? = nil) throws -> CompiledHiveGraph<ColonySchema> {
        var builder = HiveGraphBuilder<ColonySchema>(start: [nodePreModel])

        builder.addNode(nodePreModel, preModel)
        builder.addNode(nodeModel, model)
        builder.addNode(nodeRouteAfterModel) { _ in HiveNodeOutput() }
        builder.addRouter(from: nodeRouteAfterModel, routeAfterModel)
        builder.addNode(nodeTools, tools)
        builder.addNode(nodeToolExecute, toolExecute)

        builder.addEdge(from: nodePreModel, to: nodeModel)
        builder.addEdge(from: nodeModel, to: nodeRouteAfterModel)
        builder.addEdge(from: nodeRouteAfterModel, to: nodeTools)
        builder.addEdge(from: nodeToolExecute, to: nodePreModel)

        return try builder.compile(graphVersionOverride: graphVersionOverride)
    }

    private static func preModel(_ input: HiveNodeInput<ColonySchema>) async throws -> HiveNodeOutput<ColonySchema> {
        let messages = try input.store.get(ColonySchema.Channels.messages)
        var updatedMessages = messages
        var rewritesMessages: Bool = false

        let (patchedMessages, didPatchToolCalls) = patchDanglingToolCalls(in: updatedMessages)
        if didPatchToolCalls {
            updatedMessages = patchedMessages
            rewritesMessages = true
        }

        if let policy = input.context.configuration.summarizationPolicy,
           let filesystem = input.context.filesystem
        {
            if let summarized = try await maybeSummarize(
                messages: updatedMessages,
                policy: policy,
                tokenizer: input.context.tokenizer,
                filesystem: filesystem,
                threadID: input.run.threadID
            ) {
                updatedMessages = summarized
                rewritesMessages = true
            }
        }

        var writes: [AnyHiveWrite<ColonySchema>] = []
        writes.reserveCapacity(2)

        if rewritesMessages {
            let removeAll = HiveChatMessage(
                id: ColonySchema.removeAllMessagesID,
                role: .system,
                content: "",
                op: .removeAll
            )
            writes.append(AnyHiveWrite(ColonySchema.Channels.messages, [removeAll] + updatedMessages))
        }

        let compacted = input.context.configuration.compactionPolicy.compact(updatedMessages, tokenizer: input.context.tokenizer)
        writes.append(AnyHiveWrite(ColonySchema.Channels.llmInputMessages, compacted))

        return HiveNodeOutput(writes: writes)
    }

    private static func model(_ input: HiveNodeInput<ColonySchema>) async throws -> HiveNodeOutput<ColonySchema> {
        let messages = try input.store.get(ColonySchema.Channels.messages)
        let llmInputMessages = try input.store.get(ColonySchema.Channels.llmInputMessages)
        let externalTools = input.environment.tools?.listTools() ?? []
        let builtInTools = builtInToolDefinitions(for: input.context)
        let tools = dedupeToolsByName(builtIn: builtInTools, external: externalTools)

        let memory: String?
        let skills: String?
        if let filesystem = input.context.filesystem {
            memory = try await loadAgentsMemory(
                sources: input.context.configuration.memorySources,
                tokenLimit: input.context.configuration.systemPromptMemoryTokenLimit,
                filesystem: filesystem
            )
            skills = try await loadSkillsCatalogMetadata(
                sources: input.context.configuration.skillSources,
                tokenLimit: input.context.configuration.systemPromptSkillsTokenLimit,
                filesystem: filesystem
            )
        } else {
            memory = nil
            skills = nil
        }

        let systemPrompt = ColonyPrompts.systemPrompt(
            additional: input.context.configuration.additionalSystemPrompt,
            memory: memory,
            skills: skills,
            availableTools: tools
        )
        let systemMessage = HiveChatMessage(
            id: "system:colony",
            role: .system,
            content: systemPrompt
        )

        let inputMessages = (llmInputMessages ?? messages)

        let messageTokenLimit: Int?
        if let hardLimit = input.context.configuration.requestHardTokenLimit {
            let toolTokenCount = toolDefinitionTokenCount(tools, tokenizer: input.context.tokenizer)
            guard toolTokenCount < hardLimit else {
                throw ColonyBudgetError.toolDefinitionsExceedHardRequestTokenLimit(
                    requestHardTokenLimit: hardLimit,
                    toolTokenCount: toolTokenCount,
                    toolCount: tools.count
                )
            }
            messageTokenLimit = hardLimit - toolTokenCount
        } else {
            messageTokenLimit = nil
        }

        let requestMessages = requestMessagesWithHardTokenLimit(
            systemMessage: systemMessage,
            conversationMessages: inputMessages,
            tokenLimit: messageTokenLimit,
            tokenizer: input.context.tokenizer
        )
        let request = HiveChatRequest(
            model: input.context.configuration.modelName,
            messages: requestMessages,
            tools: tools
        )

        let modelClient: AnyHiveModelClient
        if let router = input.environment.modelRouter {
            modelClient = router.route(request, hints: input.environment.inferenceHints)
        } else if let direct = input.environment.model {
            modelClient = direct
        } else {
            throw HiveRuntimeError.modelClientMissing
        }

        input.emitStream(.modelInvocationStarted(model: request.model), [:])
        defer { input.emitStream(.modelInvocationFinished, [:]) }

        var finalResponse: HiveChatResponse?
        for try await chunk in modelClient.stream(request) {
            switch chunk {
            case .token(let token):
                if finalResponse != nil {
                    throw HiveRuntimeError.modelStreamInvalid("Received token after final chunk.")
                }
                input.emitStream(.modelToken(text: token), [:])
            case .final(let response):
                if finalResponse != nil {
                    throw HiveRuntimeError.modelStreamInvalid("Received multiple final chunks.")
                }
                finalResponse = response
            }
        }

        guard let response = finalResponse else {
            throw HiveRuntimeError.modelStreamInvalid("Missing final chunk.")
        }

        let assistantMessage = ColonyMessages.makeDeterministicAssistantMessage(
            from: response.message,
            taskID: input.run.taskID
        )

        var writes: [AnyHiveWrite<ColonySchema>] = [
            AnyHiveWrite(ColonySchema.Channels.messages, [assistantMessage]),
            AnyHiveWrite(ColonySchema.Channels.pendingToolCalls, assistantMessage.toolCalls),
            AnyHiveWrite(ColonySchema.Channels.llmInputMessages, nil),
        ]

        if assistantMessage.toolCalls.isEmpty {
            writes.append(AnyHiveWrite(ColonySchema.Channels.finalAnswer, assistantMessage.content))
        }

        return HiveNodeOutput(writes: writes)
    }

    private static func toolDefinitionTokenCount(
        _ tools: [HiveToolDefinition],
        tokenizer: any ColonyTokenizer
    ) -> Int {
        guard tools.isEmpty == false else { return 0 }

        let content: String = {
            do {
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.sortedKeys]
                let data = try encoder.encode(tools)
                return String(decoding: data, as: UTF8.self)
            } catch {
                return tools
                    .sorted { $0.name.utf8.lexicographicallyPrecedes($1.name.utf8) }
                    .map { tool in
                        [tool.name, tool.description, tool.parametersJSONSchema].joined(separator: "\n")
                    }
                    .joined(separator: "\n\n")
            }
        }()

        return tokenizer.countTokens([HiveChatMessage(id: "budget:tools", role: .system, content: content)])
    }

    private static func requestMessagesWithHardTokenLimit(
        systemMessage: HiveChatMessage,
        conversationMessages: [HiveChatMessage],
        tokenLimit: Int?,
        tokenizer: any ColonyTokenizer
    ) -> [HiveChatMessage] {
        guard let tokenLimit else { return [systemMessage] + conversationMessages }
        guard tokenLimit > 0 else { return [systemMessage] }

        let boundedSystemMessage = trimSystemMessageToFitTokenLimit(
            systemMessage,
            tokenLimit: tokenLimit,
            tokenizer: tokenizer
        )
        var keptConversation = conversationMessages
        var requestMessages = [boundedSystemMessage] + keptConversation

        while keptConversation.isEmpty == false, tokenizer.countTokens(requestMessages) > tokenLimit {
            keptConversation.removeFirst()
            requestMessages = [boundedSystemMessage] + keptConversation
        }

        if tokenizer.countTokens(requestMessages) <= tokenLimit {
            return requestMessages
        }

        return [boundedSystemMessage]
    }

    private static func trimSystemMessageToFitTokenLimit(
        _ systemMessage: HiveChatMessage,
        tokenLimit: Int,
        tokenizer: any ColonyTokenizer
    ) -> HiveChatMessage {
        if tokenizer.countTokens([systemMessage]) <= tokenLimit {
            return systemMessage
        }

        let content = systemMessage.content
        var low = 0
        var high = content.count

        while low < high {
            let mid = (low + high + 1) / 2
            let candidate = systemMessageWithTrimmedContent(systemMessage, maxCharacters: mid)
            if tokenizer.countTokens([candidate]) <= tokenLimit {
                low = mid
            } else {
                high = mid - 1
            }
        }

        return systemMessageWithTrimmedContent(systemMessage, maxCharacters: low)
    }

    private static func systemMessageWithTrimmedContent(
        _ systemMessage: HiveChatMessage,
        maxCharacters: Int
    ) -> HiveChatMessage {
        let trimmedContent = String(systemMessage.content.prefix(maxCharacters))
        return HiveChatMessage(
            id: systemMessage.id,
            role: systemMessage.role,
            content: trimmedContent,
            name: systemMessage.name,
            toolCallID: systemMessage.toolCallID,
            toolCalls: systemMessage.toolCalls,
            op: systemMessage.op
        )
    }

    private static func routeAfterModel(_ store: HiveStoreView<ColonySchema>) -> HiveNext {
        let calls = (try? store.get(ColonySchema.Channels.pendingToolCalls)) ?? []
        return calls.isEmpty ? .end : .nodes([nodeTools])
    }

    private static func tools(_ input: HiveNodeInput<ColonySchema>) async throws -> HiveNodeOutput<ColonySchema> {
        let pending = try input.store.get(ColonySchema.Channels.pendingToolCalls)
        let calls = pending.sorted { lhs, rhs in
            if lhs.name == rhs.name { return lhs.id.utf8.lexicographicallyPrecedes(rhs.id.utf8) }
            return lhs.name.utf8.lexicographicallyPrecedes(rhs.name.utf8)
        }

        let requiresApproval = input.context.configuration.toolApprovalPolicy.requiresApproval(for: calls.map(\.name))
        if requiresApproval {
            if let resume = input.run.resume, case let .toolApproval(decision) = resume.payload {
                switch decision {
                case .approved:
                    return try approvedToolPath(input: input, calls: calls)
                case .rejected:
                    return try rejectedToolPath(input: input, calls: calls, taskID: input.run.taskID)
                }
            }

            return HiveNodeOutput(
                next: .nodes([nodeTools]),
                interrupt: HiveInterruptRequest(payload: .toolApprovalRequired(toolCalls: calls))
            )
        }

        return try approvedToolPath(input: input, calls: calls)
    }

    private static func approvedToolPath(
        input: HiveNodeInput<ColonySchema>,
        calls: [HiveToolCall]
    ) throws -> HiveNodeOutput<ColonySchema> {
        var spawn: [HiveTaskSeed<ColonySchema>] = []
        spawn.reserveCapacity(calls.count)
        for call in calls {
            var local = HiveTaskLocalStore<ColonySchema>.empty
            try local.set(ColonySchema.Channels.currentToolCall, call)
            spawn.append(HiveTaskSeed(nodeID: nodeToolExecute, local: local))
        }
        return HiveNodeOutput(
            writes: [AnyHiveWrite(ColonySchema.Channels.pendingToolCalls, [])],
            spawn: spawn,
            next: .end
        )
    }

    private static func rejectedToolPath(
        input: HiveNodeInput<ColonySchema>,
        calls: [HiveToolCall],
        taskID: HiveTaskID
    ) throws -> HiveNodeOutput<ColonySchema> {
        let messageID = ColonyMessageID.systemMessageID(taskID: taskID)
        let system = HiveChatMessage(
            id: messageID,
            role: .system,
            content: "Tool execution rejected by user."
        )

        let cancellations = calls.map { call in
            HiveChatMessage(
                id: "tool:" + call.id,
                role: .tool,
                content: "Tool call \(call.name) with id \(call.id) was cancelled - tool execution was rejected by the user.",
                name: call.name,
                toolCallID: call.id
            )
        }
        return HiveNodeOutput(
            writes: [
                AnyHiveWrite(ColonySchema.Channels.pendingToolCalls, []),
                AnyHiveWrite(ColonySchema.Channels.messages, [system] + cancellations),
            ],
            next: .nodes([nodePreModel])
        )
    }

    private static func toolExecute(_ input: HiveNodeInput<ColonySchema>) async throws -> HiveNodeOutput<ColonySchema> {
        let call = try input.store.get(ColonySchema.Channels.currentToolCall)
        input.emitStream(.toolInvocationStarted(name: call.name), ["toolCallID": call.id])

        let outcome = await ColonyTools.execute(call: call, input: input)
        input.emitStream(.toolInvocationFinished(name: call.name, success: outcome.success), ["toolCallID": call.id])

        let toolContent = await maybeEvictLargeToolResult(
            toolCall: call,
            content: outcome.content,
            filesystem: input.context.filesystem,
            tokenLimit: input.context.configuration.toolResultEvictionTokenLimit
        )

        let toolMessage = HiveChatMessage(
            id: "tool:" + call.id,
            role: .tool,
            content: toolContent,
            name: call.name,
            toolCallID: call.id
        )

        var writes: [AnyHiveWrite<ColonySchema>] = [
            AnyHiveWrite(ColonySchema.Channels.messages, [toolMessage]),
        ]
        writes.append(contentsOf: outcome.writes)

        return HiveNodeOutput(writes: writes)
    }

    private static func builtInToolDefinitions(for context: ColonyContext) -> [HiveToolDefinition] {
        var tools: [HiveToolDefinition] = []

        if context.configuration.capabilities.contains(.planning) {
            tools.append(ColonyBuiltInToolDefinitions.writeTodos)
            tools.append(ColonyBuiltInToolDefinitions.readTodos)
        }

        if context.configuration.capabilities.contains(.filesystem), context.filesystem != nil {
            tools.append(contentsOf: [
                ColonyBuiltInToolDefinitions.ls,
                ColonyBuiltInToolDefinitions.readFile,
                ColonyBuiltInToolDefinitions.writeFile,
                ColonyBuiltInToolDefinitions.editFile,
                ColonyBuiltInToolDefinitions.glob,
                ColonyBuiltInToolDefinitions.grep,
            ])
        }

        if context.configuration.capabilities.contains(.shell), context.shell != nil {
            tools.append(ColonyBuiltInToolDefinitions.execute)
        }

        if context.configuration.capabilities.contains(.subagents), let subagents = context.subagents {
            tools.append(
                ColonyBuiltInToolDefinitions.task(availableSubagents: subagents.listSubagents())
            )
        }

        return tools
    }

    private static func dedupeToolsByName(
        builtIn: [HiveToolDefinition],
        external: [HiveToolDefinition]
    ) -> [HiveToolDefinition] {
        var byName: [String: HiveToolDefinition] = [:]
        for tool in builtIn { byName[tool.name] = tool }
        for tool in external { byName[tool.name] = tool }
        return byName.values.sorted { $0.name.utf8.lexicographicallyPrecedes($1.name.utf8) }
    }

    // MARK: - Deep Agents parity helpers

    private static let toolResultEvictionCharsPerToken: Int = 4
    private static let toolNamesExcludedFromEviction: Set<String> = [
        ColonyBuiltInToolDefinitions.ls.name,
        ColonyBuiltInToolDefinitions.glob.name,
        ColonyBuiltInToolDefinitions.grep.name,
        ColonyBuiltInToolDefinitions.readFile.name,
        ColonyBuiltInToolDefinitions.editFile.name,
        ColonyBuiltInToolDefinitions.writeFile.name,
    ]

    private static func truncateSystemPromptSection(
        _ text: String?,
        tokenLimit: Int?,
        truncatedNotice: String
    ) -> String? {
        guard var text else { return nil }
        guard let tokenLimit, tokenLimit > 0 else { return text }

        let maxChars = tokenLimit * toolResultEvictionCharsPerToken
        guard text.count > maxChars else { return text }

        let prefix = String(text.prefix(maxChars))
        text = prefix + "\n\n" + truncatedNotice
        return text
    }

    private static func patchDanglingToolCalls(
        in messages: [HiveChatMessage]
    ) -> (messages: [HiveChatMessage], didPatch: Bool) {
        guard messages.isEmpty == false else { return (messages, false) }

        var patched: [HiveChatMessage] = []
        patched.reserveCapacity(messages.count)
        var didPatch = false

        for (index, message) in messages.enumerated() {
            patched.append(message)

            guard message.role == .assistant, message.toolCalls.isEmpty == false else { continue }

            for call in message.toolCalls {
                let hasToolMessage = messages[(index + 1)...].contains { later in
                    later.role == .tool && later.toolCallID == call.id
                }
                if hasToolMessage { continue }

                didPatch = true
                patched.append(
                    HiveChatMessage(
                        id: "tool:" + call.id,
                        role: .tool,
                        content: "Tool call \(call.name) with id \(call.id) was cancelled - another message came in before it could be completed.",
                        name: call.name,
                        toolCallID: call.id
                    )
                )
            }
        }

        return (patched, didPatch)
    }

    private static func maybeSummarize(
        messages: [HiveChatMessage],
        policy: ColonySummarizationPolicy,
        tokenizer: any ColonyTokenizer,
        filesystem: any ColonyFileSystemBackend,
        threadID: HiveThreadID
    ) async throws -> [HiveChatMessage]? {
        guard messages.isEmpty == false else { return nil }
        guard tokenizer.countTokens(messages) > policy.triggerTokens else { return nil }

        let keepLastMessages = max(0, policy.keepLastMessages)
        guard messages.count > keepLastMessages else { return nil }

        let threadSlug = sanitizePathComponent(threadID.rawValue)
        let historyPath = try ColonyVirtualPath(policy.historyPathPrefix.rawValue + "/" + threadSlug + ".md")

        let offloaded = Array(messages.prefix(messages.count - keepLastMessages))
        let tail = Array(messages.suffix(keepLastMessages))

        let historyMarkdown = renderConversationHistoryMarkdown(offloaded)
        try await appendFile(filesystem: filesystem, path: historyPath, content: historyMarkdown)

        let summaryMessage = HiveChatMessage(
            id: "system:summary:" + threadSlug,
            role: .system,
            content: "Note: conversation has been summarized. Full prior history is available at \(historyPath.rawValue)."
        )

        return [summaryMessage] + tail
    }

    private static func loadAgentsMemory(
        sources: [ColonyVirtualPath],
        tokenLimit: Int?,
        filesystem: any ColonyFileSystemBackend
    ) async throws -> String? {
        guard sources.isEmpty == false else { return nil }
        var parts: [String] = []
        parts.reserveCapacity(sources.count)
        for path in sources {
            if let content = try? await filesystem.read(at: path) {
                let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty == false {
                    parts.append(trimmed)
                }
            }
        }
        let merged = parts.isEmpty ? nil : parts.joined(separator: "\n\n")
        return truncateSystemPromptSection(
            merged,
            tokenLimit: tokenLimit,
            truncatedNotice: "[Memory truncated to fit context budget]"
        )
    }

    private static func loadSkillsCatalogMetadata(
        sources: [ColonyVirtualPath],
        tokenLimit: Int?,
        filesystem: any ColonyFileSystemBackend
    ) async throws -> String? {
        guard sources.isEmpty == false else { return nil }

        var skillPaths: Set<ColonyVirtualPath> = []
        for root in sources {
            if root.rawValue.hasSuffix("/SKILL.md") {
                skillPaths.insert(root)
                continue
            }
            let pattern = root.rawValue + "/**/SKILL.md"
            if let matches = try? await filesystem.glob(pattern: pattern) {
                skillPaths.formUnion(matches)
            }
        }

        let sorted = skillPaths.sorted { lhs, rhs in lhs.rawValue.utf8.lexicographicallyPrecedes(rhs.rawValue.utf8) }
        guard sorted.isEmpty == false else { return nil }

        var lines: [String] = []
        lines.reserveCapacity(sorted.count)
        for path in sorted {
            guard let content = try? await filesystem.read(at: path) else { continue }
            let metadata = parseSkillFrontmatter(content)
            guard let name = metadata.name, name.isEmpty == false else { continue }

            if let description = metadata.description, description.isEmpty == false {
                lines.append("- \(name): \(description) (\(path.rawValue))")
            } else {
                lines.append("- \(name) (\(path.rawValue))")
            }
        }

        let merged = lines.isEmpty ? nil : lines.joined(separator: "\n")
        return truncateSystemPromptSection(
            merged,
            tokenLimit: tokenLimit,
            truncatedNotice: "[Skills list truncated to fit context budget]"
        )
    }

    private static func parseSkillFrontmatter(_ content: String) -> (name: String?, description: String?) {
        var name: String?
        var description: String?

        var lines = content.split(separator: "\n", omittingEmptySubsequences: false)
        guard let first = lines.first?.trimmingCharacters(in: .whitespacesAndNewlines), first == "---" else {
            return (nil, nil)
        }

        lines.removeFirst()
        while let line = lines.first {
            lines.removeFirst()

            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed == "---" { break }

            if let value = yamlScalarValue(line: trimmed, key: "name") {
                name = value
            } else if let value = yamlScalarValue(line: trimmed, key: "description") {
                description = value
            }
        }

        return (name, description)
    }

    private static func yamlScalarValue(line: String, key: String) -> String? {
        let prefix = key + ":"
        guard line.hasPrefix(prefix) else { return nil }
        var value = line.dropFirst(prefix.count)
        if value.first == " " { value = value.dropFirst() }
        return value.trimmingCharacters(in: CharacterSet(charactersIn: "\"' ").union(.whitespacesAndNewlines))
    }

    private static func maybeEvictLargeToolResult(
        toolCall: HiveToolCall,
        content: String,
        filesystem: (any ColonyFileSystemBackend)?,
        tokenLimit: Int?
    ) async -> String {
        guard let filesystem else { return content }
        guard let tokenLimit, tokenLimit > 0 else { return content }
        guard toolNamesExcludedFromEviction.contains(toolCall.name) == false else { return content }

        let threshold = tokenLimit * toolResultEvictionCharsPerToken
        guard content.count > threshold else { return content }

        let sanitizedID = sanitizeToolCallID(toolCall.id)
        let path: ColonyVirtualPath
        do {
            path = try ColonyVirtualPath("/large_tool_results/" + sanitizedID)
        } catch {
            return content
        }

        do {
            try await writeOrOverwrite(filesystem: filesystem, path: path, content: content)
        } catch {
            return content
        }

        let preview = createContentPreview(content)
        return """
Tool result too large (tool_call_id: \(toolCall.id)).
Full content was written to \(path.rawValue). Read it with read_file using offset/limit.

Preview:
\(preview)
"""
    }

    private static func createContentPreview(_ content: String) -> String {
        let maxSample = 2_000
        if content.count <= maxSample * 2 { return content }

        let head = String(content.prefix(maxSample))
        let tail = String(content.suffix(maxSample))
        return head + "\n...\n" + tail
    }

    private static func sanitizeToolCallID(_ id: String) -> String {
        id.map { character in
            switch character {
            case ".", "/", "\\":
                return "_"
            default:
                return character
            }
        }.reduce(into: "") { $0.append($1) }
    }

    private static func sanitizePathComponent(_ input: String) -> String {
        input.map { character in
            switch character {
            case "/", "\\":
                return "_"
            default:
                return character
            }
        }.reduce(into: "") { $0.append($1) }
    }

    private static func appendFile(
        filesystem: any ColonyFileSystemBackend,
        path: ColonyVirtualPath,
        content: String
    ) async throws {
        if let existing = try? await filesystem.read(at: path) {
            if existing.isEmpty {
                // No safe edit path for empty sentinel content; keep existing.
                return
            }
            let updated = existing + "\n\n" + content
            _ = try await filesystem.edit(at: path, oldString: existing, newString: updated, replaceAll: false)
        } else {
            try await filesystem.write(at: path, content: content)
        }
    }

    private static func writeOrOverwrite(
        filesystem: any ColonyFileSystemBackend,
        path: ColonyVirtualPath,
        content: String
    ) async throws {
        do {
            try await filesystem.write(at: path, content: content)
        } catch let error as ColonyFileSystemError {
            switch error {
            case .alreadyExists:
                if let existing = try? await filesystem.read(at: path), existing.isEmpty == false {
                    _ = try await filesystem.edit(
                        at: path,
                        oldString: existing,
                        newString: content,
                        replaceAll: false
                    )
                }
            default:
                throw error
            }
        }
    }

    private static func renderConversationHistoryMarkdown(_ messages: [HiveChatMessage]) -> String {
        var lines: [String] = []
        lines.reserveCapacity(messages.count * 3)

        for message in messages {
            lines.append("### \(String(describing: message.role))")
            lines.append(message.content)
            lines.append("")
        }

        return lines.joined(separator: "\n")
    }
}

// MARK: - Messages

enum ColonyReducers {
    static func messages() -> HiveReducer<[HiveChatMessage]> {
        HiveReducer<[HiveChatMessage]> { left, right in
            try ColonyMessages.reduceMessages(left: left, right: right)
        }
    }
}

enum ColonyMessages {
    static func reduceMessages(
        left initialLeft: [HiveChatMessage],
        right initialRight: [HiveChatMessage]
    ) throws -> [HiveChatMessage] {
        var left = initialLeft
        var right = initialRight

        for message in right where message.op == .removeAll {
            guard message.id == ColonySchema.removeAllMessagesID else {
                throw HiveRuntimeError.invalidMessagesUpdate
            }
        }

        if let lastRemoveAllIndex = right.lastIndex(where: { $0.op == .removeAll }) {
            left = []
            if lastRemoveAllIndex + 1 < right.count {
                right = Array(right[(lastRemoveAllIndex + 1)...])
            } else {
                right = []
            }
        }

        var merged = left
        var indexByID: [String: Int] = [:]
        indexByID.reserveCapacity(merged.count)
        for (index, message) in merged.enumerated() where indexByID[message.id] == nil {
            indexByID[message.id] = index
        }

        var idsToDelete: Set<String> = []

        for message in right {
            switch message.op {
            case .some(.removeAll):
                continue
            case .some(.remove):
                guard indexByID[message.id] != nil else {
                    throw HiveRuntimeError.invalidMessagesUpdate
                }
                idsToDelete.insert(message.id)
            case .none:
                if let existingIndex = indexByID[message.id] {
                    merged[existingIndex] = HiveChatMessage(
                        id: message.id,
                        role: message.role,
                        content: message.content,
                        name: message.name,
                        toolCallID: message.toolCallID,
                        toolCalls: message.toolCalls,
                        op: nil
                    )
                    idsToDelete.remove(message.id)
                } else {
                    let normalized = HiveChatMessage(
                        id: message.id,
                        role: message.role,
                        content: message.content,
                        name: message.name,
                        toolCallID: message.toolCallID,
                        toolCalls: message.toolCalls,
                        op: nil
                    )
                    merged.append(normalized)
                    indexByID[normalized.id] = merged.count - 1
                }
            }
        }

        if idsToDelete.isEmpty == false {
            merged.removeAll { idsToDelete.contains($0.id) }
        }

        return merged.map { message in
            HiveChatMessage(
                id: message.id,
                role: message.role,
                content: message.content,
                name: message.name,
                toolCallID: message.toolCallID,
                toolCalls: message.toolCalls,
                op: nil
            )
        }
    }

    static func makeDeterministicAssistantMessage(
        from message: HiveChatMessage,
        taskID: HiveTaskID
    ) -> HiveChatMessage {
        HiveChatMessage(
            id: ColonyMessageID.assistantMessageID(taskID: taskID),
            role: .assistant,
            content: message.content,
            toolCalls: message.toolCalls
        )
    }
}

enum ColonyMessageID {
    static func userMessageID(runID: HiveRunID, stepIndex: Int) -> String {
        var bytes = Data()
        bytes.append(contentsOf: "HMSG1".utf8)
        bytes.append(contentsOf: uuidBytes(runID.rawValue))
        appendUInt32BE(UInt32(stepIndex), to: &bytes)
        bytes.append(contentsOf: "user".utf8)
        appendUInt32BE(0, to: &bytes)
        return "msg:" + sha256HexLower(bytes)
    }

    static func assistantMessageID(taskID: HiveTaskID) -> String {
        var bytes = Data()
        bytes.append(contentsOf: "HMSG1".utf8)
        bytes.append(contentsOf: Data(taskID.rawValue.utf8))
        bytes.append(0x00)
        bytes.append(contentsOf: "assistant".utf8)
        appendUInt32BE(0, to: &bytes)
        return "msg:" + sha256HexLower(bytes)
    }

    static func systemMessageID(taskID: HiveTaskID) -> String {
        var bytes = Data()
        bytes.append(contentsOf: "HMSG1".utf8)
        bytes.append(contentsOf: Data(taskID.rawValue.utf8))
        bytes.append(0x00)
        bytes.append(contentsOf: "system".utf8)
        appendUInt32BE(0, to: &bytes)
        return "msg:" + sha256HexLower(bytes)
    }

    private static func sha256HexLower(_ data: Data) -> String {
        let hash = SHA256.hash(data: data)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }

    private static func uuidBytes(_ uuid: UUID) -> [UInt8] {
        withUnsafeBytes(of: uuid.uuid) { raw in Array(raw) }
    }

    private static func appendUInt32BE(_ value: UInt32, to data: inout Data) {
        var bigEndian = value.bigEndian
        withUnsafeBytes(of: &bigEndian) { data.append(contentsOf: $0) }
    }
}

// MARK: - Tools

struct ColonyToolOutcome<Schema: HiveSchema>: Sendable {
    var success: Bool
    var content: String
    var writes: [AnyHiveWrite<Schema>]
}

enum ColonyTools {
    static func execute(
        call: HiveToolCall,
        input: HiveNodeInput<ColonySchema>
    ) async -> ColonyToolOutcome<ColonySchema> {
        do {
            if let builtIn = try await executeBuiltIn(call: call, input: input) {
                return builtIn
            }

            if let external = input.environment.tools {
                let result = try await external.invoke(call)
                return ColonyToolOutcome(success: true, content: result.content, writes: [])
            }

            return ColonyToolOutcome(success: false, content: "Error: Tool registry missing.", writes: [])
        } catch {
            return ColonyToolOutcome(
                success: false,
                content: "Error: \(error)",
                writes: []
            )
        }
    }

    private static func executeBuiltIn(
        call: HiveToolCall,
        input: HiveNodeInput<ColonySchema>
    ) async throws -> ColonyToolOutcome<ColonySchema>? {
        switch call.name {
        case ColonyBuiltInToolDefinitions.writeTodos.name:
            let args = try decode(call.argumentsJSON, as: WriteTodosArgs.self)
            let todos = args.todos
            return ColonyToolOutcome(
                success: true,
                content: renderTodos(todos),
                writes: [AnyHiveWrite(ColonySchema.Channels.todos, todos)]
            )

        case ColonyBuiltInToolDefinitions.readTodos.name:
            let todos = try input.store.get(ColonySchema.Channels.todos)
            return ColonyToolOutcome(success: true, content: renderTodos(todos), writes: [])

        case ColonyBuiltInToolDefinitions.ls.name:
            guard let fs = input.context.filesystem else {
                return ColonyToolOutcome(success: false, content: "Error: Filesystem not configured.", writes: [])
            }
            let args = try decode(call.argumentsJSON, as: LSArgs.self, defaultingToEmptyObject: true)
            let path = try ColonyVirtualPath(args.path ?? "/")
            let infos = try await fs.list(at: path)
            let lines = infos.map { info in
                info.isDirectory ? (info.path.rawValue + "/") : info.path.rawValue
            }
            return ColonyToolOutcome(success: true, content: lines.joined(separator: "\n"), writes: [])

        case ColonyBuiltInToolDefinitions.readFile.name:
            guard let fs = input.context.filesystem else {
                return ColonyToolOutcome(success: false, content: "Error: Filesystem not configured.", writes: [])
            }
            let args = try decode(call.argumentsJSON, as: ReadFileArgs.self)
            let path = try ColonyVirtualPath(args.path)
            let text = try await fs.read(at: path)
            let offset = max(0, args.offset ?? 0)
            let limit = max(1, args.limit ?? 100)
            return ColonyToolOutcome(
                success: true,
                content: formatWithLineNumbers(text: text, offset: offset, limit: limit),
                writes: []
            )

        case ColonyBuiltInToolDefinitions.writeFile.name:
            guard let fs = input.context.filesystem else {
                return ColonyToolOutcome(success: false, content: "Error: Filesystem not configured.", writes: [])
            }
            let args = try decode(call.argumentsJSON, as: WriteFileArgs.self)
            let path = try ColonyVirtualPath(args.path)
            try await fs.write(at: path, content: args.content)
            return ColonyToolOutcome(success: true, content: "OK: wrote \(path.rawValue)", writes: [])

        case ColonyBuiltInToolDefinitions.editFile.name:
            guard let fs = input.context.filesystem else {
                return ColonyToolOutcome(success: false, content: "Error: Filesystem not configured.", writes: [])
            }
            let args = try decode(call.argumentsJSON, as: EditFileArgs.self)
            let path = try ColonyVirtualPath(args.path)
            let occurrences = try await fs.edit(
                at: path,
                oldString: args.oldString,
                newString: args.newString,
                replaceAll: args.replaceAll ?? false
            )
            return ColonyToolOutcome(
                success: true,
                content: "OK: edited \(path.rawValue) (\(occurrences) replacement(s))",
                writes: []
            )

        case ColonyBuiltInToolDefinitions.glob.name:
            guard let fs = input.context.filesystem else {
                return ColonyToolOutcome(success: false, content: "Error: Filesystem not configured.", writes: [])
            }
            let args = try decode(call.argumentsJSON, as: GlobArgs.self)
            let paths = try await fs.glob(pattern: args.pattern)
            return ColonyToolOutcome(success: true, content: paths.map(\.rawValue).joined(separator: "\n"), writes: [])

        case ColonyBuiltInToolDefinitions.grep.name:
            guard let fs = input.context.filesystem else {
                return ColonyToolOutcome(success: false, content: "Error: Filesystem not configured.", writes: [])
            }
            let args = try decode(call.argumentsJSON, as: GrepArgs.self)
            let matches = try await fs.grep(pattern: args.pattern, glob: args.glob)
            let lines = matches.map { "\($0.path.rawValue):\($0.line): \($0.text)" }
            return ColonyToolOutcome(success: true, content: lines.joined(separator: "\n"), writes: [])

        case ColonyBuiltInToolDefinitions.execute.name:
            guard let shell = input.context.shell else {
                return ColonyToolOutcome(success: false, content: "Error: Shell backend not configured.", writes: [])
            }
            let args = try decode(call.argumentsJSON, as: ExecuteArgs.self)
            let cwd: ColonyVirtualPath?
            if let rawCWD = args.cwd, rawCWD.isEmpty == false {
                cwd = try ColonyVirtualPath(rawCWD)
            } else {
                cwd = nil
            }
            let timeoutNanoseconds = args.timeoutMilliseconds.map { millis -> UInt64 in
                UInt64(max(0, millis)) * 1_000_000
            }
            let request = ColonyShellExecutionRequest(
                command: args.command,
                workingDirectory: cwd,
                timeoutNanoseconds: timeoutNanoseconds
            )
            let result = try await shell.execute(request)
            return ColonyToolOutcome(
                success: result.exitCode == 0,
                content: formatShellResult(result),
                writes: []
            )

        case ColonyBuiltInToolDefinitions.taskName:
            guard let subagents = input.context.subagents else {
                return ColonyToolOutcome(success: false, content: "Error: Subagent registry not configured.", writes: [])
            }
            let args = try decode(call.argumentsJSON, as: TaskArgs.self)
            let type = args.subagentType?.trimmingCharacters(in: .whitespacesAndNewlines)
            let selectedType = (type?.isEmpty == false) ? type! : "general-purpose"
            let result = try await subagents.run(
                ColonySubagentRequest(
                    prompt: args.prompt,
                    subagentType: selectedType,
                    context: args.context,
                    fileReferences: args.fileReferences ?? []
                )
            )
            return ColonyToolOutcome(success: true, content: result.content, writes: [])

        default:
            return nil
        }
    }

    private static func renderTodos(_ todos: [ColonyTodo]) -> String {
        if todos.isEmpty { return "(No todos)" }
        return todos.map { todo in
            "[\(todo.status.rawValue)] \(todo.id): \(todo.title)"
        }.joined(separator: "\n")
    }

    private static func formatWithLineNumbers(text: String, offset: Int, limit: Int) -> String {
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

    private static func formatShellResult(_ result: ColonyShellExecutionResult) -> String {
        var sections: [String] = ["exit_code: \(result.exitCode)"]
        if result.stdout.isEmpty == false {
            sections.append("stdout:\n\(result.stdout)")
        }
        if result.stderr.isEmpty == false {
            sections.append("stderr:\n\(result.stderr)")
        }
        if result.wasTruncated {
            sections.append("warning: output truncated")
        }
        return sections.joined(separator: "\n\n")
    }

    private static func decode<T: Decodable>(
        _ json: String,
        as type: T.Type,
        defaultingToEmptyObject: Bool = false
    ) throws -> T {
        let trimmed = json.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty, defaultingToEmptyObject {
            return try JSONDecoder().decode(T.self, from: Data("{}".utf8))
        }
        guard let data = trimmed.data(using: .utf8) else {
            throw ColonyToolDecodeError.invalidUTF8
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
}

enum ColonyToolDecodeError: Error, Sendable {
    case invalidUTF8
}

private struct WriteTodosArgs: Decodable, Sendable {
    let todos: [ColonyTodo]
}

private struct LSArgs: Decodable, Sendable {
    let path: String?
}

private struct ReadFileArgs: Decodable, Sendable {
    let path: String
    let offset: Int?
    let limit: Int?
}

private struct WriteFileArgs: Decodable, Sendable {
    let path: String
    let content: String
}

private struct EditFileArgs: Decodable, Sendable {
    let path: String
    let oldString: String
    let newString: String
    let replaceAll: Bool?

    private enum CodingKeys: String, CodingKey {
        case path
        case oldString = "old_string"
        case newString = "new_string"
        case replaceAll = "replace_all"
    }
}

private struct GlobArgs: Decodable, Sendable {
    let pattern: String
}

private struct GrepArgs: Decodable, Sendable {
    let pattern: String
    let glob: String?
}

private struct ExecuteArgs: Decodable, Sendable {
    let command: String
    let cwd: String?
    let timeoutMilliseconds: Int?

    private enum CodingKeys: String, CodingKey {
        case command
        case cwd
        case timeoutMilliseconds = "timeout_ms"
    }
}

private struct TaskArgs: Decodable, Sendable {
    let prompt: String
    let subagentType: String?
    let context: ColonySubagentContext?
    let fileReferences: [ColonySubagentFileReference]?

    private enum CodingKeys: String, CodingKey {
        case prompt
        case subagentType = "subagent_type"
        case context
        case fileReferences = "file_references"
    }
}
