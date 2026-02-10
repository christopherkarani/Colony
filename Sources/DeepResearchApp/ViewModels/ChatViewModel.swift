import SwiftUI
import Colony

#if canImport(FoundationModels)
import FoundationModels
#endif

@Observable
@MainActor
final class ChatViewModel {
    var messages: [ChatMessage] = []
    var currentPhase: ResearchPhase = .idle
    var isProcessing: Bool = false
    var pendingApproval: PendingToolApproval? = nil
    var error: String? = nil
    var isInputDisabled: Bool {
        isProcessing || isRunInFlight || pendingApproval != nil
    }
    var activeProviderModelSummary: String {
        guard let configuration = activeRuntimeConfiguration else {
            return "Provider not configured"
        }
        return "\(configuration.providerDisplayName) · \(configuration.selectedModelName)"
    }

    #if canImport(FoundationModels)
    /// Structured insights extracted from the most recent research report.
    /// Populated asynchronously after the agent finishes its answer.
    @available(macOS 26.0, iOS 26.0, visionOS 26.0, *)
    var insights: ResearchInsights? {
        get { _insightsStorage as? ResearchInsights }
        set { _insightsStorage = newValue }
    }
    /// Indicates whether insights extraction is currently in progress.
    var isExtractingInsights: Bool = false
    #endif

    private var _insightsStorage: (any Sendable)? = nil
    private var runtime: ColonyRuntime?
    private var eventTask: Task<Void, Never>?
    private var insightsTask: Task<Void, Never>?
    private var liveInsightsTask: Task<Void, Never>?
    private var lastLiveInsightsSourceLength: Int = 0
    private var activeRuntimeConfiguration: RuntimeConfiguration?
    private var pendingRuntimeConfiguration: RuntimeConfiguration?
    private var isRunInFlight: Bool = false

    struct PendingToolApproval {
        let interruptID: HiveInterruptID
        let toolCalls: [HiveToolCall]

        var toolNames: [String] {
            toolCalls.map(\.name)
        }
    }

    private struct RuntimeConfiguration: Equatable {
        let provider: ModelProviderFactory.Configuration
        let tavilyAPIKey: String

        init(settings: AppSettings) {
            self.provider = ModelProviderFactory.Configuration(
                backend: settings.selectedBackend,
                ollamaBaseURL: settings.ollamaBaseURL,
                selectedOllamaModel: settings.selectedOllamaModel
            )
            self.tavilyAPIKey = settings.tavilyAPIKey
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        var selectedBackend: BackendType { provider.backend }

        var selectedModelName: String {
            selectedBackend == .foundationModels ? "foundation-models" : provider.selectedOllamaModel
        }

        var providerDisplayName: String { selectedBackend.displayName }
    }

    // MARK: - Configuration

    func configure(with settingsVM: SettingsViewModel, conversationID: UUID) {
        configure(settings: settingsVM.settings)
    }

    func configure(settings: AppSettings) {
        requestRuntimeReconfiguration(using: settings)
    }

    func handleSettingsUpdate(_ settings: AppSettings) {
        requestRuntimeReconfiguration(using: settings)
    }

    private func requestRuntimeReconfiguration(using settings: AppSettings) {
        let configuration = RuntimeConfiguration(settings: settings)
        if configuration == activeRuntimeConfiguration {
            pendingRuntimeConfiguration = nil
            return
        }
        if isRunInFlight {
            pendingRuntimeConfiguration = configuration
            return
        }
        applyRuntimeConfiguration(configuration)
    }

