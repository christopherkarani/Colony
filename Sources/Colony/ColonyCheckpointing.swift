import ColonyCore
import Foundation

package struct ColonyCheckpointSnapshot: Sendable, Codable, Equatable {
    package let id: ColonyCheckpointID
    package let threadID: ColonyThreadID
    package let runID: ColonyRunID
    package let attemptID: ColonyRunAttemptID
    package let stepIndex: Int
    package let interruptID: ColonyInterruptID?
    package let store: ColonyStoreSnapshot
    package let createdAt: Date

    package init(
        id: ColonyCheckpointID = .generate(prefix: "checkpoint"),
        threadID: ColonyThreadID,
        runID: ColonyRunID,
        attemptID: ColonyRunAttemptID,
        stepIndex: Int,
        interruptID: ColonyInterruptID? = nil,
        store: ColonyStoreSnapshot,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.threadID = threadID
        self.runID = runID
        self.attemptID = attemptID
        self.stepIndex = stepIndex
        self.interruptID = interruptID
        self.store = store
        self.createdAt = createdAt
    }
}

package protocol ColonyCheckpointStore: Sendable {
    func save(_ checkpoint: ColonyCheckpointSnapshot) async throws
    func loadLatest(threadID: ColonyThreadID) async throws -> ColonyCheckpointSnapshot?
    func loadCheckpoint(threadID: ColonyThreadID, id: ColonyCheckpointID) async throws -> ColonyCheckpointSnapshot?
    func loadByInterruptID(threadID: ColonyThreadID, interruptID: ColonyInterruptID) async throws -> ColonyCheckpointSnapshot?
}

package actor ColonyInMemoryCheckpointStore: ColonyCheckpointStore {
    private var checkpoints: [ColonyCheckpointSnapshot] = []

    package init() {}

    package func save(_ checkpoint: ColonyCheckpointSnapshot) async throws {
        checkpoints.append(checkpoint)
    }

    package func loadLatest(threadID: ColonyThreadID) async throws -> ColonyCheckpointSnapshot? {
        checkpoints
            .filter { $0.threadID == threadID }
            .max {
                if $0.stepIndex == $1.stepIndex {
                    return $0.createdAt < $1.createdAt
                }
                return $0.stepIndex < $1.stepIndex
            }
    }

    package func loadCheckpoint(threadID: ColonyThreadID, id: ColonyCheckpointID) async throws -> ColonyCheckpointSnapshot? {
        checkpoints
            .last { $0.threadID == threadID && $0.id == id }
    }

    package func loadByInterruptID(threadID: ColonyThreadID, interruptID: ColonyInterruptID) async throws -> ColonyCheckpointSnapshot? {
        checkpoints
            .last { $0.threadID == threadID && $0.interruptID == interruptID }
    }
}
