import Darwin
import Dispatch
import Foundation

// SAFETY: All mutable state is isolated to ColonyShellSessionManager (an actor).
// Immutable stored properties (confinement, defaultTimeout, maxOutputBytes,
// environmentWhitelist, defaultTerminalMode) are all Sendable value types.
public final class ColonyHardenedShellBackend: ColonyShellBackend, @unchecked Sendable {
    public let confinement: ColonyShell.ConfinementPolicy
    public let defaultTimeout: Duration?
    public let maxOutputBytes: Int
    public let environmentWhitelist: Set<String>?
    public let defaultTerminalMode: ColonyShell.TerminalMode
    private let sessionManager = ColonyShellSessionManager()

    public init(
        confinement: ColonyShell.ConfinementPolicy,
        defaultTimeout: Duration? = nil,
        maxOutputBytes: Int = 64 * 1024,
        environmentWhitelist: Set<String>? = nil,
        defaultTerminalMode: ColonyShell.TerminalMode = .pipes
    ) {
        self.confinement = confinement
        self.defaultTimeout = defaultTimeout
        self.maxOutputBytes = max(1, maxOutputBytes)
        self.environmentWhitelist = environmentWhitelist
        self.defaultTerminalMode = defaultTerminalMode
    }

    /// Create a sandboxed shell backend confined to the given root directory.
    ///
    /// ```swift
    /// let shell = try ColonyHardenedShellBackend.sandbox(root: URL(filePath: "/tmp/workspace"))
    /// ```
    public static func sandbox(
        root: URL,
        deniedPrefixes: [ColonyFileSystem.VirtualPath] = [],
        defaultTimeout: Duration? = nil,
        maxOutputBytes: Int = 64 * 1024,
        environmentWhitelist: Set<String>? = nil,
        defaultTerminalMode: ColonyShell.TerminalMode = .pipes
    ) throws -> ColonyHardenedShellBackend {
        let confinement = try ColonyShell.ConfinementPolicy(
            allowedRoot: root,
            deniedPrefixes: deniedPrefixes
        )
        return ColonyHardenedShellBackend(
            confinement: confinement,
            defaultTimeout: defaultTimeout,
            maxOutputBytes: maxOutputBytes,
            environmentWhitelist: environmentWhitelist,
            defaultTerminalMode: defaultTerminalMode
        )
    }

    public func execute(_ request: ColonyShell.ExecutionRequest) async throws -> ColonyShell.ExecutionResult {
        let workingDirectory = try confinement.resolveWorkingDirectory(request.workingDirectory)
        try validateWorkingDirectoryExists(workingDirectory, requestedPath: request.workingDirectory ?? .root)

        let terminalMode = request.terminalMode ?? defaultTerminalMode
        let timeout = request.timeout ?? defaultTimeout
        let environment = buildEnvironment()

        let launched = try Self.launch(
            command: request.command,
            workingDirectory: workingDirectory,
            terminalMode: terminalMode,
            environment: environment,
            maxOutputBytes: maxOutputBytes
        )

        return try await withTaskCancellationHandler {
            try await Self.waitForCompletion(launched, timeout: timeout)
        } onCancel: {
            launched.terminateTree()
        }
    }

    public func openSession(_ request: ColonyShell.SessionOpenRequest) async throws -> ColonyShell.SessionID {
        let workingDirectory = try confinement.resolveWorkingDirectory(request.workingDirectory)
        try validateWorkingDirectoryExists(workingDirectory, requestedPath: request.workingDirectory ?? .root)

        let launched = try Self.launchInteractiveSession(
            command: request.command,
            workingDirectory: workingDirectory,
            workingDirectoryPath: request.workingDirectory,
            environment: buildEnvironment(),
            maxOutputBytes: maxOutputBytes
        )

        let snapshot = ColonyShell.SessionSnapshot(
            id: launched.id,
            command: request.command,
            workingDirectory: request.workingDirectory,
            startedAt: Date(),
            isRunning: launched.isRunning
        )

        await sessionManager.insert(
            launched,
            snapshot: snapshot,
            idleTimeout: request.idleTimeout
        )

        return launched.id
    }

    public func writeToSession(_ sessionID: ColonyShell.SessionID, data: Data) async throws {
        try await sessionManager.write(to: sessionID, data: data)
    }