    private func applyRuntimeConfiguration(_ configuration: RuntimeConfiguration) {
        let client: AnyHiveModelClient
        do {
            client = try ModelProviderFactory.makeClient(configuration: configuration.provider)
        } catch {
            self.error = "Failed to create model client: \(describe(error))"
            return
        }

        let tavilyRegistry: AnyHiveToolRegistry? = configuration.tavilyAPIKey.isEmpty
            ? nil
            : AnyHiveToolRegistry(TavilySearchToolRegistry(apiKey: configuration.tavilyAPIKey))

        let profile: ColonyProfile = configuration.selectedBackend == .foundationModels
            ? .onDevice4k
            : .cloud

        let systemPrompt = Self.deepResearchSystemPrompt
        do {
            runtime = try ColonyAgentFactory().makeRuntime(
                profile: profile,
                modelName: configuration.selectedModelName,
                model: client,
                tools: tavilyRegistry,
                configure: { config in
                    config.capabilities = [.planning, .scratchbook]
                    config.toolApprovalPolicy = .never
                    config.additionalSystemPrompt = systemPrompt
                }
            )
            activeRuntimeConfiguration = configuration
            pendingRuntimeConfiguration = nil
        } catch {
            self.error = "Failed to create runtime: \(describe(error))"
        }
    }

    // MARK: - Send Message

    func send(_ text: String) async {
        await sendMessage(text)
    }

    func sendMessage(_ text: String) async {
        guard isRunInFlight == false, pendingApproval == nil else {
            error = "Finish the current run or resolve pending tool approval before sending a new message."
            return
        }
        guard let runtime else {
            error = "Runtime not configured. Please check settings."
            return
        }

        let userMessage = ChatMessage.user(text)
        messages.append(userMessage)

        liveInsightsTask?.cancel()
        insightsTask?.cancel()
        lastLiveInsightsSourceLength = 0
        #if canImport(FoundationModels)
        if #available(macOS 26.0, iOS 26.0, visionOS 26.0, *) {
            insights = nil
        }
        #endif

        let assistantMessage = ChatMessage.assistantPlaceholder()
        let assistantID = assistantMessage.id
        messages.append(assistantMessage)

        isProcessing = true
        isRunInFlight = true
        currentPhase = .clarifying
        error = nil

        let handle = await runtime.sendUserMessage(text)

        startEventConsumption(handle: handle, assistantMessageID: assistantID)

        await resolveOutcomeLoop(handle: handle, assistantMessageID: assistantID)
    }

    // MARK: - Tool Approval

    func approveTools() {
        Task { await approveTools(approved: true) }
    }

    func rejectTools() {
        Task { await approveTools(approved: false) }
    }

    func approveTools(approved: Bool) async {
        guard let runtime, let approval = pendingApproval else { return }
        pendingApproval = nil

        let decision: ColonyToolApprovalDecision = approved ? .approved : .rejected
        let handle = await runtime.resumeToolApproval(
            interruptID: approval.interruptID,
            decision: decision
        )

        let assistantMessage = ChatMessage.assistantPlaceholder()
        let assistantID = assistantMessage.id
        messages.append(assistantMessage)

        isProcessing = true
        isRunInFlight = true

        startEventConsumption(handle: handle, assistantMessageID: assistantID)

        await resolveOutcomeLoop(handle: handle, assistantMessageID: assistantID)
    }

    // MARK: - Event Consumption

    private func startEventConsumption(
        handle: HiveRunHandle<ColonySchema>,
        assistantMessageID: String
    ) {
        eventTask?.cancel()
        eventTask = Task { [weak self] in
            await self?.consumeEvents(handle: handle, assistantMessageID: assistantMessageID)
        }
    }

    private func consumeEvents(
        handle: HiveRunHandle<ColonySchema>,
        assistantMessageID: String
    ) async {
        do {
            for try await event in handle.events {
                guard !Task.isCancelled else { break }

                switch event.kind {
                case .modelToken(let text):
                    appendToAssistantMessage(id: assistantMessageID, text: text)

                case .toolInvocationStarted(let name):
                    let phase = ResearchPhase.fromToolName(name)
                    currentPhase = phase
                    addToolCall(
                        toMessageID: assistantMessageID,
                        toolCallID: event.metadata["toolCallID"] ?? UUID().uuidString,
                        name: name,
                        status: .running
                    )

                case .toolInvocationFinished(_, let success):
                    updateToolCallStatus(
                        inMessageID: assistantMessageID,
                        toolCallID: event.metadata["toolCallID"] ?? "",
                        status: success ? .completed : .failed
                    )

                case .modelInvocationStarted:
                    if currentPhase == .searching || currentPhase == .reading {
                        currentPhase = .synthesizing
                    }

                default:
                    break
                }
            }
        } catch {
            if !Task.isCancelled {
                let details = describe(error)
                self.error = "Event stream error: \(details)"
                setAssistantFailureMessage(
                    id: assistantMessageID,
                    details: details
                )
            }
        }
    }

