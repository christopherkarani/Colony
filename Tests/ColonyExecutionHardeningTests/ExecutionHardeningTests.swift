import Foundation
import Testing
@testable import Colony

private struct TemporaryDirectory {
    let url: URL

    init(prefix: String) throws {
        let base = FileManager.default.temporaryDirectory
        let path = base.appendingPathComponent("\(prefix)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: path, withIntermediateDirectories: true)
        self.url = path
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: url)
    }
}

@Test("Disk backend rejects symlink file escape during read")
func diskBackend_rejectsSymlinkFileEscape_read() async throws {
    let temp = try TemporaryDirectory(prefix: "colony-disk-read")
    defer { temp.cleanup() }

    let root = temp.url.appendingPathComponent("root", isDirectory: true)
    let outside = temp.url.appendingPathComponent("outside", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)

    let outsideFile = outside.appendingPathComponent("secret.txt", isDirectory: false)
    try "classified".write(to: outsideFile, atomically: true, encoding: .utf8)

    let linkFile = root.appendingPathComponent("leak.txt", isDirectory: false)
    try FileManager.default.createSymbolicLink(atPath: linkFile.path, withDestinationPath: outsideFile.path)

    let backend = ColonyDiskFileSystemBackend(root: root)

    await #expect(throws: ColonyFileSystemError.invalidPath("/leak.txt")) {
        _ = try await backend.read(at: ColonyVirtualPath("/leak.txt"))
    }
}

@Test("Disk backend rejects boundary-prefix sibling escape")
func diskBackend_rejectsBoundaryPrefixSiblingEscape_read() async throws {
    let temp = try TemporaryDirectory(prefix: "colony-disk-prefix")
    defer { temp.cleanup() }

    let root = temp.url.appendingPathComponent("root", isDirectory: true)
    let sibling = temp.url.appendingPathComponent("root-escape", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: sibling, withIntermediateDirectories: true)

    let siblingFile = sibling.appendingPathComponent("secret.txt", isDirectory: false)
    try "classified".write(to: siblingFile, atomically: true, encoding: .utf8)

    let linkFile = root.appendingPathComponent("leak.txt", isDirectory: false)
    try FileManager.default.createSymbolicLink(atPath: linkFile.path, withDestinationPath: siblingFile.path)

    let backend = ColonyDiskFileSystemBackend(root: root)
    await #expect(throws: ColonyFileSystemError.invalidPath("/leak.txt")) {
        _ = try await backend.read(at: ColonyVirtualPath("/leak.txt"))
    }
}

@Test("Disk backend rejects symlink parent escape during write")
func diskBackend_rejectsSymlinkParentEscape_write() async throws {
    let temp = try TemporaryDirectory(prefix: "colony-disk-write")
    defer { temp.cleanup() }

    let root = temp.url.appendingPathComponent("root", isDirectory: true)
    let outside = temp.url.appendingPathComponent("outside", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)

    let linkDir = root.appendingPathComponent("linkdir", isDirectory: true)
    try FileManager.default.createSymbolicLink(atPath: linkDir.path, withDestinationPath: outside.path)

    let backend = ColonyDiskFileSystemBackend(root: root)

    await #expect(throws: ColonyFileSystemError.invalidPath("/linkdir/new.txt")) {
        try await backend.write(at: ColonyVirtualPath("/linkdir/new.txt"), content: "nope")
    }

    let escapedFile = outside.appendingPathComponent("new.txt", isDirectory: false)
    #expect(FileManager.default.fileExists(atPath: escapedFile.path) == false)
}

@Test("Hardened shell backend rejects denied working-directory prefix")
func hardenedShellBackend_rejectsDeniedPrefixWorkingDirectory() async throws {
    let temp = try TemporaryDirectory(prefix: "colony-shell-denied")
    defer { temp.cleanup() }

    let root = temp.url.appendingPathComponent("root", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

    let policy = try ColonyShellConfinementPolicy(
        allowedRoot: root,
        deniedPrefixes: [ColonyVirtualPath("/blocked")]
    )

    let backend = ColonyHardenedShellBackend(confinement: policy)
    let deniedPath = try ColonyVirtualPath("/blocked")
    let request = ColonyShellExecutionRequest(command: "pwd", workingDirectory: deniedPath)

    await #expect(throws: ColonyShellExecutionError.workingDirectoryDenied(deniedPath)) {
        _ = try await backend.execute(request)
    }
}

