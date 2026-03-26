@_spi(ColonyInternal) import Swarm
import ColonyCore

// MARK: - HiveRunHandle Convenience APIs

extension HiveRunHandle where Schema == ColonySchema {
    /// Returns `true` if the run has finished successfully.
    package var isFinished: Bool {
        get async {
            guard let outcome = try? await outcome.value else {
                return false
            }
            return outcome.isFinished
        }
    }

    /// Returns `true` if the run is interrupted and requires user action.
    package var isInterrupted: Bool {
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
    package func complete() async throws -> HiveRunOutcome<Schema> {
        try await outcome.value
    }
}

// MARK: - HiveRunOutcome Convenience APIs

extension HiveRunOutcome {
    /// Returns `true` if the outcome is `.finished`.
    package var isFinished: Bool {
        if case .finished = self {
            return true
        }
        return false
    }

    /// Returns `true` if the outcome is `.interrupted`.
    package var isInterrupted: Bool {
        if case .interrupted = self {
            return true
        }
        return false
    }

    /// Returns the output if the outcome is `.finished`, otherwise `nil`.
    package var finishedOutput: HiveRunOutput<Schema>? {
        if case .finished(let output, _) = self {
            return output
        }
        return nil
    }

    /// Returns the interruption if the outcome is `.interrupted`, otherwise `nil`.
    package var interruption: HiveInterruption<Schema>? {
        if case .interrupted(let interruption) = self {
            return interruption
        }
        return nil
    }
}