    public func readFromSession(
        _ sessionID: ColonyShell.SessionID,
        maxBytes: Int,
        timeout: Duration?
    ) async throws -> ColonyShell.SessionReadResult {
        try await sessionManager.read(
            from: sessionID,
            maxBytes: max(1, maxBytes),
            timeout: timeout
        )
    }

    public func closeSession(_ sessionID: ColonyShell.SessionID) async {
        await sessionManager.close(sessionID)
    }

    public func listSessions() async -> [ColonyShell.SessionSnapshot] {
        await sessionManager.listSnapshots()
    }
}

private extension ColonyHardenedShellBackend {
    static func launch(
        command: String,
        workingDirectory: URL,
        terminalMode: ColonyShell.TerminalMode,
        environment: [String: String]?,
        maxOutputBytes: Int
    ) throws -> RunningProcess {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", command]
        process.currentDirectoryURL = workingDirectory
        process.environment = environment

        let collector = OutputCollector(maxBytes: maxOutputBytes)
        let standardIO: StandardIO

        switch terminalMode {
        case .pipes:
            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardInput = FileHandle.nullDevice
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe

            stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard data.isEmpty == false else { return }
                collector.append(data, stream: .stdout)
            }
            stderrPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard data.isEmpty == false else { return }
                collector.append(data, stream: .stderr)
            }
            standardIO = .pipes(stdout: stdoutPipe.fileHandleForReading, stderr: stderrPipe.fileHandleForReading)

        case .pty:
            var masterFD: Int32 = -1
            var slaveFD: Int32 = -1
            guard openpty(&masterFD, &slaveFD, nil, nil, nil) == 0 else {
                throw ColonyShell.ExecutionError.launchFailed(String(cString: strerror(errno)))
            }
            let master = FileHandle(fileDescriptor: masterFD, closeOnDealloc: true)
            let slave = FileHandle(fileDescriptor: slaveFD, closeOnDealloc: true)
            process.standardInput = slave
            process.standardOutput = slave
            process.standardError = slave

            master.readabilityHandler = { handle in
                let data = handle.availableData
                guard data.isEmpty == false else { return }
                collector.append(data, stream: .stdout)
            }
            standardIO = .pty(master: master, slave: slave)
        }

        do {
            try process.run()
        } catch {
            standardIO.teardownHandlersAndClose()
            throw ColonyShell.ExecutionError.launchFailed(error.localizedDescription)
        }

        if case let .pty(_, slave) = standardIO {
            // Parent should close slave side so EOF propagates to master when child exits.
            try? slave.close()
        }

        return RunningProcess(process: process, collector: collector, standardIO: standardIO)
    }

    static func waitForCompletion(
        _ launched: RunningProcess,
        timeout: Duration?
    ) async throws -> ColonyShell.ExecutionResult {
        let deadlineNanoseconds: UInt64? = timeout.map { DispatchTime.now().uptimeNanoseconds &+ Self.durationToNanoseconds($0) }
        var timedOut = false

        while launched.isRunning {
            if let deadlineNanoseconds, DispatchTime.now().uptimeNanoseconds >= deadlineNanoseconds {
                timedOut = true
                launched.terminateTree()
                break
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }

        if timedOut {
            let killDeadline = DispatchTime.now().uptimeNanoseconds &+ 200_000_000
            while launched.isRunning, DispatchTime.now().uptimeNanoseconds < killDeadline {
                try await Task.sleep(nanoseconds: 10_000_000)
            }
            if launched.isRunning {
                launched.forceKill()
            }
        }

        while launched.isRunning {
            try await Task.sleep(nanoseconds: 5_000_000)
        }

        let output = launched.finishAndCollectOutput()
        let stderr = timedOut ? mergeTimeoutMessage(into: output.stderr) : output.stderr
        let exitCode: Int32 = timedOut ? 124 : launched.exitCode
        return ColonyShell.ExecutionResult(
            exitCode: exitCode,
            stdout: output.stdout,
            stderr: stderr,
            wasTruncated: output.wasTruncated
        )
    }

    static func durationToNanoseconds(_ duration: Duration) -> UInt64 {
        let components = duration.components
        let secondsNanos = UInt64(clamping: components.seconds) &* 1_000_000_000
        let attosecondsNanos = UInt64(clamping: components.attoseconds / 1_000_000_000)
        return secondsNanos &+ attosecondsNanos
    }

    static func mergeTimeoutMessage(into stderr: String) -> String {
        let timeoutMessage = "command timed out"
        if stderr.isEmpty { return timeoutMessage }
        return stderr + "\n" + timeoutMessage
    }

    static func launchInteractiveSession(
        command: String,
        workingDirectory: URL,
        workingDirectoryPath: ColonyFileSystem.VirtualPath?,
        environment: [String: String]?,
        maxOutputBytes: Int
    ) throws -> ManagedShellSession {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", command]
        process.currentDirectoryURL = workingDirectory
        process.environment = environment

        var masterFD: Int32 = -1
        var slaveFD: Int32 = -1
        guard openpty(&masterFD, &slaveFD, nil, nil, nil) == 0 else {
            throw ColonyShell.ExecutionError.launchFailed(String(cString: strerror(errno)))
        }

        let master = FileHandle(fileDescriptor: masterFD, closeOnDealloc: true)
        let slave = FileHandle(fileDescriptor: slaveFD, closeOnDealloc: true)
        process.standardInput = slave
        process.standardOutput = slave
        process.standardError = slave

        let outputBuffer = SessionOutputBuffer(maxBytes: maxOutputBytes)
        master.readabilityHandler = { handle in
            let data = handle.availableData
            guard data.isEmpty == false else { return }
            Task {
                await outputBuffer.append(data)
            }
        }

        do {
            try process.run()
        } catch {
            master.readabilityHandler = nil
            try? master.close()
            try? slave.close()
            throw ColonyShell.ExecutionError.launchFailed(error.localizedDescription)
        }

        // Parent closes slave so EOF propagates correctly.
        try? slave.close()

        return ManagedShellSession(
            id: ColonyShell.SessionID(rawValue: "pty:" + UUID().uuidString.lowercased()),
            command: command,
            workingDirectory: workingDirectoryPath,
            process: process,
            master: master,
            outputBuffer: outputBuffer
        )
    }
}

