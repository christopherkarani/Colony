import HiveCore
import ColonyCore

// MARK: - HiveRunHandle Convenience APIs

extension HiveRunHandle where Schema == ColonySchema {
    /// Returns `true` if the run has finished successfully.
    public var isFinished: Bool {
        get async {
            guard let outcome = try? await outcome.value else {
                return false
            }
            return outcome.isFinished
        }
    }

    /// Returns `true` if the run is interrupted and requires user action.
    public var isInterrupted: Bool {
        get async {
            guard let outcome = try? await outcome.value else {
                return false
            }
            return outcome.isInterrupted
        }
    }

    /// Waits for the run to complete and returns the outcome.
    ///
    /// This is a convenience method that awaits the outcome task.
    public func complete() async throws -> HiveRunOutcome<Schema> {
        try await outcome.value
    }
}

// MARK: - HiveRunOutcome Convenience APIs

extension HiveRunOutcome {
    /// Returns `true` if the outcome is `.finished`.
    public var isFinished: Bool {
        if case .finished = self {
            return true
        }
        return false
    }

    /// Returns `true` if the outcome is `.interrupted`.
    public var isInterrupted: Bool {
        if case .interrupted = self {
            return true
        }
        return false
    }

    /// Returns the output if the outcome is `.finished`, otherwise `nil`.
    public var finishedOutput: HiveRunOutput<Schema>? {
        if case .finished(let output, _) = self {
            return output
        }
        return nil
    }

    /// Returns the interruption if the outcome is `.interrupted`, otherwise `nil`.
    public var interruption: HiveInterruption<Schema>? {
        if case .interrupted(let interruption) = self {
            return interruption
        }
        return nil
    }
}