    // MARK: - Outcome Loop

    private func resolveOutcomeLoop(
        handle: HiveRunHandle<ColonySchema>,
        assistantMessageID: String
    ) async {
        let currentHandle = handle

        while true {
            let outcome: HiveRunOutcome<ColonySchema>
            do {
                outcome = try await currentHandle.outcome.value
            } catch {
                finalizeAssistantMessage(id: assistantMessageID)
                let details = describe(error)
                self.error = "Run failed: \(details)"
                setAssistantFailureMessage(
                    id: assistantMessageID,
                    details: details
                )
                finalizeRun(phase: .idle)
                return
            }

            switch outcome {
            case let .finished(output, _):
                let answer = extractFinalAnswer(from: output)
                if let answer, !answer.isEmpty {
                    setAssistantMessageContent(id: assistantMessageID, content: answer)
                    extractInsightsIfAvailable(from: answer)
                }
                finalizeAssistantMessage(id: assistantMessageID)
                finalizeRun(phase: .done)
                return

            case let .cancelled(output, _):
                let answer = extractFinalAnswer(from: output)
                if let answer, !answer.isEmpty {
                    setAssistantMessageContent(id: assistantMessageID, content: answer)
                }
                finalizeAssistantMessage(id: assistantMessageID)
                finalizeRun(phase: .done)
                return

            case let .outOfSteps(_, output, _):
                let answer = extractFinalAnswer(from: output)
                if let answer, !answer.isEmpty {
                    setAssistantMessageContent(id: assistantMessageID, content: answer)
                }
                finalizeAssistantMessage(id: assistantMessageID)
                finalizeRun(phase: .done)
                return

            case let .interrupted(interruption):
                switch interruption.interrupt.payload {
                case .toolApprovalRequired(let toolCalls):
                    pendingApproval = PendingToolApproval(
                        interruptID: interruption.interrupt.id,
                        toolCalls: toolCalls
                    )
                    isProcessing = false
                    // The loop exits here; user calls approveTools() which creates a new handle
                    return
                }
            }
        }
    }

    private func finalizeRun(phase: ResearchPhase) {
        isProcessing = false
        currentPhase = phase
        isRunInFlight = false
        applyPendingRuntimeReconfigurationIfNeeded()
    }

    private func applyPendingRuntimeReconfigurationIfNeeded() {
        guard let pendingRuntimeConfiguration else { return }
        self.pendingRuntimeConfiguration = nil
        applyRuntimeConfiguration(pendingRuntimeConfiguration)
    }

    // MARK: - Message Mutation Helpers

    private func appendToAssistantMessage(id: String, text: String) {
        guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
        messages[index].content += text
        scheduleLiveInsightsExtractionIfAvailable(from: messages[index].content)
    }

    private func setAssistantMessageContent(id: String, content: String) {
        guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
        // Always replace with the clean final answer from the ColonySchema channel,
        // overwriting any raw streaming tokens that accumulated during tool use.
        messages[index].content = content
    }

    private func finalizeAssistantMessage(id: String) {
        guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
        messages[index].isStreaming = false
    }

    private func describe(_ error: Error) -> String {
        if let localized = (error as? LocalizedError)?.errorDescription {
            let trimmed = localized.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty == false {
                return trimmed
            }
        }
        let rendered = String(describing: error).trimmingCharacters(in: .whitespacesAndNewlines)
        if rendered.isEmpty == false {
            return rendered
        }
        return error.localizedDescription
    }

    private func setAssistantFailureMessage(id: String, details: String) {
        let message = """
        I hit an internal error before completing this response.

        Details: \(details)
        """
        setAssistantMessageContent(id: id, content: message)
    }

    private func addToolCall(
        toMessageID messageID: String,
        toolCallID: String,
        name: String,
        status: ChatMessage.ToolCallInfo.ToolCallStatus
    ) {
        guard let index = messages.firstIndex(where: { $0.id == messageID }) else { return }
        let info = ChatMessage.ToolCallInfo(id: toolCallID, name: name, status: status)
        messages[index].toolCalls.append(info)
    }