private extension ColonyHardenedShellBackend {
    func validateWorkingDirectoryExists(_ url: URL, requestedPath: ColonyFileSystem.VirtualPath) throws {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
              isDirectory.boolValue
        else {
            throw ColonyShell.ExecutionError.invalidWorkingDirectory(requestedPath)
        }
    }

    func buildEnvironment() -> [String: String]? {
        guard let whitelist = environmentWhitelist else { return nil }
        let inherited = ProcessInfo.processInfo.environment
        return inherited.reduce(into: [String: String]()) { partial, entry in
            if whitelist.contains(entry.key) {
                partial[entry.key] = entry.value
            }
        }
    }
}

private final class RunningProcess: @unchecked Sendable {
    private let process: Process
    private let collector: OutputCollector
    private let standardIO: StandardIO

    init(process: Process, collector: OutputCollector, standardIO: StandardIO) {
        self.process = process
        self.collector = collector
        self.standardIO = standardIO
    }

    var isRunning: Bool { process.isRunning }

    var exitCode: Int32 { process.terminationStatus }

    func terminateTree() {
        guard process.isRunning else { return }
        process.terminate()
    }

    func forceKill() {
        guard process.isRunning else { return }
        kill(process.processIdentifier, SIGKILL)
    }

    func finishAndCollectOutput() -> (stdout: String, stderr: String, wasTruncated: Bool) {
        standardIO.teardownHandlersAndDrain(into: collector)
        standardIO.teardownHandlersAndClose()
        return collector.snapshot()
    }
}

private enum StandardIO {
    case pipes(stdout: FileHandle, stderr: FileHandle)
    case pty(master: FileHandle, slave: FileHandle)

    func teardownHandlersAndDrain(into collector: OutputCollector) {
        switch self {
        case let .pipes(stdout, stderr):
            stdout.readabilityHandler = nil
            stderr.readabilityHandler = nil
            let stdoutRemainder = stdout.readDataToEndOfFile()
            if stdoutRemainder.isEmpty == false {
                collector.append(stdoutRemainder, stream: .stdout)
            }
            let stderrRemainder = stderr.readDataToEndOfFile()
            if stderrRemainder.isEmpty == false {
                collector.append(stderrRemainder, stream: .stderr)
            }

        case let .pty(master, _):
            master.readabilityHandler = nil
            let remainder = master.readDataToEndOfFile()
            if remainder.isEmpty == false {
                collector.append(remainder, stream: .stdout)
            }
        }
    }

