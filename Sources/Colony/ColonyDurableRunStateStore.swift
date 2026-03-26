import Foundation
@_spi(ColonyInternal) import Swarm
import ColonyCore

/// Represents the current phase of a Colony run.
public enum ColonyRunPhase: String, Codable, Sendable, Equatable {
    /// The run is actively executing.
    case running
    /// The run is paused waiting for user input (e.g., tool approval).
    case interrupted
    /// The run completed successfully.
    case finished
    /// The run was cancelled.
    case cancelled
}

/// A snapshot of run state at a point in time.
///
/// This struct captures the complete state of a run including its ID,
/// phase, and the sequence number of the last event processed.
public struct ColonyRunStateSnapshot: Codable, Sendable, Equatable {
    /// The unique run identifier.
    public let runID: ColonyRunID

    /// The session this run belongs to.
    public let sessionID: ColonyHarnessSessionID

    /// The thread ID for this run.
    public let threadID: ColonyThreadID

    /// The current phase of the run.
    public let phase: ColonyRunPhase

    /// Sequence number of the last processed event.
    public let lastEventSequence: Int

    /// Timestamp of the last update.
    public let updatedAt: Date

    /// Creates a new run state snapshot.
    ///
    /// - Parameters:
    ///   - runID: The run identifier.
    ///   - sessionID: The session identifier.
    ///   - threadID: The thread identifier.
    ///   - phase: The current phase.
    ///   - lastEventSequence: Last event sequence number.
    ///   - updatedAt: Last update timestamp.
    public init(
        runID: ColonyRunID,
        sessionID: ColonyHarnessSessionID,
        threadID: ColonyThreadID,
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

/// A durable store for run state snapshots and events.
///
/// This actor persists run state to the filesystem, enabling recovery
/// of run state across application restarts and event replay.
public actor ColonyDurableRunStateStore {
    private let runsDirectoryURL: URL
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    /// Creates a new durable run state store.
    ///
    /// - Parameters:
    ///   - baseURL: Base directory for storage.
    ///   - fileManager: File manager to use. Defaults to `.default`.
    /// - Throws: If the runs directory cannot be created.
    public init(baseURL: URL, fileManager: FileManager = .default) throws {
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

    /// Appends an event envelope to the run's event log.
    ///
    /// Also updates the run state snapshot with the new phase.
    ///
    /// - Parameters:
    ///   - envelope: The event envelope to append.
    ///   - threadID: The thread ID for the run.
    public func appendEvent(
        _ envelope: ColonyHarnessEventEnvelope,
        threadID: ColonyThreadID
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
            runID: ColonyRunID(hiveRunID: HiveRunID(envelope.runID)),
            sessionID: envelope.sessionID,
            threadID: threadID,
            phase: nextPhase,
            lastEventSequence: envelope.sequence,
            updatedAt: envelope.timestamp
        )

        let stateURL = runDirectory.appendingPathComponent("state.json", isDirectory: false)
        try ColonyPersistenceIO.writeJSON(snapshot, to: stateURL, encoder: encoder, fileManager: fileManager)
    }

    /// Loads the run state snapshot for a run.
    ///
    /// - Parameter runID: The run identifier.
    /// - Returns: The run state snapshot, or nil if not found.
    public func loadRunState(runID: UUID) async throws -> ColonyRunStateSnapshot? {
        let colonyRunID = ColonyRunID(hiveRunID: HiveRunID(runID))
        let runDirectory = runDirectoryURL(runID: runID)
        let stateURL = runDirectory.appendingPathComponent("state.json", isDirectory: false)
        guard fileManager.fileExists(atPath: stateURL.path) else {
            return try await rebuildStateSnapshotFromEvents(
                runDirectory: runDirectory,
                runID: colonyRunID,
                fallbackThreadID: .generate()
            )
        }
        let snapshot = try ColonyPersistenceIO.readJSON(ColonyRunStateSnapshot.self, from: stateURL, decoder: decoder)
        guard let recovered = try await rebuildStateSnapshotFromEvents(
            runDirectory: runDirectory,
            runID: colonyRunID,
            minimumSequence: snapshot.lastEventSequence + 1,
            fallbackThreadID: snapshot.threadID
        ) else {
            return snapshot
        }

        // The event log is ahead of the snapshot; repair by returning and persisting recovered state.
        try ColonyPersistenceIO.writeJSON(recovered, to: stateURL, encoder: encoder, fileManager: fileManager)
        return recovered
    }

    /// Lists all run state snapshots with optional limit.
    ///
    /// - Parameter limit: Maximum number of snapshots to return.
    /// - Returns: List of run state snapshots, newest first.
    public func listRunStates(limit: Int? = nil) async throws -> [ColonyRunStateSnapshot] {
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
            return lhs.runID.rawValue > rhs.runID.rawValue
        }

        if let limit {
            return Array(snapshots.prefix(limit))
        }
        return snapshots
    }

    /// Loads events for a run with optional limit.
    ///
    /// - Parameters:
    ///   - runID: The run identifier.
    ///   - limit: Maximum number of events to return (oldest first).
    /// - Returns: List of event envelopes.
    public func loadEvents(runID: UUID, limit: Int? = nil) async throws -> [ColonyHarnessEventEnvelope] {
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

    /// Finds the most recent interrupted run.
    ///
    /// - Parameter sessionID: Optional session ID to filter by.
    /// - Returns: The most recent interrupted run snapshot, or nil.
    public func latestInterruptedRun(sessionID: ColonyHarnessSessionID? = nil) async throws -> ColonyRunStateSnapshot? {
        let snapshots = try await listRunStates()
        return snapshots.first { snapshot in
            guard snapshot.phase == .interrupted else { return false }
            if let sessionID {
                return snapshot.sessionID == sessionID
            }
            return true
        }
    }

    /// Finds the most recent run state for a session.
    ///
    /// - Parameter sessionID: Optional session ID to filter by.
    /// - Returns: The most recent run snapshot, or nil.
    public func latestRunState(sessionID: ColonyHarnessSessionID? = nil) async throws -> ColonyRunStateSnapshot? {
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

    private func rebuildStateSnapshotFromEvents(
        runDirectory: URL,
        runID: ColonyRunID,
        minimumSequence: Int = 1,
        fallbackThreadID: ColonyThreadID
    ) async throws -> ColonyRunStateSnapshot? {
        let eventsDirectory = runDirectory.appendingPathComponent("events", isDirectory: true)
        guard fileManager.fileExists(atPath: eventsDirectory.path) else {
            return nil
        }

        let files = try ColonyPersistenceIO.listFiles(in: eventsDirectory, fileManager: fileManager)
            .filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        var latestEvent: ColonyHarnessEventEnvelope?
        for file in files {
            let event = try ColonyPersistenceIO.readJSON(ColonyHarnessEventEnvelope.self, from: file, decoder: decoder)
            guard event.sequence >= minimumSequence else { continue }
            latestEvent = event
        }

        guard let latestEvent else {
            return nil
        }

        var currentPhase: ColonyRunPhase = .running
        for file in files {
            let event = try ColonyPersistenceIO.readJSON(ColonyHarnessEventEnvelope.self, from: file, decoder: decoder)
            guard event.sequence <= latestEvent.sequence else { continue }
            currentPhase = phase(for: event.eventType, fallback: currentPhase)
        }

        return ColonyRunStateSnapshot(
            runID: runID,
            sessionID: latestEvent.sessionID,
            threadID: fallbackThreadID,
            phase: currentPhase,
            lastEventSequence: latestEvent.sequence,
            updatedAt: latestEvent.timestamp
        )
    }
}
