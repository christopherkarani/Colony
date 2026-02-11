import Darwin
import Dispatch
import Foundation

public final class ColonyHardenedShellBackend: ColonyShellBackend, @unchecked Sendable {
    public let confinement: ColonyShellConfinementPolicy
    public let defaultTimeoutNanoseconds: UInt64?
    public let maxOutputBytes: Int
    public let environmentWhitelist: Set<String>?
    public let defaultTerminalMode: ColonyShellTerminalMode
    private let sessionManager = ColonyShellSessionManager()

    public init(
        confinement: ColonyShellConfinementPolicy,
        defaultTimeoutNanoseconds: UInt64? = nil,
        maxOutputBytes: Int = 64 * 1024,
        environmentWhitelist: Set<String>? = nil,
        defaultTerminalMode: ColonyShellTerminalMode = .pipes
    ) {
        self.confinement = confinement
        self.defaultTimeoutNanoseconds = defaultTimeoutNanoseconds
        self.maxOutputBytes = max(1, maxOutputBytes)
        self.environmentWhitelist = environmentWhitelist
        self.defaultTerminalMode = defaultTerminalMode
    }

    public func execute(_ request: ColonyShellExecutionRequest) async throws -> ColonyShellExecutionResult {
        let workingDirectory = try confinement.resolveWorkingDirectory(request.workingDirectory)
        try validateWorkingDirectoryExists(workingDirectory, requestedPath: request.workingDirectory ?? .root)

        let terminalMode = request.terminalMode ?? defaultTerminalMode
        let timeout = request.timeoutNanoseconds ?? defaultTimeoutNanoseconds
        let environment = buildEnvironment()

        let launched = try Self.launch(
            command: request.command,
            workingDirectory: workingDirectory,
            terminalMode: terminalMode,
            environment: environment,
            maxOutputBytes: maxOutputBytes
        )

        return try await withTaskCancellationHandler {
            try await Self.waitForCompletion(launched, timeoutNanoseconds: timeout)
        } onCancel: {
            launched.terminateTree()
        }
    }

    public func openSession(_ request: ColonyShellSessionOpenRequest) async throws -> ColonyShellSessionID {
        let workingDirectory = try confinement.resolveWorkingDirectory(request.workingDirectory)
        try validateWorkingDirectoryExists(workingDirectory, requestedPath: request.workingDirectory ?? .root)

        let launched = try Self.launchInteractiveSession(
            command: request.command,
            workingDirectory: workingDirectory,
            workingDirectoryPath: request.workingDirectory,
            environment: buildEnvironment(),
            maxOutputBytes: maxOutputBytes
        )

        let snapshot = ColonyShellSessionSnapshot(
            id: launched.id,
            command: request.command,
            workingDirectory: request.workingDirectory,
            startedAt: Date(),
            isRunning: launched.isRunning
        )

        await sessionManager.insert(
            launched,
            snapshot: snapshot,
            idleTimeoutNanoseconds: request.idleTimeoutNanoseconds
        )

        return launched.id
    }

    public func writeToSession(_ sessionID: ColonyShellSessionID, data: Data) async throws {
        try await sessionManager.write(to: sessionID, data: data)
    }

    public func readFromSession(
        _ sessionID: ColonyShellSessionID,
        maxBytes: Int,
        timeoutNanoseconds: UInt64?
    ) async throws -> ColonyShellSessionReadResult {
        try await sessionManager.read(
            from: sessionID,
            maxBytes: max(1, maxBytes),
            timeoutNanoseconds: timeoutNanoseconds
        )
    }

    public func closeSession(_ sessionID: ColonyShellSessionID) async {
        await sessionManager.close(sessionID)
    }

    public func listSessions() async -> [ColonyShellSessionSnapshot] {
        await sessionManager.listSnapshots()
    }
}

private extension ColonyHardenedShellBackend {
    static func launch(
        command: String,
        workingDirectory: URL,
        terminalMode: ColonyShellTerminalMode,
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
                throw ColonyShellExecutionError.launchFailed(String(cString: strerror(errno)))
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
            throw ColonyShellExecutionError.launchFailed(error.localizedDescription)
        }

        if case let .pty(_, slave) = standardIO {
            // Parent should close slave side so EOF propagates to master when child exits.
            try? slave.close()
        }

        return RunningProcess(process: process, collector: collector, standardIO: standardIO)
    }

    static func waitForCompletion(
        _ launched: RunningProcess,
        timeoutNanoseconds: UInt64?
    ) async throws -> ColonyShellExecutionResult {
        let deadline: UInt64? = timeoutNanoseconds.map { DispatchTime.now().uptimeNanoseconds &+ $0 }
        var timedOut = false

        while launched.isRunning {
            if let deadline, DispatchTime.now().uptimeNanoseconds >= deadline {
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
        return ColonyShellExecutionResult(
            exitCode: exitCode,
            stdout: output.stdout,
            stderr: stderr,
            wasTruncated: output.wasTruncated
        )
    }

    static func mergeTimeoutMessage(into stderr: String) -> String {
        let timeoutMessage = "command timed out"
        if stderr.isEmpty { return timeoutMessage }
        return stderr + "\n" + timeoutMessage
    }

    static func launchInteractiveSession(
        command: String,
        workingDirectory: URL,
        workingDirectoryPath: ColonyVirtualPath?,
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
            throw ColonyShellExecutionError.launchFailed(String(cString: strerror(errno)))
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
            throw ColonyShellExecutionError.launchFailed(error.localizedDescription)
        }

        // Parent closes slave so EOF propagates correctly.
        try? slave.close()

        return ManagedShellSession(
            id: ColonyShellSessionID(rawValue: "pty:" + UUID().uuidString.lowercased()),
            command: command,
            workingDirectory: workingDirectoryPath,
            process: process,
            master: master,
            outputBuffer: outputBuffer
        )
    }
}