    private func updateToolCallStatus(
        inMessageID messageID: String,
        toolCallID: String,
        status: ChatMessage.ToolCallInfo.ToolCallStatus
    ) {
        guard let msgIndex = messages.firstIndex(where: { $0.id == messageID }) else { return }
        guard let tcIndex = messages[msgIndex].toolCalls.firstIndex(where: { $0.id == toolCallID }) else { return }
        messages[msgIndex].toolCalls[tcIndex].status = status
    }

    private func extractFinalAnswer(from output: HiveRunOutput<ColonySchema>) -> String? {
        switch output {
        case .fullStore(let store):
            return try? store.get(ColonySchema.Channels.finalAnswer)
        case .channels:
            return nil
        }
    }

    // MARK: - Insights Extraction

    /// Kicks off a non-blocking extraction of ``ResearchInsights`` from the
    /// completed markdown report using the on-device Foundation Models pipeline.
    private func extractInsightsIfAvailable(from markdownReport: String) {
        #if canImport(FoundationModels)
        guard InsightsExtractor.isAvailable else { return }
        liveInsightsTask?.cancel()
        insightsTask?.cancel()
        insightsTask = Task {
            if #available(macOS 26.0, iOS 26.0, visionOS 26.0, *) {
                self.isExtractingInsights = true
                do {
                    let extractor = InsightsExtractor()
                    let result = try await extractor.extract(from: markdownReport)
                    guard !Task.isCancelled else { return }
                    self.insights = result
                    self.isExtractingInsights = false
                } catch {
                    guard !Task.isCancelled else { return }
                    self.isExtractingInsights = false
                }
            }
        }
        #endif
    }

    /// Streams UI-friendly insights progressively by running `@Generable`
    /// extraction on partial assistant output with debounce.
    private func scheduleLiveInsightsExtractionIfAvailable(from markdownSoFar: String) {
        #if canImport(FoundationModels)
        guard InsightsExtractor.isAvailable else { return }
        guard markdownSoFar.count >= 500 else { return }
        guard markdownSoFar.count - lastLiveInsightsSourceLength >= 300 else { return }

        lastLiveInsightsSourceLength = markdownSoFar.count
        liveInsightsTask?.cancel()

        let snapshot = markdownSoFar
        liveInsightsTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 900_000_000)
            guard let self, !Task.isCancelled else { return }

            if #available(macOS 26.0, iOS 26.0, visionOS 26.0, *) {
                self.isExtractingInsights = true
                defer { self.isExtractingInsights = false }

                do {
                    let extractor = InsightsExtractor()
                    let result = try await extractor.extract(from: snapshot)
                    guard !Task.isCancelled else { return }
                    self.insights = result
                } catch {
                    // Best-effort while streaming; final extraction runs after completion.
                }
            }
        }
        #endif
    }

    // MARK: - System Prompt

    nonisolated private static let deepResearchSystemPrompt: String = """
    You are a Deep Research Assistant. Your purpose is to conduct thorough, multi-step research on topics.

    ## Research Protocol

    1. **CLARIFY** (mandatory first step): When the user gives you a research topic, ask 2-3 targeted clarifying questions about the specific angle, depth needed, and any constraints. Wait for answers before proceeding.

    2. **PLAN**: After clarification, create a research plan using write_todos. Break into 3-7 focused sub-questions.

    3. **SEARCH**: Execute systematically:
       - Use tavily_search for each sub-question with specific, focused queries
       - Use tavily_extract for full content from most relevant URLs
       - Search iteratively if initial results raise new questions
       - Update todos as you complete each step

    4. **SYNTHESIZE**: Compile findings into structured Markdown:
       - Title (# heading) and executive summary
       - Organized sections with ## headings
       - Source citations as [Title](URL) links
       - Limitations & Gaps section if applicable

    ## Rules
    - Always clarify before researching
    - Aim for at least 3 searches per topic
    - Cite sources for all factual claims
    - If you cannot find reliable info, say so
    """
}
