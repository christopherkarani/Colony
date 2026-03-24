import HiveCore
import ColonyCore

// MARK: - Type Aliases

/// Type alias for Colony run outcomes.
public typealias ColonyOutcome = HiveRunOutcome<ColonySchema>

// MARK: - ColonyRun Namespace

/// Namespace for Colony run observation and control types.
public enum ColonyRun {

    /// Handle for observing a running Colony agent attempt.
    ///
    /// This wraps the underlying `HiveRunHandle<ColonySchema>` and provides
    /// a cleaner async API for accessing the outcome.
    public struct Handle: Sendable {
        private let hiveHandle: HiveRunHandle<ColonySchema>

        /// The unique identifier for this run.
        public var runID: HiveRunID { hiveHandle.runID }

        /// The unique identifier for this attempt (a run may have multiple attempts via resume).
        public var attemptID: HiveRunAttemptID { hiveHandle.attemptID }

        /// Stream of events occurring during the run.
        public var events: AsyncThrowingStream<HiveEvent, Error> { hiveHandle.events }

        /// The outcome of the run, accessible as an async property.
        ///
        /// This property awaits the underlying Task and returns the outcome
        /// or throws if the task failed.
        public var outcome: ColonyOutcome {
            get async throws {
                try await hiveHandle.outcome.value
            }
        }

        /// Creates a new Handle wrapping a HiveRunHandle.
        ///
        /// - Parameter hiveHandle: The underlying Hive run handle to wrap.
        public init(wrapping hiveHandle: HiveRunHandle<ColonySchema>) {
            self.hiveHandle = hiveHandle
        }
    }
}

// MARK: - Outcome Convenience Extensions

extension HiveRunOutcome where Schema == ColonySchema {

    /// Returns `true` if the outcome is `.finished`.
    public var isFinished: Bool {
        if case .finished = self { return true }
        return false
    }

    /// Returns `true` if the outcome is `.interrupted`.
    public var isInterrupted: Bool {
        if case .interrupted = self { return true }
        return false
    }
}

// MARK: - ColonyRuntime Convenience Extensions

extension ColonyRuntime {

    /// Convenience method that sends a user message and waits for completion.
    ///
    /// This method starts a run with the given input and awaits its outcome,
    /// returning the final outcome when the run completes, interrupts, or is cancelled.
    ///
    /// - Parameter input: The user message to send to the agent.
    /// - Returns: The final outcome of the run.
    /// - Throws: Any error that occurs during the run.
    public func complete(input: String) async throws -> ColonyOutcome {
        let handle = await sendUserMessage(input)
        return try await handle.outcome.value
    }
}