    func teardownHandlersAndClose() {
        switch self {
        case let .pipes(stdout, stderr):
            stdout.readabilityHandler = nil
            stderr.readabilityHandler = nil
            try? stdout.close()
            try? stderr.close()

        case let .pty(master, slave):
            master.readabilityHandler = nil
            try? master.close()
            try? slave.close()
        }
    }
}

private final class OutputCollector: @unchecked Sendable {
    enum Stream {
        case stdout
        case stderr
    }

    private let maxBytes: Int
    private let lock = NSLock()
    private var stdout = Data()
    private var stderr = Data()
    private var totalCaptured = 0
    private var wasTruncated = false

    init(maxBytes: Int) {
        self.maxBytes = maxBytes
    }

    func append(_ data: Data, stream: Stream) {
        lock.lock()
        defer { lock.unlock() }

        guard data.isEmpty == false else { return }
        let remaining = maxBytes - totalCaptured
        guard remaining > 0 else {
            wasTruncated = true
            return
        }

        if data.count > remaining {
            wasTruncated = true
        }
        let chunk = data.prefix(remaining)
        totalCaptured += chunk.count
        switch stream {
        case .stdout:
            stdout.append(chunk)
        case .stderr:
            stderr.append(chunk)
        }
    }

    func snapshot() -> (stdout: String, stderr: String, wasTruncated: Bool) {
        lock.lock()
        defer { lock.unlock() }
        return (
            stdout: String(decoding: stdout, as: UTF8.self),
            stderr: String(decoding: stderr, as: UTF8.self),
            wasTruncated: wasTruncated
        )
    }
}

private actor SessionOutputBuffer {
    private let maxBytes: Int
    private var buffer = Data()
    private var wasTruncated = false

    init(maxBytes: Int) {
        self.maxBytes = max(1, maxBytes)
    }

    func append(_ data: Data) {
        guard data.isEmpty == false else { return }
        let remaining = maxBytes - buffer.count
        guard remaining > 0 else {
            wasTruncated = true
            return
        }

        if data.count > remaining {
            wasTruncated = true
        }
        buffer.append(data.prefix(remaining))
    }

    func drain(maxBytes: Int) -> (data: Data, wasTruncated: Bool) {
        let count = min(max(1, maxBytes), buffer.count)
        let chunk = buffer.prefix(count)
        buffer.removeFirst(chunk.count)
        let truncated = wasTruncated
        wasTruncated = false
        return (data: Data(chunk), wasTruncated: truncated)
    }

    func hasData() -> Bool {
        buffer.isEmpty == false
    }
}

private final class ManagedShellSession: @unchecked Sendable {
    let id: ColonyShell.SessionID
    let command: String
    let workingDirectory: ColonyFileSystem.VirtualPath?
    let process: Process
    let master: FileHandle
    let outputBuffer: SessionOutputBuffer

    init(
        id: ColonyShell.SessionID,
        command: String,
        workingDirectory: ColonyFileSystem.VirtualPath?,
        process: Process,
        master: FileHandle,
        outputBuffer: SessionOutputBuffer
    ) {
        self.id = id
        self.command = command
        self.workingDirectory = workingDirectory
        self.process = process
        self.master = master
        self.outputBuffer = outputBuffer
    }

    var isRunning: Bool {
        process.isRunning
    }

    func write(_ data: Data) throws {
        guard data.isEmpty == false else { return }
        do {
            try master.write(contentsOf: data)
        } catch {
            throw ColonyShell.ExecutionError.launchFailed(error.localizedDescription)
        }
    }

    func close() {
        if process.isRunning {
            process.terminate()
        }
        master.readabilityHandler = nil
        try? master.close()
    }
}

