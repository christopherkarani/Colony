import Foundation
import HiveCore
import ColonyCore

public struct ColonyDefaultSubagentRegistry: ColonySubagentRegistry {
    private enum RegistryError: Error, Sendable, Equatable {
        case unsupportedSubagentType(String)
        case runInterrupted
        case runCancelled
        case runOutOfSteps(maxSteps: Int)
        case missingFullStoreOutput
    }

    private static let compiledGraph: CompiledHiveGraph<ColonySchema> = {
        do {
            return try ColonyAgent.compile()
        } catch {
            preconditionFailure("ColonyDefaultSubagentRegistry failed to compile ColonyAgent graph: \(error)")
        }
    }()

    private let profile: ColonyProfile
    private let modelName: String
    private let model: AnyHiveModelClient
    private let clock: any HiveClock
    private let logger: any HiveLogger
    private let filesystem: (any ColonyFileSystemBackend)?

    public init(
        modelName: String,
        model: AnyHiveModelClient,
        clock: any HiveClock,
        logger: any HiveLogger,
        filesystem: (any ColonyFileSystemBackend)? = nil
    ) {
        self.init(
            profile: .cloud,
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
        model: AnyHiveModelClient,
        clock: any HiveClock,
        logger: any HiveLogger,
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
            )
        ]
    }

    public func run(_ request: ColonySubagentRequest) async throws -> ColonySubagentResult {
        let type = request.subagentType.trimmingCharacters(in: .whitespacesAndNewlines)
        guard type == "general-purpose" else {
            throw RegistryError.unsupportedSubagentType(request.subagentType)
        }

        var configuration = ColonyAgentFactory.configuration(profile: profile, modelName: modelName)
        configuration.capabilities = subagentCapabilities(
            base: configuration.capabilities,
            filesystem: filesystem
        )
        configuration.toolApprovalPolicy = .never
        let context = ColonyContext(
            configuration: configuration,
            filesystem: filesystem,
            shell: nil,
            subagents: nil
        )

        let environment = HiveEnvironment<ColonySchema>(
            context: context,
            clock: clock,
            logger: logger,
            model: model
        )
        let runtime = HiveRuntime(graph: Self.compiledGraph, environment: environment)

        let threadID = HiveThreadID("subagent:\(UUID().uuidString)")
        let handle = await runtime.run(
            threadID: threadID,
            input: request.prompt,
            options: HiveRunOptions(checkpointPolicy: .disabled)
        )

        let outcome = try await handle.outcome.value
        let store: HiveGlobalStore<ColonySchema>
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
        let toolMessages = messages.filter { $0.role == HiveChatRole.tool }
        if let toolError = toolMessages.first(where: { $0.content.hasPrefix("Error:") }) {
            return ColonySubagentResult(content: toolError.content)
        }

        let finalAnswer = try store.get(ColonySchema.Channels.finalAnswer)
        return ColonySubagentResult(content: finalAnswer ?? "")
    }

    private func subagentCapabilities(
        base: ColonyCapabilities,
        filesystem: (any ColonyFileSystemBackend)?
    ) -> ColonyCapabilities {
        var capabilities: ColonyCapabilities = [.planning]
        if filesystem != nil, base.contains(.filesystem) {
            capabilities.insert(.filesystem)
        }
        // Intentionally omit `.subagents` to prevent recursion by default.
        return capabilities
    }
}
