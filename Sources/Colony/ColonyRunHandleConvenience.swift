import ColonyCore

extension ColonyRun.Handle {
    package var isFinished: Bool {
        get async {
            guard let outcome = try? await outcome.value else {
                return false
            }
            return outcome.isFinished
        }
    }

    package var isInterrupted: Bool {
        get async {
            guard let outcome = try? await outcome.value else {
                return false
            }
            return outcome.isInterrupted
        }
    }

    package func complete() async throws -> ColonyRun.Outcome {
        try await outcome.value
    }
}