private actor ColonyShellSessionManager {
    private struct Entry {
        var session: ManagedShellSession
        var snapshot: ColonyShell.SessionSnapshot
        var lastActivityNanoseconds: UInt64
        var idleTimeoutNanoseconds: UInt64?
    }

    private var entriesByID: [ColonyShell.SessionID: Entry] = [:]

    func insert(
        _ session: ManagedShellSession,
        snapshot: ColonyShell.SessionSnapshot,
        idleTimeout: Duration?
    ) {
        let now = DispatchTime.now().uptimeNanoseconds
        entriesByID[session.id] = Entry(
            session: session,
            snapshot: snapshot,
            lastActivityNanoseconds: now,
            idleTimeoutNanoseconds: idleTimeout.map { ColonyHardenedShellBackend.durationToNanoseconds($0) }
        )
    }

    func write(to sessionID: ColonyShell.SessionID, data: Data) async throws {
        await pruneExpiredSessions()
        guard var entry = entriesByID[sessionID] else {
            throw ColonyShell.ExecutionError.sessionNotFound(sessionID)
        }

        try entry.session.write(data)
        entry.lastActivityNanoseconds = DispatchTime.now().uptimeNanoseconds
        entry.snapshot.isRunning = entry.session.isRunning
        entriesByID[sessionID] = entry
    }

    func read(
        from sessionID: ColonyShell.SessionID,
        maxBytes: Int,
        timeout: Duration?
    ) async throws -> ColonyShell.SessionReadResult {
        await pruneExpiredSessions()
        guard var entry = entriesByID[sessionID] else {
            throw ColonyShell.ExecutionError.sessionNotFound(sessionID)
        }

        let deadline = timeout.map { DispatchTime.now().uptimeNanoseconds &+ ColonyHardenedShellBackend.durationToNanoseconds($0) }
        while true {
            let chunk = await entry.session.outputBuffer.drain(maxBytes: maxBytes)
            if chunk.data.isEmpty == false {
                entry.lastActivityNanoseconds = DispatchTime.now().uptimeNanoseconds
                entry.snapshot.isRunning = entry.session.isRunning
                entriesByID[sessionID] = entry
                let hasRemainingBufferedOutput = await entry.session.outputBuffer.hasData()
                return ColonyShell.SessionReadResult(
                    stdout: String(decoding: chunk.data, as: UTF8.self),
                    stderr: "",
                    eof: entry.session.isRunning == false && hasRemainingBufferedOutput == false,
                    wasTruncated: chunk.wasTruncated
                )
            }

            if entry.session.isRunning == false {
                entry.snapshot.isRunning = false
                entriesByID[sessionID] = entry
                return ColonyShell.SessionReadResult(stdout: "", stderr: "", eof: true, wasTruncated: false)
            }

            if let deadline, DispatchTime.now().uptimeNanoseconds >= deadline {
                entry.snapshot.isRunning = entry.session.isRunning
                entriesByID[sessionID] = entry
                return ColonyShell.SessionReadResult(stdout: "", stderr: "", eof: false, wasTruncated: false)
            }

            try? await Task.sleep(nanoseconds: 10_000_000)

            guard let refreshed = entriesByID[sessionID] else {
                throw ColonyShell.ExecutionError.sessionNotFound(sessionID)
            }
            entry = refreshed
        }
    }

    func close(_ sessionID: ColonyShell.SessionID) async {
        await pruneExpiredSessions()
        guard let entry = entriesByID.removeValue(forKey: sessionID) else { return }
        entry.session.close()
    }

    func listSnapshots() async -> [ColonyShell.SessionSnapshot] {
        await pruneExpiredSessions()
        var snapshots: [ColonyShell.SessionSnapshot] = []
        snapshots.reserveCapacity(entriesByID.count)
        let ids = entriesByID.keys.sorted { $0.rawValue.utf8.lexicographicallyPrecedes($1.rawValue.utf8) }
        for id in ids {
            guard var entry = entriesByID[id] else { continue }
            entry.snapshot.isRunning = entry.session.isRunning
            entriesByID[id] = entry
            snapshots.append(entry.snapshot)
        }

        snapshots.sort { lhs, rhs in
            if lhs.startedAt != rhs.startedAt { return lhs.startedAt > rhs.startedAt }
            return lhs.id.rawValue.utf8.lexicographicallyPrecedes(rhs.id.rawValue.utf8)
        }
        return snapshots
    }

    private func pruneExpiredSessions() async {
        let now = DispatchTime.now().uptimeNanoseconds
        let expiredIDs = entriesByID.compactMap { sessionID, entry -> ColonyShell.SessionID? in
            guard let timeout = entry.idleTimeoutNanoseconds else { return nil }
            return (now &- entry.lastActivityNanoseconds) >= timeout ? sessionID : nil
        }

        for sessionID in expiredIDs {
            if let entry = entriesByID.removeValue(forKey: sessionID) {
                entry.session.close()
            }
        }
    }
}
