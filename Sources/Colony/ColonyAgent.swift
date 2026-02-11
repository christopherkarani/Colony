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
    public let git: (any ColonyGitBackend)?
    public let lsp: (any ColonyLSPBackend)?
    public let applyPatch: (any ColonyApplyPatchBackend)?
    public let webSearch: (any ColonyWebSearchBackend)?
    public let codeSearch: (any ColonyCodeSearchBackend)?
    public let mcp: (any ColonyMCPBackend)?
    public let memory: (any ColonyMemoryBackend)?
    public let plugins: (any ColonyPluginToolRegistry)?
    public let subagents: (any ColonySubagentRegistry)?
    public let tokenizer: any ColonyTokenizer

    public init(
        configuration: ColonyConfiguration,
        filesystem: (any ColonyFileSystemBackend)?,
        shell: (any ColonyShellBackend)? = nil,
        git: (any ColonyGitBackend)? = nil,
        lsp: (any ColonyLSPBackend)? = nil,
        applyPatch: (any ColonyApplyPatchBackend)? = nil,
        webSearch: (any ColonyWebSearchBackend)? = nil,
        codeSearch: (any ColonyCodeSearchBackend)? = nil,
        mcp: (any ColonyMCPBackend)? = nil,
        memory: (any ColonyMemoryBackend)? = nil,
        plugins: (any ColonyPluginToolRegistry)? = nil,
        subagents: (any ColonySubagentRegistry)? = nil,
        tokenizer: any ColonyTokenizer = ColonyApproximateTokenizer()
    ) {
        self.configuration = configuration
        self.filesystem = filesystem
        self.shell = shell
        self.git = git
        self.lsp = lsp
        self.applyPatch = applyPatch
        self.webSearch = webSearch
        self.codeSearch = codeSearch
        self.mcp = mcp
        self.memory = memory
        self.plugins = plugins
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
                scratchbookEnabled: input.context.configuration.capabilities.contains(.scratchbook),
                scratchbookPolicy: input.context.configuration.scratchbookPolicy,
                subagentsAllowed: input.context.configuration.capabilities.contains(.subagents),
                subagents: input.context.subagents,
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
        let scratchbook: String?
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

            if input.context.configuration.capabilities.contains(.scratchbook) {
                scratchbook = try await loadScratchbookView(
                    policy: input.context.configuration.scratchbookPolicy,
                    filesystem: filesystem,
                    threadID: input.run.threadID
                )
            } else {
                scratchbook = nil
            }
        } else {
            memory = nil
            skills = nil
            scratchbook = nil
        }

        let toolsForPrompt = input.context.configuration.includeToolListInSystemPrompt ? tools : []
        let systemPrompt = ColonyPrompts.systemPrompt(
            additional: input.context.configuration.additionalSystemPrompt,
            memory: memory,
            skills: skills,
            scratchbook: scratchbook,
            availableTools: toolsForPrompt
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
            // Our tokenizer is an approximation (chars/4) over the *combined* request payload. When we subtract
            // tool-definition tokens and then bound messages independently, integer division rounding can carry
            // and exceed the hard cap by ~1 token. Subtract an additional 1 token as conservative padding.
            messageTokenLimit = max(1, hardLimit - toolTokenCount - 1)
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

        let safety = ColonyToolSafetyPolicyEngine(
            approvalPolicy: input.context.configuration.toolApprovalPolicy,
            riskLevelOverrides: input.context.configuration.toolRiskLevelOverrides,
            mandatoryApprovalRiskLevels: input.context.configuration.mandatoryApprovalRiskLevels,
            defaultRiskLevel: input.context.configuration.defaultToolRiskLevel
        )
        let assessments = safety.assess(toolCalls: calls)
        let assessmentsByCallID = Dictionary(uniqueKeysWithValues: assessments.map { ($0.toolCallID, $0) })
        let persistedRuleDecisions = try await resolvePersistedRuleDecisions(
            calls: calls,
            assessmentsByCallID: assessmentsByCallID,
            store: input.context.configuration.toolApprovalRuleStore
        )

        var preApprovedIDs: Set<String> = []
        var preDeniedIDs: Set<String> = []
        preApprovedIDs.reserveCapacity(calls.count)
        preDeniedIDs.reserveCapacity(calls.count)

        for call in calls {
            if let persisted = persistedRuleDecisions[call.id] {
                switch persisted {
                case .allowOnce, .allowAlways:
                    preApprovedIDs.insert(call.id)
                case .rejectAlways:
                    preDeniedIDs.insert(call.id)
                }
                continue
            }

            let requiresApproval = assessmentsByCallID[call.id]?.requiresApproval == true
            if requiresApproval == false {
                preApprovedIDs.insert(call.id)
            }
        }

        let approvalRequiredCalls = calls.filter {
            assessmentsByCallID[$0.id]?.requiresApproval == true
                && preApprovedIDs.contains($0.id) == false
                && preDeniedIDs.contains($0.id) == false
        }
        let approvalRequiredIDs = Set(approvalRequiredCalls.map(\.id))

        if approvalRequiredCalls.isEmpty == false {
            if let resume = input.run.resume, case let .toolApproval(decision) = resume.payload {
                var approvedIDs = preApprovedIDs
                var deniedIDs = preDeniedIDs
                approvedIDs.reserveCapacity(calls.count)
                deniedIDs.reserveCapacity(calls.count)

                for call in approvalRequiredCalls {
                    if decision.decision(forToolCallID: call.id) == .approved {
                        approvedIDs.insert(call.id)
                    } else {
                        deniedIDs.insert(call.id)
                    }
                }

                let approvedCalls = calls.filter { approvedIDs.contains($0.id) }
                let deniedCalls = calls.filter { deniedIDs.contains($0.id) }

                try await recordToolAuditEvents(
                    calls: calls.filter { approvedIDs.contains($0.id) && approvalRequiredIDs.contains($0.id) == false },
                    decision: .autoApproved,
                    assessmentsByCallID: assessmentsByCallID,
                    input: input
                )
                try await recordToolAuditEvents(
                    calls: approvalRequiredCalls.filter { approvedIDs.contains($0.id) },
                    decision: .userApproved,
                    assessmentsByCallID: assessmentsByCallID,
                    input: input
                )
                try await recordToolAuditEvents(
                    calls: deniedCalls,
                    decision: .userDenied,
                    assessmentsByCallID: assessmentsByCallID,
                    input: input
                )

                return try toolDispatchPath(
                    input: input,
                    approvedCalls: approvedCalls,
                    deniedCalls: deniedCalls,
                    taskID: input.run.taskID
                )
            }

            try await recordToolAuditEvents(
                calls: calls.filter { preApprovedIDs.contains($0.id) },
                decision: .autoApproved,
                assessmentsByCallID: assessmentsByCallID,
                input: input
            )
            try await recordToolAuditEvents(
                calls: calls.filter { preDeniedIDs.contains($0.id) },
                decision: .userDenied,
                assessmentsByCallID: assessmentsByCallID,
                input: input
            )

            try await recordToolAuditEvents(
                calls: approvalRequiredCalls,
                decision: .approvalRequired,
                assessmentsByCallID: assessmentsByCallID,
                input: input
            )

            return HiveNodeOutput(
                next: .nodes([nodeTools]),
                interrupt: HiveInterruptRequest(payload: .toolApprovalRequired(toolCalls: approvalRequiredCalls))
            )
        }

        let approvedCalls = calls.filter { preDeniedIDs.contains($0.id) == false }
        let deniedCalls = calls.filter { preDeniedIDs.contains($0.id) }
        try await recordToolAuditEvents(
            calls: approvedCalls,
            decision: .autoApproved,
            assessmentsByCallID: assessmentsByCallID,
            input: input
        )
        try await recordToolAuditEvents(
            calls: deniedCalls,
            decision: .userDenied,
            assessmentsByCallID: assessmentsByCallID,
            input: input
        )
        return try toolDispatchPath(
            input: input,
            approvedCalls: approvedCalls,
            deniedCalls: deniedCalls,
            taskID: input.run.taskID
        )
    }

    private static func toolDispatchPath(
        input: HiveNodeInput<ColonySchema>,
        approvedCalls: [HiveToolCall],
        deniedCalls: [HiveToolCall],
        taskID: HiveTaskID
    ) throws -> HiveNodeOutput<ColonySchema> {
        var spawn: [HiveTaskSeed<ColonySchema>] = []
        spawn.reserveCapacity(approvedCalls.count)
        for call in approvedCalls {
            var local = HiveTaskLocalStore<ColonySchema>.empty
            try local.set(ColonySchema.Channels.currentToolCall, call)
            spawn.append(HiveTaskSeed(nodeID: nodeToolExecute, local: local))
        }

        var writes: [AnyHiveWrite<ColonySchema>] = [
            AnyHiveWrite(ColonySchema.Channels.pendingToolCalls, []),
        ]

        if deniedCalls.isEmpty == false {
            let messageID = ColonyMessageID.systemMessageID(taskID: taskID)
            let system = HiveChatMessage(
                id: messageID,
                role: .system,
                content: "Tool execution rejected by user."
            )

            let cancellations = deniedCalls.map { call in
                HiveChatMessage(
                    id: "tool:" + call.id,
                    role: .tool,
                    content: "Tool call \(call.name) with id \(call.id) was cancelled - tool execution was rejected by the user.",
                    name: call.name,
                    toolCallID: call.id
                )
            }
            writes.append(
                AnyHiveWrite(ColonySchema.Channels.messages, [system] + cancellations)
            )
        }

        if spawn.isEmpty {
            return HiveNodeOutput(
                writes: writes,
                next: .nodes([nodePreModel])
            )
        }

        return HiveNodeOutput(
            writes: writes,
            spawn: spawn,
            next: .end
        )
    }

    private static func recordToolAuditEvents(
        calls: [HiveToolCall],
        decision: ColonyToolAuditDecisionKind,
        assessmentsByCallID: [String: ColonyToolSafetyAssessment],
        input: HiveNodeInput<ColonySchema>
    ) async throws {
        guard calls.isEmpty == false else { return }
        guard let recorder = input.context.configuration.toolAuditRecorder else { return }

        for call in calls {
            guard let assessment = assessmentsByCallID[call.id] else { continue }
            let event = ColonyToolAuditEvent(
                timestampNanoseconds: input.environment.clock.nowNanoseconds(),
                threadID: input.run.threadID.rawValue,
                taskID: input.run.taskID.rawValue,
                toolCallID: call.id,
                toolName: call.name,
                riskLevel: assessment.riskLevel,
                decision: decision,
                reason: assessment.reason
            )
            try await recorder.record(event: event)
        }
    }

    private static func resolvePersistedRuleDecisions(
        calls: [HiveToolCall],
        assessmentsByCallID: [String: ColonyToolSafetyAssessment],
        store: (any ColonyToolApprovalRuleStore)?
    ) async throws -> [String: ColonyToolApprovalRuleDecision] {
        guard let store else {
            return [:]
        }

        var decisions: [String: ColonyToolApprovalRuleDecision] = [:]
        decisions.reserveCapacity(calls.count)

        for call in calls {
            guard assessmentsByCallID[call.id]?.requiresApproval == true else { continue }
            if let resolved = try await store.resolveDecision(forToolName: call.name, consumeOneShot: true) {
                decisions[call.id] = resolved.decision
            }
        }
        return decisions
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
            if context.configuration.capabilities.contains(.shellSessions) {
                tools.append(contentsOf: [
                    ColonyBuiltInToolDefinitions.shellOpen,
                    ColonyBuiltInToolDefinitions.shellWrite,
                    ColonyBuiltInToolDefinitions.shellRead,
                    ColonyBuiltInToolDefinitions.shellClose,
                ])
            }
        }

        if context.configuration.capabilities.contains(.git), context.git != nil {
            tools.append(contentsOf: [
                ColonyBuiltInToolDefinitions.gitStatus,
                ColonyBuiltInToolDefinitions.gitDiff,
                ColonyBuiltInToolDefinitions.gitCommit,
                ColonyBuiltInToolDefinitions.gitBranch,
                ColonyBuiltInToolDefinitions.gitPush,
                ColonyBuiltInToolDefinitions.gitPreparePR,
            ])
        }

        if context.configuration.capabilities.contains(.lsp), context.lsp != nil {
            tools.append(contentsOf: [
                ColonyBuiltInToolDefinitions.lspSymbols,
                ColonyBuiltInToolDefinitions.lspDiagnostics,
                ColonyBuiltInToolDefinitions.lspReferences,
                ColonyBuiltInToolDefinitions.lspApplyEdit,
            ])
        }

        if context.configuration.capabilities.contains(.applyPatch), context.applyPatch != nil {
            tools.append(ColonyBuiltInToolDefinitions.applyPatch)
        }

        if context.configuration.capabilities.contains(.webSearch), context.webSearch != nil {
            tools.append(ColonyBuiltInToolDefinitions.webSearch)
        }

        if context.configuration.capabilities.contains(.codeSearch), context.codeSearch != nil {
            tools.append(ColonyBuiltInToolDefinitions.codeSearch)
        }

        if context.configuration.capabilities.contains(.memory), context.memory != nil {
            tools.append(contentsOf: [
                ColonyBuiltInToolDefinitions.memoryRecall,
                ColonyBuiltInToolDefinitions.memoryRemember,
            ])
        }

        if context.configuration.capabilities.contains(.mcp), context.mcp != nil {
            tools.append(contentsOf: [
                ColonyBuiltInToolDefinitions.mcpListResources,
                ColonyBuiltInToolDefinitions.mcpReadResource,
            ])
        }

        if context.configuration.capabilities.contains(.plugins), context.plugins != nil {
            tools.append(contentsOf: [
                ColonyBuiltInToolDefinitions.pluginListTools,
                ColonyBuiltInToolDefinitions.pluginInvoke,
            ])
        }

        if context.configuration.capabilities.contains(.scratchbook), context.filesystem != nil {
            tools.append(contentsOf: [
                ColonyBuiltInToolDefinitions.scratchRead,
                ColonyBuiltInToolDefinitions.scratchAdd,
                ColonyBuiltInToolDefinitions.scratchUpdate,
                ColonyBuiltInToolDefinitions.scratchComplete,
                ColonyBuiltInToolDefinitions.scratchPin,
                ColonyBuiltInToolDefinitions.scratchUnpin,
            ])
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
        scratchbookEnabled: Bool,
        scratchbookPolicy: ColonyScratchbookPolicy,
        subagentsAllowed: Bool,
        subagents: (any ColonySubagentRegistry)?,
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

        if scratchbookEnabled {
            do {
                try await updateScratchbookForHistoryOffload(
                    filesystem: filesystem,
                    threadID: threadID,
                    policy: scratchbookPolicy,
                    historyPath: historyPath
                )
            } catch {
                // Best-effort; never fail the agent run due to Scratchbook persistence.
            }
        }

        if scratchbookEnabled,
           subagentsAllowed,
           let subagents,
           subagents.listSubagents().contains(where: { $0.name == "compactor" })
        {
            do {
                let scratchbookPath = try ColonyScratchbookStore.path(
                    threadID: threadID.rawValue,
                    policy: scratchbookPolicy
                )

                let prompt = """
                Conversation history was offloaded to: \(historyPath.rawValue)

                Update the Scratchbook at: \(scratchbookPath.rawValue)
                - Add or update a concise summary note that references the offloaded history path.
                - Add at least one concrete next action as a todo/task item.
                - Keep updates compact and on-device friendly.
                """

                _ = try await subagents.run(
                    ColonySubagentRequest(
                        prompt: prompt,
                        subagentType: "compactor"
                    )
                )
            } catch {
                // Best-effort; do not fail summarization if the compactor cannot run.
            }
        }

        let summaryMessage = HiveChatMessage(
            id: "system:summary:" + threadSlug,
            role: .system,
            content: "Note: conversation has been summarized. Full prior history is available at \(historyPath.rawValue)."
        )

        return [summaryMessage] + tail
    }

    private static let historyOffloadSummaryItemID: String = "history_offload:summary"
    private static let historyOffloadNextActionsItemID: String = "history_offload:next_actions"

    private static func updateScratchbookForHistoryOffload(
        filesystem: any ColonyFileSystemBackend,
        threadID: HiveThreadID,
        policy: ColonyScratchbookPolicy,
        historyPath: ColonyVirtualPath
    ) async throws {
        let scratchbook = try await ColonyScratchbookStore.load(
            filesystem: filesystem,
            threadID: threadID.rawValue,
            policy: policy
        )

        let retained = scratchbook.items.filter { item in
            item.id != historyOffloadSummaryItemID && item.id != historyOffloadNextActionsItemID
        }

        let summary = ColonyScratchItem(
            id: historyOffloadSummaryItemID,
            kind: .note,
            status: .open,
            title: "History offloaded: \(historyPath.rawValue)",
            body: "Conversation history was offloaded to \(historyPath.rawValue).",
            tags: ["history_offload"],
            createdAtNanoseconds: 0,
            updatedAtNanoseconds: 0
        )

        let nextActions = ColonyScratchItem(
            id: historyOffloadNextActionsItemID,
            kind: .todo,
            status: .open,
            title: "Next actions (see \(historyPath.rawValue))",
            body: """
            Next actions:
            - Next action: Review \(historyPath.rawValue)
            - Next action: Update Scratchbook tasks/todos for the current objective
            """,
            tags: ["next_action"],
            createdAtNanoseconds: 0,
            updatedAtNanoseconds: 0
        )

        let updated = ColonyScratchbook(
            items: retained + [summary, nextActions],
            pinnedItemIDs: scratchbook.pinnedItemIDs
        )

        try await ColonyScratchbookStore.save(
            updated,
            filesystem: filesystem,
            threadID: threadID.rawValue,
            policy: policy
        )
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

    private static func loadScratchbookView(
        policy: ColonyScratchbookPolicy,
        filesystem: any ColonyFileSystemBackend,
        threadID: HiveThreadID
    ) async throws -> String? {
        let scratchbook = try await ColonyScratchbookStore.load(
            filesystem: filesystem,
            threadID: threadID.rawValue,
            policy: policy
        )
        let view = scratchbook.renderView(policy: policy)

        let trimmed = view.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
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

        let preview = createContentPreview(content, maxChars: threshold)
        return """
Tool result too large (tool_call_id: \(toolCall.id)).
Full content was written to \(path.rawValue). Read it with read_file using offset/limit.

Preview:
\(preview)
"""
    }

    private static func createContentPreview(
        _ content: String,
        maxChars: Int
    ) -> String {
        guard maxChars > 0 else { return "" }
        guard content.count > maxChars else { return content }

        let ellipsis = "\n...\n"
        if maxChars <= ellipsis.count + 32 {
            return String(content.prefix(maxChars))
        }

        let sampleBudget = max(0, maxChars - ellipsis.count)
        let headBudget = sampleBudget / 2
        let tailBudget = sampleBudget - headBudget

        if headBudget == 0 || tailBudget == 0 {
            return String(content.prefix(maxChars))
        }

        let head = String(content.prefix(headBudget))
        let tail = String(content.suffix(tailBudget))
        let preview = head + ellipsis + tail

        if preview.count <= maxChars { return preview }
        return String(preview.prefix(maxChars))
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

        case ColonyBuiltInToolDefinitions.scratchRead.name:
            guard input.context.configuration.capabilities.contains(.scratchbook) else {
                return ColonyToolOutcome(success: false, content: "Error: Scratchbook capability not enabled.", writes: [])
            }
            guard let fs = input.context.filesystem else {
                return ColonyToolOutcome(success: false, content: "Error: Filesystem not configured.", writes: [])
            }

            let policy = input.context.configuration.scratchbookPolicy
            let scratchbook = try await ColonyScratchbookStore.load(
                filesystem: fs,
                threadID: input.run.threadID.rawValue,
                policy: policy
            )
            let view = scratchbook.renderView(policy: policy)
            return ColonyToolOutcome(success: true, content: view, writes: [])

        case ColonyBuiltInToolDefinitions.scratchAdd.name:
            guard input.context.configuration.capabilities.contains(.scratchbook) else {
                return ColonyToolOutcome(success: false, content: "Error: Scratchbook capability not enabled.", writes: [])
            }
            guard let fs = input.context.filesystem else {
                return ColonyToolOutcome(success: false, content: "Error: Filesystem not configured.", writes: [])
            }

            let args = try decode(call.argumentsJSON, as: ScratchAddArgs.self)
            let policy = input.context.configuration.scratchbookPolicy
            let scratchbook = try await ColonyScratchbookStore.load(
                filesystem: fs,
                threadID: input.run.threadID.rawValue,
                policy: policy
            )
            let existingIDs = Set(scratchbook.items.map(\.id))
            let itemID = newScratchItemID(toolCallID: call.id, existing: existingIDs)

            let now = input.environment.clock.nowNanoseconds()
            let item = ColonyScratchItem(
                id: itemID,
                kind: args.kind,
                status: .open,
                title: args.title,
                body: args.body ?? "",
                tags: args.tags ?? [],
                createdAtNanoseconds: now,
                updatedAtNanoseconds: now,
                phase: args.phase,
                progress: args.progress
            )
            let updatedScratchbook = ColonyScratchbook(
                items: scratchbook.items + [item],
                pinnedItemIDs: scratchbook.pinnedItemIDs
            )
            try await ColonyScratchbookStore.save(
                updatedScratchbook,
                filesystem: fs,
                threadID: input.run.threadID.rawValue,
                policy: policy
            )
            return ColonyToolOutcome(success: true, content: "OK: added \(itemID)", writes: [])

        case ColonyBuiltInToolDefinitions.scratchUpdate.name:
            guard input.context.configuration.capabilities.contains(.scratchbook) else {
                return ColonyToolOutcome(success: false, content: "Error: Scratchbook capability not enabled.", writes: [])
            }
            guard let fs = input.context.filesystem else {
                return ColonyToolOutcome(success: false, content: "Error: Filesystem not configured.", writes: [])
            }

            let args = try decode(call.argumentsJSON, as: ScratchUpdateArgs.self)
            let policy = input.context.configuration.scratchbookPolicy
            let scratchbook = try await ColonyScratchbookStore.load(
                filesystem: fs,
                threadID: input.run.threadID.rawValue,
                policy: policy
            )
            guard let existing = scratchbook.items.first(where: { $0.id == args.id }) else {
                return ColonyToolOutcome(success: false, content: "Error: Scratchbook item not found: \(args.id)", writes: [])
            }

            let now = input.environment.clock.nowNanoseconds()
            let updatedItem = ColonyScratchItem(
                id: existing.id,
                kind: existing.kind,
                status: args.status ?? existing.status,
                title: args.title ?? existing.title,
                body: args.body ?? existing.body,
                tags: args.tags ?? existing.tags,
                createdAtNanoseconds: existing.createdAtNanoseconds,
                updatedAtNanoseconds: now,
                phase: args.phase ?? existing.phase,
                progress: args.progress ?? existing.progress
            )

            let updatedItems = scratchbook.items.map { item in
                (item.id == args.id) ? updatedItem : item
            }
            let updatedScratchbook = ColonyScratchbook(items: updatedItems, pinnedItemIDs: scratchbook.pinnedItemIDs)
            try await ColonyScratchbookStore.save(
                updatedScratchbook,
                filesystem: fs,
                threadID: input.run.threadID.rawValue,
                policy: policy
            )
            return ColonyToolOutcome(success: true, content: "OK: updated \(args.id)", writes: [])

        case ColonyBuiltInToolDefinitions.scratchComplete.name:
            guard input.context.configuration.capabilities.contains(.scratchbook) else {
                return ColonyToolOutcome(success: false, content: "Error: Scratchbook capability not enabled.", writes: [])
            }
            guard let fs = input.context.filesystem else {
                return ColonyToolOutcome(success: false, content: "Error: Filesystem not configured.", writes: [])
            }

            let args = try decode(call.argumentsJSON, as: ScratchIDArgs.self)
            let policy = input.context.configuration.scratchbookPolicy
            let scratchbook = try await ColonyScratchbookStore.load(
                filesystem: fs,
                threadID: input.run.threadID.rawValue,
                policy: policy
            )
            guard let existing = scratchbook.items.first(where: { $0.id == args.id }) else {
                return ColonyToolOutcome(success: false, content: "Error: Scratchbook item not found: \(args.id)", writes: [])
            }

            let now = input.environment.clock.nowNanoseconds()
            let completed = ColonyScratchItem(
                id: existing.id,
                kind: existing.kind,
                status: .done,
                title: existing.title,
                body: existing.body,
                tags: existing.tags,
                createdAtNanoseconds: existing.createdAtNanoseconds,
                updatedAtNanoseconds: now,
                phase: existing.phase,
                progress: existing.progress
            )
            let updatedItems = scratchbook.items.map { item in
                (item.id == args.id) ? completed : item
            }
            let updatedScratchbook = ColonyScratchbook(items: updatedItems, pinnedItemIDs: scratchbook.pinnedItemIDs)
            try await ColonyScratchbookStore.save(
                updatedScratchbook,
                filesystem: fs,
                threadID: input.run.threadID.rawValue,
                policy: policy
            )
            return ColonyToolOutcome(success: true, content: "OK: completed \(args.id)", writes: [])

        case ColonyBuiltInToolDefinitions.scratchPin.name:
            guard input.context.configuration.capabilities.contains(.scratchbook) else {
                return ColonyToolOutcome(success: false, content: "Error: Scratchbook capability not enabled.", writes: [])
            }
            guard let fs = input.context.filesystem else {
                return ColonyToolOutcome(success: false, content: "Error: Filesystem not configured.", writes: [])
            }

            let args = try decode(call.argumentsJSON, as: ScratchIDArgs.self)
            let policy = input.context.configuration.scratchbookPolicy
            let scratchbook = try await ColonyScratchbookStore.load(
                filesystem: fs,
                threadID: input.run.threadID.rawValue,
                policy: policy
            )
            guard scratchbook.items.contains(where: { $0.id == args.id }) else {
                return ColonyToolOutcome(success: false, content: "Error: Scratchbook item not found: \(args.id)", writes: [])
            }
            let pinnedIDs = scratchbook.pinnedItemIDs.contains(args.id)
                ? scratchbook.pinnedItemIDs
                : (scratchbook.pinnedItemIDs + [args.id])
            let updatedScratchbook = ColonyScratchbook(items: scratchbook.items, pinnedItemIDs: pinnedIDs)
            try await ColonyScratchbookStore.save(
                updatedScratchbook,
                filesystem: fs,
                threadID: input.run.threadID.rawValue,
                policy: policy
            )
            return ColonyToolOutcome(success: true, content: "OK: pinned \(args.id)", writes: [])

        case ColonyBuiltInToolDefinitions.scratchUnpin.name:
            guard input.context.configuration.capabilities.contains(.scratchbook) else {
                return ColonyToolOutcome(success: false, content: "Error: Scratchbook capability not enabled.", writes: [])
            }
            guard let fs = input.context.filesystem else {
                return ColonyToolOutcome(success: false, content: "Error: Filesystem not configured.", writes: [])
            }

            let args = try decode(call.argumentsJSON, as: ScratchIDArgs.self)
            let policy = input.context.configuration.scratchbookPolicy
            let scratchbook = try await ColonyScratchbookStore.load(
                filesystem: fs,
                threadID: input.run.threadID.rawValue,
                policy: policy
            )
            let pinnedIDs = scratchbook.pinnedItemIDs.filter { $0 != args.id }
            let updatedScratchbook = ColonyScratchbook(items: scratchbook.items, pinnedItemIDs: pinnedIDs)
            try await ColonyScratchbookStore.save(
                updatedScratchbook,
                filesystem: fs,
                threadID: input.run.threadID.rawValue,
                policy: policy
            )
            return ColonyToolOutcome(success: true, content: "OK: unpinned \(args.id)", writes: [])

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

        case ColonyBuiltInToolDefinitions.shellOpen.name:
            guard input.context.configuration.capabilities.contains(.shellSessions) else {
                return ColonyToolOutcome(success: false, content: "Error: Shell sessions capability not enabled.", writes: [])
            }
            guard let shell = input.context.shell else {
                return ColonyToolOutcome(success: false, content: "Error: Shell backend not configured.", writes: [])
            }
            let args = try decode(call.argumentsJSON, as: ShellOpenArgs.self)
            let cwd = try virtualPath(from: args.cwd)
            let idleTimeout = args.idleTimeoutMilliseconds.map { UInt64(max(0, $0)) * 1_000_000 }
            let sessionID = try await shell.openSession(
                ColonyShellSessionOpenRequest(
                    command: args.command,
                    workingDirectory: cwd,
                    idleTimeoutNanoseconds: idleTimeout
                )
            )
            return ColonyToolOutcome(
                success: true,
                content: "session_id: \(sessionID.rawValue)",
                writes: []
            )

        case ColonyBuiltInToolDefinitions.shellWrite.name:
            guard input.context.configuration.capabilities.contains(.shellSessions) else {
                return ColonyToolOutcome(success: false, content: "Error: Shell sessions capability not enabled.", writes: [])
            }
            guard let shell = input.context.shell else {
                return ColonyToolOutcome(success: false, content: "Error: Shell backend not configured.", writes: [])
            }
            let args = try decode(call.argumentsJSON, as: ShellWriteArgs.self)
            try await shell.writeToSession(
                ColonyShellSessionID(rawValue: args.sessionID),
                data: Data(args.input.utf8)
            )
            return ColonyToolOutcome(success: true, content: "OK: wrote to \(args.sessionID)", writes: [])

        case ColonyBuiltInToolDefinitions.shellRead.name:
            guard input.context.configuration.capabilities.contains(.shellSessions) else {
                return ColonyToolOutcome(success: false, content: "Error: Shell sessions capability not enabled.", writes: [])
            }
            guard let shell = input.context.shell else {
                return ColonyToolOutcome(success: false, content: "Error: Shell backend not configured.", writes: [])
            }
            let args = try decode(call.argumentsJSON, as: ShellReadArgs.self)
            let timeout = args.timeoutMilliseconds.map { UInt64(max(0, $0)) * 1_000_000 }
            let result = try await shell.readFromSession(
                ColonyShellSessionID(rawValue: args.sessionID),
                maxBytes: max(1, args.maxBytes ?? 4_096),
                timeoutNanoseconds: timeout
            )
            return ColonyToolOutcome(success: true, content: formatShellSessionReadResult(result), writes: [])

        case ColonyBuiltInToolDefinitions.shellClose.name:
            guard input.context.configuration.capabilities.contains(.shellSessions) else {
                return ColonyToolOutcome(success: false, content: "Error: Shell sessions capability not enabled.", writes: [])
            }
            guard let shell = input.context.shell else {
                return ColonyToolOutcome(success: false, content: "Error: Shell backend not configured.", writes: [])
            }
            let args = try decode(call.argumentsJSON, as: ShellCloseArgs.self)
            await shell.closeSession(ColonyShellSessionID(rawValue: args.sessionID))
            return ColonyToolOutcome(success: true, content: "OK: closed \(args.sessionID)", writes: [])

        case ColonyBuiltInToolDefinitions.applyPatch.name:
            guard input.context.configuration.capabilities.contains(.applyPatch) else {
                return ColonyToolOutcome(success: false, content: "Error: apply_patch capability not enabled.", writes: [])
            }
            guard let backend = input.context.applyPatch else {
                return ColonyToolOutcome(success: false, content: "Error: apply_patch backend not configured.", writes: [])
            }
            let args = try decode(call.argumentsJSON, as: ApplyPatchArgs.self)
            let result = try await backend.applyPatch(args.patch)
            return ColonyToolOutcome(success: result.success, content: result.summary, writes: [])

        case ColonyBuiltInToolDefinitions.webSearch.name:
            guard input.context.configuration.capabilities.contains(.webSearch) else {
                return ColonyToolOutcome(success: false, content: "Error: web_search capability not enabled.", writes: [])
            }
            guard let backend = input.context.webSearch else {
                return ColonyToolOutcome(success: false, content: "Error: web_search backend not configured.", writes: [])
            }
            let args = try decode(call.argumentsJSON, as: WebSearchArgs.self)
            let result = try await backend.search(query: args.query, limit: args.limit)
            let lines = result.items.map { "\($0.title)\n\($0.url)\n\($0.snippet)" }
            return ColonyToolOutcome(success: true, content: lines.joined(separator: "\n\n"), writes: [])

        case ColonyBuiltInToolDefinitions.codeSearch.name:
            guard input.context.configuration.capabilities.contains(.codeSearch) else {
                return ColonyToolOutcome(success: false, content: "Error: code_search capability not enabled.", writes: [])
            }
            guard let backend = input.context.codeSearch else {
                return ColonyToolOutcome(success: false, content: "Error: code_search backend not configured.", writes: [])
            }
            let args = try decode(call.argumentsJSON, as: CodeSearchArgs.self)
            let result = try await backend.search(query: args.query, path: try virtualPath(from: args.path))
            let lines = result.matches.map { "\($0.path.rawValue):\($0.line): \($0.preview)" }
            return ColonyToolOutcome(success: true, content: lines.joined(separator: "\n"), writes: [])

        case ColonyBuiltInToolDefinitions.memoryRecall.name:
            guard input.context.configuration.capabilities.contains(.memory) else {
                return ColonyToolOutcome(success: false, content: "Error: memory capability not enabled.", writes: [])
            }
            guard let backend = input.context.memory else {
                return ColonyToolOutcome(success: false, content: "Error: memory backend not configured.", writes: [])
            }
            let args = try decode(call.argumentsJSON, as: MemoryRecallArgs.self)
            let result = try await backend.recall(
                ColonyMemoryRecallRequest(
                    query: args.query,
                    limit: args.limit
                )
            )
            return ColonyToolOutcome(success: true, content: formatMemoryRecallResult(result), writes: [])

        case ColonyBuiltInToolDefinitions.memoryRemember.name:
            guard input.context.configuration.capabilities.contains(.memory) else {
                return ColonyToolOutcome(success: false, content: "Error: memory capability not enabled.", writes: [])
            }
            guard let backend = input.context.memory else {
                return ColonyToolOutcome(success: false, content: "Error: memory backend not configured.", writes: [])
            }
            let args = try decode(call.argumentsJSON, as: MemoryRememberArgs.self)
            let result = try await backend.remember(
                ColonyMemoryRememberRequest(
                    content: args.content,
                    tags: args.tags ?? [],
                    metadata: args.metadata ?? [:]
                )
            )
            return ColonyToolOutcome(success: true, content: formatMemoryRememberResult(result), writes: [])

        case ColonyBuiltInToolDefinitions.mcpListResources.name:
            guard input.context.configuration.capabilities.contains(.mcp) else {
                return ColonyToolOutcome(success: false, content: "Error: MCP capability not enabled.", writes: [])
            }
            guard let backend = input.context.mcp else {
                return ColonyToolOutcome(success: false, content: "Error: MCP backend not configured.", writes: [])
            }
            let resources = try await backend.listResources()
            let lines = resources.map { resource in
                if let description = resource.description, description.isEmpty == false {
                    return "\(resource.id)\t\(resource.name)\t\(description)"
                }
                return "\(resource.id)\t\(resource.name)"
            }
            return ColonyToolOutcome(success: true, content: lines.joined(separator: "\n"), writes: [])

        case ColonyBuiltInToolDefinitions.mcpReadResource.name:
            guard input.context.configuration.capabilities.contains(.mcp) else {
                return ColonyToolOutcome(success: false, content: "Error: MCP capability not enabled.", writes: [])
            }
            guard let backend = input.context.mcp else {
                return ColonyToolOutcome(success: false, content: "Error: MCP backend not configured.", writes: [])
            }
            let args = try decode(call.argumentsJSON, as: MCPReadResourceArgs.self)
            let content = try await backend.readResource(id: args.resourceID)
            return ColonyToolOutcome(success: true, content: content, writes: [])

        case ColonyBuiltInToolDefinitions.pluginListTools.name:
            guard input.context.configuration.capabilities.contains(.plugins) else {
                return ColonyToolOutcome(success: false, content: "Error: plugins capability not enabled.", writes: [])
            }
            guard let plugins = input.context.plugins else {
                return ColonyToolOutcome(success: false, content: "Error: plugin registry not configured.", writes: [])
            }
            let tools = plugins.listTools()
            let lines = tools.map { "\($0.name): \($0.description)" }
            return ColonyToolOutcome(success: true, content: lines.joined(separator: "\n"), writes: [])

        case ColonyBuiltInToolDefinitions.pluginInvoke.name:
            guard input.context.configuration.capabilities.contains(.plugins) else {
                return ColonyToolOutcome(success: false, content: "Error: plugins capability not enabled.", writes: [])
            }
            guard let plugins = input.context.plugins else {
                return ColonyToolOutcome(success: false, content: "Error: plugin registry not configured.", writes: [])
            }
            let args = try decode(call.argumentsJSON, as: PluginInvokeArgs.self)
            let output = try await plugins.invoke(name: args.name, argumentsJSON: args.argumentsJSON)
            return ColonyToolOutcome(success: true, content: output, writes: [])

        case ColonyBuiltInToolDefinitions.gitStatus.name:
            guard input.context.configuration.capabilities.contains(.git) else {
                return ColonyToolOutcome(success: false, content: "Error: Git capability not enabled.", writes: [])
            }
            guard let git = input.context.git else {
                return ColonyToolOutcome(success: false, content: "Error: Git backend not configured.", writes: [])
            }
            let args = try decode(call.argumentsJSON, as: GitStatusArgs.self, defaultingToEmptyObject: true)
            let request = ColonyGitStatusRequest(
                repositoryPath: try virtualPath(from: args.repoPath),
                includeUntracked: args.includeUntracked ?? true
            )
            let result = try await git.status(request)
            return ColonyToolOutcome(success: true, content: formatGitStatusResult(result), writes: [])

        case ColonyBuiltInToolDefinitions.gitDiff.name:
            guard input.context.configuration.capabilities.contains(.git) else {
                return ColonyToolOutcome(success: false, content: "Error: Git capability not enabled.", writes: [])
            }
            guard let git = input.context.git else {
                return ColonyToolOutcome(success: false, content: "Error: Git backend not configured.", writes: [])
            }
            let args = try decode(call.argumentsJSON, as: GitDiffArgs.self, defaultingToEmptyObject: true)
            let request = ColonyGitDiffRequest(
                repositoryPath: try virtualPath(from: args.repoPath),
                baseRef: args.baseRef,
                headRef: args.headRef,
                pathspec: args.pathspec,
                staged: args.staged ?? false
            )
            let result = try await git.diff(request)
            return ColonyToolOutcome(success: true, content: result.patch, writes: [])

        case ColonyBuiltInToolDefinitions.gitCommit.name:
            guard input.context.configuration.capabilities.contains(.git) else {
                return ColonyToolOutcome(success: false, content: "Error: Git capability not enabled.", writes: [])
            }
            guard let git = input.context.git else {
                return ColonyToolOutcome(success: false, content: "Error: Git backend not configured.", writes: [])
            }
            let args = try decode(call.argumentsJSON, as: GitCommitArgs.self)
            let request = ColonyGitCommitRequest(
                repositoryPath: try virtualPath(from: args.repoPath),
                message: args.message,
                includeAll: args.includeAll ?? true,
                amend: args.amend ?? false,
                signoff: args.signoff ?? false
            )
            let result = try await git.commit(request)
            return ColonyToolOutcome(success: true, content: formatGitCommitResult(result), writes: [])

        case ColonyBuiltInToolDefinitions.gitBranch.name:
            guard input.context.configuration.capabilities.contains(.git) else {
                return ColonyToolOutcome(success: false, content: "Error: Git capability not enabled.", writes: [])
            }
            guard let git = input.context.git else {
                return ColonyToolOutcome(success: false, content: "Error: Git backend not configured.", writes: [])
            }
            let args = try decode(call.argumentsJSON, as: GitBranchArgs.self)
            let request = ColonyGitBranchRequest(
                repositoryPath: try virtualPath(from: args.repoPath),
                operation: args.operation,
                name: args.name,
                startPoint: args.startPoint,
                force: args.force ?? false
            )
            let result = try await git.branch(request)
            return ColonyToolOutcome(success: true, content: formatGitBranchResult(result), writes: [])

        case ColonyBuiltInToolDefinitions.gitPush.name:
            guard input.context.configuration.capabilities.contains(.git) else {
                return ColonyToolOutcome(success: false, content: "Error: Git capability not enabled.", writes: [])
            }
            guard let git = input.context.git else {
                return ColonyToolOutcome(success: false, content: "Error: Git backend not configured.", writes: [])
            }
            let args = try decode(call.argumentsJSON, as: GitPushArgs.self, defaultingToEmptyObject: true)
            let request = ColonyGitPushRequest(
                repositoryPath: try virtualPath(from: args.repoPath),
                remote: args.remote ?? "origin",
                branch: args.branch,
                setUpstream: args.setUpstream ?? false,
                forceWithLease: args.forceWithLease ?? false
            )
            let result = try await git.push(request)
            return ColonyToolOutcome(success: true, content: formatGitPushResult(result), writes: [])

        case ColonyBuiltInToolDefinitions.gitPreparePR.name:
            guard input.context.configuration.capabilities.contains(.git) else {
                return ColonyToolOutcome(success: false, content: "Error: Git capability not enabled.", writes: [])
            }
            guard let git = input.context.git else {
                return ColonyToolOutcome(success: false, content: "Error: Git backend not configured.", writes: [])
            }
            let args = try decode(call.argumentsJSON, as: GitPreparePRArgs.self)
            let request = ColonyGitPreparePullRequestRequest(
                repositoryPath: try virtualPath(from: args.repoPath),
                baseBranch: args.baseBranch,
                headBranch: args.headBranch,
                title: args.title,
                body: args.body,
                draft: args.draft ?? false
            )
            let result = try await git.preparePullRequest(request)
            return ColonyToolOutcome(success: true, content: formatGitPreparePRResult(result), writes: [])

        case ColonyBuiltInToolDefinitions.lspSymbols.name:
            guard input.context.configuration.capabilities.contains(.lsp) else {
                return ColonyToolOutcome(success: false, content: "Error: LSP capability not enabled.", writes: [])
            }
            guard let lsp = input.context.lsp else {
                return ColonyToolOutcome(success: false, content: "Error: LSP backend not configured.", writes: [])
            }
            let args = try decode(call.argumentsJSON, as: LSPSymbolsArgs.self, defaultingToEmptyObject: true)
            let request = ColonyLSPSymbolsRequest(
                path: try virtualPath(from: args.path),
                query: args.query
            )
            let symbols = try await lsp.symbols(request)
            return ColonyToolOutcome(success: true, content: formatLSPSymbols(symbols), writes: [])

        case ColonyBuiltInToolDefinitions.lspDiagnostics.name:
            guard input.context.configuration.capabilities.contains(.lsp) else {
                return ColonyToolOutcome(success: false, content: "Error: LSP capability not enabled.", writes: [])
            }
            guard let lsp = input.context.lsp else {
                return ColonyToolOutcome(success: false, content: "Error: LSP backend not configured.", writes: [])
            }
            let args = try decode(call.argumentsJSON, as: LSPDiagnosticsArgs.self, defaultingToEmptyObject: true)
            let request = ColonyLSPDiagnosticsRequest(path: try virtualPath(from: args.path))
            let diagnostics = try await lsp.diagnostics(request)
            return ColonyToolOutcome(success: true, content: formatLSPDiagnostics(diagnostics), writes: [])

        case ColonyBuiltInToolDefinitions.lspReferences.name:
            guard input.context.configuration.capabilities.contains(.lsp) else {
                return ColonyToolOutcome(success: false, content: "Error: LSP capability not enabled.", writes: [])
            }
            guard let lsp = input.context.lsp else {
                return ColonyToolOutcome(success: false, content: "Error: LSP backend not configured.", writes: [])
            }
            let args = try decode(call.argumentsJSON, as: LSPReferencesArgs.self)
            let request = ColonyLSPReferencesRequest(
                path: try ColonyVirtualPath(args.path),
                position: ColonyLSPPosition(line: args.line, character: args.character),
                includeDeclaration: args.includeDeclaration ?? true
            )
            let references = try await lsp.references(request)
            return ColonyToolOutcome(success: true, content: formatLSPReferences(references), writes: [])

        case ColonyBuiltInToolDefinitions.lspApplyEdit.name:
            guard input.context.configuration.capabilities.contains(.lsp) else {
                return ColonyToolOutcome(success: false, content: "Error: LSP capability not enabled.", writes: [])
            }
            guard let lsp = input.context.lsp else {
                return ColonyToolOutcome(success: false, content: "Error: LSP backend not configured.", writes: [])
            }
            let args = try decode(call.argumentsJSON, as: LSPApplyEditArgs.self)
            let edits = try args.edits.map { edit in
                ColonyLSPTextEdit(
                    path: try ColonyVirtualPath(edit.path),
                    range: ColonyLSPRange(
                        start: ColonyLSPPosition(line: edit.startLine, character: edit.startCharacter),
                        end: ColonyLSPPosition(line: edit.endLine, character: edit.endCharacter)
                    ),
                    newText: edit.newText
                )
            }
            let result = try await lsp.applyEdit(ColonyLSPApplyEditRequest(edits: edits))
            return ColonyToolOutcome(success: true, content: formatLSPApplyEditResult(result), writes: [])

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

    private static func newScratchItemID(
        toolCallID: String,
        existing: Set<String>
    ) -> String {
        let base: String = {
            let trimmed = toolCallID.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? "scratch-item" : trimmed
        }()

        if existing.contains(base) == false { return base }

        var counter = 2
        while true {
            let candidate = base + "-" + String(counter)
            if existing.contains(candidate) == false { return candidate }
            counter += 1
        }
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

    private static func formatShellSessionReadResult(_ result: ColonyShellSessionReadResult) -> String {
        var sections: [String] = [
            "eof: \(result.eof ? "true" : "false")",
        ]
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

    private static func formatGitStatusResult(_ result: ColonyGitStatusResult) -> String {
        var lines: [String] = []
        if let branch = result.currentBranch {
            lines.append("branch: \(branch)")
        }
        if let upstream = result.upstreamBranch {
            lines.append("upstream: \(upstream)")
        }
        lines.append("ahead: \(result.aheadBy)")
        lines.append("behind: \(result.behindBy)")
        if result.entries.isEmpty {
            lines.append("changes: clean")
        } else {
            lines.append("changes:")
            for entry in result.entries {
                lines.append("\(gitStatusCode(for: entry.state)) \(entry.path)")
            }
        }
        return lines.joined(separator: "\n")
    }

    private static func gitStatusCode(for state: ColonyGitStatusEntry.State) -> String {
        switch state {
        case .added: "A"
        case .modified: "M"
        case .deleted: "D"
        case .renamed: "R"
        case .copied: "C"
        case .conflicted: "U"
        case .untracked: "?"
        }
    }

    private static func formatGitCommitResult(_ result: ColonyGitCommitResult) -> String {
        [
            "commit: \(result.commitHash)",
            "summary: \(result.summary)",
        ].joined(separator: "\n")
    }

    private static func formatGitBranchResult(_ result: ColonyGitBranchResult) -> String {
        var lines: [String] = []
        if let currentBranch = result.currentBranch {
            lines.append("current: \(currentBranch)")
        }
        if result.branches.isEmpty {
            lines.append("branches: (none)")
        } else {
            lines.append("branches:")
            lines.append(contentsOf: result.branches.map { "- \($0)" })
        }
        if let detail = result.detail, detail.isEmpty == false {
            lines.append("detail: \(detail)")
        }
        return lines.joined(separator: "\n")
    }

    private static func formatGitPushResult(_ result: ColonyGitPushResult) -> String {
        [
            "remote: \(result.remote)",
            "branch: \(result.branch)",
            "summary: \(result.summary)",
        ].joined(separator: "\n")
    }

    private static func formatGitPreparePRResult(_ result: ColonyGitPreparePullRequestResult) -> String {
        var lines = [
            "base: \(result.baseBranch)",
            "head: \(result.headBranch)",
            "title: \(result.title)",
            "draft: \(result.draft ? "true" : "false")",
            "body:",
            result.body,
        ]
        if let summary = result.summary, summary.isEmpty == false {
            lines.append("summary: \(summary)")
        }
        return lines.joined(separator: "\n")
    }

    private static func formatLSPSymbols(_ symbols: [ColonyLSPSymbol]) -> String {
        guard symbols.isEmpty == false else { return "(No symbols)" }
        return symbols.map { symbol in
            let line = symbol.range.start.line + 1
            let character = symbol.range.start.character + 1
            return "\(symbol.path.rawValue):\(line):\(character) [\(symbol.kind.rawValue)] \(symbol.name)"
        }.joined(separator: "\n")
    }

    private static func formatLSPDiagnostics(_ diagnostics: [ColonyLSPDiagnostic]) -> String {
        guard diagnostics.isEmpty == false else { return "(No diagnostics)" }
        return diagnostics.map { diagnostic in
            let line = diagnostic.range.start.line + 1
            let character = diagnostic.range.start.character + 1
            let code = diagnostic.code.map { "[\($0)] " } ?? ""
            return "\(diagnostic.path.rawValue):\(line):\(character) [\(diagnostic.severity.rawValue)] \(code)\(diagnostic.message)"
        }.joined(separator: "\n")
    }

    private static func formatLSPReferences(_ references: [ColonyLSPReference]) -> String {
        guard references.isEmpty == false else { return "(No references)" }
        return references.map { reference in
            let line = reference.range.start.line + 1
            let character = reference.range.start.character + 1
            if let preview = reference.preview, preview.isEmpty == false {
                return "\(reference.path.rawValue):\(line):\(character) \(preview)"
            }
            return "\(reference.path.rawValue):\(line):\(character)"
        }.joined(separator: "\n")
    }

    private static func formatLSPApplyEditResult(_ result: ColonyLSPApplyEditResult) -> String {
        var lines = ["applied_edits: \(result.appliedEditCount)"]
        if let summary = result.summary, summary.isEmpty == false {
            lines.append("summary: \(summary)")
        }
        return lines.joined(separator: "\n")
    }

    private static func formatMemoryRecallResult(_ result: ColonyMemoryRecallResult) -> String {
        guard result.items.isEmpty == false else { return "(No memory matches)" }

        let blocks = result.items.map { item in
            var lines: [String] = [
                "id: \(item.id)",
            ]
            if let score = item.score {
                lines.append(String(format: "score: %.3f", score))
            }
            if item.tags.isEmpty == false {
                lines.append("tags: \(item.tags.joined(separator: ", "))")
            }
            if item.metadata.isEmpty == false {
                let metadata = item.metadata
                    .sorted { $0.key.utf8.lexicographicallyPrecedes($1.key.utf8) }
                    .map { "\($0.key)=\($0.value)" }
                    .joined(separator: ", ")
                lines.append("metadata: \(metadata)")
            }
            lines.append("content:")
            lines.append(item.content)
            return lines.joined(separator: "\n")
        }

        return blocks.joined(separator: "\n\n")
    }

    private static func formatMemoryRememberResult(_ result: ColonyMemoryRememberResult) -> String {
        "OK: remembered \(result.id)"
    }

    private static func virtualPath(from value: String?) throws -> ColonyVirtualPath? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return nil }
        return try ColonyVirtualPath(trimmed)
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

private struct ShellOpenArgs: Decodable, Sendable {
    let command: String
    let cwd: String?
    let idleTimeoutMilliseconds: Int?

    private enum CodingKeys: String, CodingKey {
        case command
        case cwd
        case idleTimeoutMilliseconds = "idle_timeout_ms"
    }
}

private struct ShellWriteArgs: Decodable, Sendable {
    let sessionID: String
    let input: String

    private enum CodingKeys: String, CodingKey {
        case sessionID = "session_id"
        case input
    }
}

private struct ShellReadArgs: Decodable, Sendable {
    let sessionID: String
    let maxBytes: Int?
    let timeoutMilliseconds: Int?

    private enum CodingKeys: String, CodingKey {
        case sessionID = "session_id"
        case maxBytes = "max_bytes"
        case timeoutMilliseconds = "timeout_ms"
    }
}

private struct ShellCloseArgs: Decodable, Sendable {
    let sessionID: String

    private enum CodingKeys: String, CodingKey {
        case sessionID = "session_id"
    }
}

private struct ApplyPatchArgs: Decodable, Sendable {
    let patch: String
}

private struct WebSearchArgs: Decodable, Sendable {
    let query: String
    let limit: Int?
}

private struct CodeSearchArgs: Decodable, Sendable {
    let query: String
    let path: String?
}

private struct MemoryRecallArgs: Decodable, Sendable {
    let query: String
    let limit: Int?
}

private struct MemoryRememberArgs: Decodable, Sendable {
    let content: String
    let tags: [String]?
    let metadata: [String: String]?
}

private struct MCPReadResourceArgs: Decodable, Sendable {
    let resourceID: String

    private enum CodingKeys: String, CodingKey {
        case resourceID = "resource_id"
    }
}

private struct PluginInvokeArgs: Decodable, Sendable {
    let name: String
    let argumentsJSON: String

    private enum CodingKeys: String, CodingKey {
        case name
        case argumentsJSON = "arguments_json"
    }
}

private struct GitStatusArgs: Decodable, Sendable {
    let repoPath: String?
    let includeUntracked: Bool?

    private enum CodingKeys: String, CodingKey {
        case repoPath = "repo_path"
        case includeUntracked = "include_untracked"
    }
}

private struct GitDiffArgs: Decodable, Sendable {
    let repoPath: String?
    let baseRef: String?
    let headRef: String?
    let pathspec: String?
    let staged: Bool?

    private enum CodingKeys: String, CodingKey {
        case repoPath = "repo_path"
        case baseRef = "base_ref"
        case headRef = "head_ref"
        case pathspec
        case staged
    }
}

private struct GitCommitArgs: Decodable, Sendable {
    let repoPath: String?
    let message: String
    let includeAll: Bool?
    let amend: Bool?
    let signoff: Bool?

    private enum CodingKeys: String, CodingKey {
        case repoPath = "repo_path"
        case message
        case includeAll = "include_all"
        case amend
        case signoff
    }
}

private struct GitBranchArgs: Decodable, Sendable {
    let repoPath: String?
    let operation: ColonyGitBranchRequest.Operation
    let name: String?
    let startPoint: String?
    let force: Bool?

    private enum CodingKeys: String, CodingKey {
        case repoPath = "repo_path"
        case operation
        case name
        case startPoint = "start_point"
        case force
    }
}

private struct GitPushArgs: Decodable, Sendable {
    let repoPath: String?
    let remote: String?
    let branch: String?
    let setUpstream: Bool?
    let forceWithLease: Bool?

    private enum CodingKeys: String, CodingKey {
        case repoPath = "repo_path"
        case remote
        case branch
        case setUpstream = "set_upstream"
        case forceWithLease = "force_with_lease"
    }
}

private struct GitPreparePRArgs: Decodable, Sendable {
    let repoPath: String?
    let baseBranch: String
    let headBranch: String
    let title: String
    let body: String
    let draft: Bool?

    private enum CodingKeys: String, CodingKey {
        case repoPath = "repo_path"
        case baseBranch = "base_branch"
        case headBranch = "head_branch"
        case title
        case body
        case draft
    }
}

private struct LSPSymbolsArgs: Decodable, Sendable {
    let path: String?
    let query: String?
}

private struct LSPDiagnosticsArgs: Decodable, Sendable {
    let path: String?
}

private struct LSPReferencesArgs: Decodable, Sendable {
    let path: String
    let line: Int
    let character: Int
    let includeDeclaration: Bool?

    private enum CodingKeys: String, CodingKey {
        case path
        case line
        case character
        case includeDeclaration = "include_declaration"
    }
}

private struct LSPApplyEditArgs: Decodable, Sendable {
    let edits: [Edit]

    struct Edit: Decodable, Sendable {
        let path: String
        let startLine: Int
        let startCharacter: Int
        let endLine: Int
        let endCharacter: Int
        let newText: String

        private enum CodingKeys: String, CodingKey {
            case path
            case startLine = "start_line"
            case startCharacter = "start_character"
            case endLine = "end_line"
            case endCharacter = "end_character"
            case newText = "new_text"
        }
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

    private enum LegacyCodingKeys: String, CodingKey {
        case subagentType = "subagentType"
        case fileReferences = "fileReferences"
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let legacyContainer = try decoder.container(keyedBy: LegacyCodingKeys.self)

        self.prompt = try container.decode(String.self, forKey: .prompt)
        self.context = try container.decodeIfPresent(ColonySubagentContext.self, forKey: .context)
        self.subagentType =
            try container.decodeIfPresent(String.self, forKey: .subagentType)
            ?? legacyContainer.decodeIfPresent(String.self, forKey: .subagentType)
        self.fileReferences =
            try container.decodeIfPresent([ColonySubagentFileReference].self, forKey: .fileReferences)
            ?? legacyContainer.decodeIfPresent([ColonySubagentFileReference].self, forKey: .fileReferences)
    }
}

private struct ScratchAddArgs: Decodable, Sendable {
    let kind: ColonyScratchItem.Kind
    let title: String
    let body: String?
    let tags: [String]?
    let phase: String?
    let progress: Double?
}

private struct ScratchUpdateArgs: Decodable, Sendable {
    let id: String
    let title: String?
    let body: String?
    let tags: [String]?
    let status: ColonyScratchItem.Status?
    let phase: String?
    let progress: Double?
}

private struct ScratchIDArgs: Decodable, Sendable {
    let id: String
}