private extension ColonyHardenedShellBackend {
    func validateWorkingDirectoryExists(_ url: URL, requestedPath: ColonyVirtualPath) throws {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
              isDirectory.boolValue
        else {
            throw ColonyShellExecutionError.invalidWorkingDirectory(requestedPath)
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
    let id: ColonyShellSessionID
    let command: String
    let workingDirectory: ColonyVirtualPath?
    let process: Process
    let master: FileHandle
    let outputBuffer: SessionOutputBuffer

    init(
        id: ColonyShellSessionID,
        command: String,
        workingDirectory: ColonyVirtualPath?,
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
            throw ColonyShellExecutionError.launchFailed(error.localizedDescription)
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
        var snapshot: ColonyShellSessionSnapshot
        var lastActivityNanoseconds: UInt64
        var idleTimeoutNanoseconds: UInt64?
    }

    private var entriesByID: [ColonyShellSessionID: Entry] = [:]

    func insert(
        _ session: ManagedShellSession,
        snapshot: ColonyShellSessionSnapshot,
        idleTimeoutNanoseconds: UInt64?
    ) {
        let now = DispatchTime.now().uptimeNanoseconds
        entriesByID[session.id] = Entry(
            session: session,
            snapshot: snapshot,
            lastActivityNanoseconds: now,
            idleTimeoutNanoseconds: idleTimeoutNanoseconds
        )
    }

    func write(to sessionID: ColonyShellSessionID, data: Data) async throws {
        await pruneExpiredSessions()
        guard var entry = entriesByID[sessionID] else {
            throw ColonyShellExecutionError.sessionNotFound(sessionID)
        }

        try entry.session.write(data)
        entry.lastActivityNanoseconds = DispatchTime.now().uptimeNanoseconds
        entry.snapshot.isRunning = entry.session.isRunning
        entriesByID[sessionID] = entry
    }

    func read(
        from sessionID: ColonyShellSessionID,
        maxBytes: Int,
        timeoutNanoseconds: UInt64?
    ) async throws -> ColonyShellSessionReadResult {
        await pruneExpiredSessions()
        guard var entry = entriesByID[sessionID] else {
            throw ColonyShellExecutionError.sessionNotFound(sessionID)
        }

        let deadline = timeoutNanoseconds.map { DispatchTime.now().uptimeNanoseconds &+ $0 }
        while true {
            let chunk = await entry.session.outputBuffer.drain(maxBytes: maxBytes)
            if chunk.data.isEmpty == false {
                entry.lastActivityNanoseconds = DispatchTime.now().uptimeNanoseconds
                entry.snapshot.isRunning = entry.session.isRunning
                entriesByID[sessionID] = entry
                let hasRemainingBufferedOutput = await entry.session.outputBuffer.hasData()
                return ColonyShellSessionReadResult(
                    stdout: String(decoding: chunk.data, as: UTF8.self),
                    stderr: "",
                    eof: entry.session.isRunning == false && hasRemainingBufferedOutput == false,
                    wasTruncated: chunk.wasTruncated
                )
            }

            if entry.session.isRunning == false {
                entry.snapshot.isRunning = false
                entriesByID[sessionID] = entry
                return ColonyShellSessionReadResult(stdout: "", stderr: "", eof: true, wasTruncated: false)
            }

            if let deadline, DispatchTime.now().uptimeNanoseconds >= deadline {
                entry.snapshot.isRunning = entry.session.isRunning
                entriesByID[sessionID] = entry
                return ColonyShellSessionReadResult(stdout: "", stderr: "", eof: false, wasTruncated: false)
            }

            try? await Task.sleep(nanoseconds: 10_000_000)

            guard let refreshed = entriesByID[sessionID] else {
                throw ColonyShellExecutionError.sessionNotFound(sessionID)
            }
            entry = refreshed
        }
    }

    func close(_ sessionID: ColonyShellSessionID) async {
        await pruneExpiredSessions()
        guard let entry = entriesByID.removeValue(forKey: sessionID) else { return }
        entry.session.close()
    }

    func listSnapshots() async -> [ColonyShellSessionSnapshot] {
        await pruneExpiredSessions()
        var snapshots: [ColonyShellSessionSnapshot] = []
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
        let expiredIDs = entriesByID.compactMap { sessionID, entry -> ColonyShellSessionID? in
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