@Test("Hardened shell backend enforces timeout")
func hardenedShellBackend_timesOutLongRunningCommand() async throws {
    let temp = try TemporaryDirectory(prefix: "colony-shell-timeout")
    defer { temp.cleanup() }

    let root = temp.url.appendingPathComponent("root", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

    let policy = try ColonyShellConfinementPolicy(allowedRoot: root)
    let backend = ColonyHardenedShellBackend(confinement: policy)
    let request = ColonyShellExecutionRequest(
        command: "/bin/sleep 2",
        timeoutNanoseconds: 100_000_000
    )

    let result = try await backend.execute(request)
    #expect(result.exitCode == 124)
    #expect(result.stderr.contains("timed out"))
}

@Test("Hardened shell backend truncates output at max byte cap")
func hardenedShellBackend_truncatesOutputAtByteCap() async throws {
    let temp = try TemporaryDirectory(prefix: "colony-shell-truncate")
    defer { temp.cleanup() }

    let root = temp.url.appendingPathComponent("root", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

    let policy = try ColonyShellConfinementPolicy(allowedRoot: root)
    let backend = ColonyHardenedShellBackend(confinement: policy, maxOutputBytes: 8)
    let request = ColonyShellExecutionRequest(command: "printf '0123456789ABCDEF'")

    let result = try await backend.execute(request)
    #expect(result.stdout == "01234567")
    #expect(result.wasTruncated == true)
}

@Test("Hardened shell backend supports PTY terminal mode")
func hardenedShellBackend_supportsPTYTerminalMode() async throws {
    let temp = try TemporaryDirectory(prefix: "colony-shell-pty")
    defer { temp.cleanup() }

    let root = temp.url.appendingPathComponent("root", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

    let policy = try ColonyShellConfinementPolicy(allowedRoot: root)
    let backend = ColonyHardenedShellBackend(confinement: policy, defaultTerminalMode: .pty)
    let request = ColonyShellExecutionRequest(command: "[ -t 1 ] && printf tty || printf notty")

    let result = try await backend.execute(request)
    #expect(result.exitCode == 0)
    #expect(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines) == "tty")
}

@Test("Hardened shell backend supports managed PTY sessions read/write/close")
func hardenedShellBackend_managedPTYSessionsRoundTrip() async throws {
    let temp = try TemporaryDirectory(prefix: "colony-shell-session")
    defer { temp.cleanup() }

    let root = temp.url.appendingPathComponent("root", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

    let policy = try ColonyShellConfinementPolicy(allowedRoot: root)
    let backend = ColonyHardenedShellBackend(confinement: policy)

    let sessionID = try await backend.openSession(
        ColonyShellSessionOpenRequest(command: "/bin/cat")
    )
    try await backend.writeToSession(sessionID, data: Data("hello-session\\n".utf8))

    let read = try await backend.readFromSession(
        sessionID,
        maxBytes: 4096,
        timeoutNanoseconds: 500_000_000
    )
    #expect(read.stdout.contains("hello-session"))
    #expect(read.eof == false)

    await backend.closeSession(sessionID)

    await #expect(throws: ColonyShellExecutionError.sessionNotFound(sessionID)) {
        _ = try await backend.readFromSession(
            sessionID,
            maxBytes: 16,
            timeoutNanoseconds: 50_000_000
        )
    }
}

@Test("Hardened shell backend auto-closes idle managed sessions")
func hardenedShellBackend_closesIdleManagedSessions() async throws {
    let temp = try TemporaryDirectory(prefix: "colony-shell-session-idle")
    defer { temp.cleanup() }

    let root = temp.url.appendingPathComponent("root", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

    let policy = try ColonyShellConfinementPolicy(allowedRoot: root)
    let backend = ColonyHardenedShellBackend(confinement: policy)

    _ = try await backend.openSession(
        ColonyShellSessionOpenRequest(
            command: "/bin/cat",
            idleTimeoutNanoseconds: 50_000_000
        )
    )
    try await Task.sleep(nanoseconds: 120_000_000)

    let sessions = await backend.listSessions()
    #expect(sessions.isEmpty)
}
