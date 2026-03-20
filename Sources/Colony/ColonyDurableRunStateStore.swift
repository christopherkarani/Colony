import Foundation
import HiveCore
import ColonyCore

package enum ColonyRunPhase: String, Codable, Sendable, Equatable {
    case running
    case interrupted
    case finished
    case cancelled
}

package struct ColonyRunStateSnapshot: Codable, Sendable, Equatable {
    package let runID: UUID
    package let sessionID: ColonyHarnessSessionID
    package let threadID: String
    package let phase: ColonyRunPhase
    package let lastEventSequence: Int
    package let updatedAt: Date

    package init(
        runID: UUID,
        sessionID: ColonyHarnessSessionID,
        threadID: String,
        phase: ColonyRunPhase,
        lastEventSequence: Int,
        updatedAt: Date
    ) {
        self.runID = runID
        self.sessionID = sessionID
        self.threadID = threadID
        self.phase = phase
        self.lastEventSequence = lastEventSequence
        self.updatedAt = updatedAt
    }
}

package actor ColonyDurableRunStateStore {
    private let runsDirectoryURL: URL
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    package init(baseURL: URL, fileManager: FileManager = .default) throws {
        self.runsDirectoryURL = baseURL.appendingPathComponent("runs", isDirectory: true)
        self.fileManager = fileManager

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder

        try ColonyPersistenceIO.ensureDirectoryExists(runsDirectoryURL, fileManager: fileManager)
    }

    package func appendEvent(
        _ envelope: ColonyHarnessEventEnvelope,
        threadID: HiveThreadID
    ) async throws {
        let runDirectory = runDirectoryURL(runID: envelope.runID)
        let eventsDirectory = runDirectory.appendingPathComponent("events", isDirectory: true)
        try ColonyPersistenceIO.ensureDirectoryExists(eventsDirectory, fileManager: fileManager)

        let eventFileName = String(format: "event-%012d.json", envelope.sequence)
        let eventURL = eventsDirectory.appendingPathComponent(eventFileName, isDirectory: false)
        try ColonyPersistenceIO.writeJSON(envelope, to: eventURL, encoder: encoder, fileManager: fileManager)

        let priorState = try await loadRunState(runID: envelope.runID)
        let nextPhase = phase(for: envelope.eventType, fallback: priorState?.phase ?? .running)
        let snapshot = ColonyRunStateSnapshot(
            runID: envelope.runID,
            sessionID: envelope.sessionID,
            threadID: threadID.rawValue,
            phase: nextPhase,
            lastEventSequence: envelope.sequence,
            updatedAt: envelope.timestamp
        )

        let stateURL = runDirectory.appendingPathComponent("state.json", isDirectory: false)
        try ColonyPersistenceIO.writeJSON(snapshot, to: stateURL, encoder: encoder, fileManager: fileManager)
    }

    package func loadRunState(runID: UUID) async throws -> ColonyRunStateSnapshot? {
        let stateURL = runDirectoryURL(runID: runID).appendingPathComponent("state.json", isDirectory: false)
        guard fileManager.fileExists(atPath: stateURL.path) else {
            return nil
        }
        return try ColonyPersistenceIO.readJSON(ColonyRunStateSnapshot.self, from: stateURL, decoder: decoder)
    }

    package func listRunStates(limit: Int? = nil) async throws -> [ColonyRunStateSnapshot] {
        if let limit, limit <= 0 {
            return []
        }

        let directories = try listRunDirectories()
        var snapshots: [ColonyRunStateSnapshot] = []
        snapshots.reserveCapacity(directories.count)

        for directory in directories {
            let stateURL = directory.appendingPathComponent("state.json", isDirectory: false)
            guard fileManager.fileExists(atPath: stateURL.path) else { continue }
            snapshots.append(try ColonyPersistenceIO.readJSON(ColonyRunStateSnapshot.self, from: stateURL, decoder: decoder))
        }

        snapshots.sort { lhs, rhs in
            if lhs.updatedAt != rhs.updatedAt {
                return lhs.updatedAt > rhs.updatedAt
            }
            return lhs.runID.uuidString > rhs.runID.uuidString
        }

        if let limit {
            return Array(snapshots.prefix(limit))
        }
        return snapshots
    }

    package func loadEvents(runID: UUID, limit: Int? = nil) async throws -> [ColonyHarnessEventEnvelope] {
        if let limit, limit <= 0 {
            return []
        }

        let eventsDirectory = runDirectoryURL(runID: runID).appendingPathComponent("events", isDirectory: true)
        let files = try ColonyPersistenceIO.listFiles(in: eventsDirectory, fileManager: fileManager)
            .filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        let selectedFiles: [URL]
        if let limit {
            selectedFiles = Array(files.suffix(limit))
        } else {
            selectedFiles = files
        }

        var events: [ColonyHarnessEventEnvelope] = []
        events.reserveCapacity(selectedFiles.count)
        for file in selectedFiles {
            events.append(try ColonyPersistenceIO.readJSON(ColonyHarnessEventEnvelope.self, from: file, decoder: decoder))
        }
        return events
    }

    package func latestInterruptedRun(sessionID: ColonyHarnessSessionID? = nil) async throws -> ColonyRunStateSnapshot? {
        let snapshots = try await listRunStates()
        return snapshots.first { snapshot in
            guard snapshot.phase == .interrupted else { return false }
            if let sessionID {
                return snapshot.sessionID == sessionID
            }
            return true
        }
    }

    package func latestRunState(sessionID: ColonyHarnessSessionID? = nil) async throws -> ColonyRunStateSnapshot? {
        let snapshots = try await listRunStates()
        return snapshots.first { snapshot in
            if let sessionID {
                return snapshot.sessionID == sessionID
            }
            return true
        }
    }

    private func runDirectoryURL(runID: UUID) -> URL {
        runsDirectoryURL.appendingPathComponent("run-\(runID.uuidString.lowercased())", isDirectory: true)
    }

    private func listRunDirectories() throws -> [URL] {
        guard fileManager.fileExists(atPath: runsDirectoryURL.path) else {
            return []
        }

        return try fileManager.contentsOfDirectory(
            at: runsDirectoryURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ).filter { url in
            (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
        }
    }

    private func phase(for eventType: ColonyHarnessEventType, fallback: ColonyRunPhase) -> ColonyRunPhase {
        switch eventType {
        case .runStarted, .runResumed:
            return .running
        case .runInterrupted:
            return .interrupted
        case .runFinished:
            return .finished
        case .runCancelled:
            return .cancelled
        case .assistantDelta, .toolRequest, .toolResult, .toolDenied:
            return fallback
        }
    }
}
