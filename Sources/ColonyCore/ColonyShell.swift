import Foundation

/// Namespace for shell-related types used by Colony.
public enum ColonyShell {}

// MARK: - ColonyShell.TerminalMode

extension ColonyShell {
    public enum TerminalMode: String, Sendable, Codable {
        case pipes
        case pty
    }
}

// MARK: - ColonyShell.ExecutionRequest

extension ColonyShell {
    public struct ExecutionRequest: Sendable, Equatable {
        public var command: String
        public var workingDirectory: ColonyFileSystem.VirtualPath?
        public var timeout: Duration?
        public var terminalMode: ColonyShell.TerminalMode?

        public init(
            command: String,
            workingDirectory: ColonyFileSystem.VirtualPath? = nil,
            timeout: Duration? = nil,
            terminalMode: ColonyShell.TerminalMode? = nil
        ) {
            self.command = command
            self.workingDirectory = workingDirectory
            self.timeout = timeout
            self.terminalMode = terminalMode
        }
    }
}

// MARK: - ColonyShell.ExecutionResult

extension ColonyShell {
    public struct ExecutionResult: Sendable, Equatable {
        public var exitCode: Int32
        public var stdout: String
        public var stderr: String
        public var wasTruncated: Bool

        public init(
            exitCode: Int32,
            stdout: String,
            stderr: String,
            wasTruncated: Bool = false
        ) {
            self.exitCode = exitCode
            self.stdout = stdout
            self.stderr = stderr
            self.wasTruncated = wasTruncated
        }

        public var combinedOutput: String {
            if stdout.isEmpty { return stderr }
            if stderr.isEmpty { return stdout }
            return stdout + "\n" + stderr
        }
    }
}

// MARK: - ColonyShell.SessionID

extension ColonyShell {
    public typealias SessionID = ColonyShellSessionID
}

// MARK: - ColonyShell.SessionOpenRequest

extension ColonyShell {
    public struct SessionOpenRequest: Sendable, Equatable {
        public var command: String
        public var workingDirectory: ColonyFileSystem.VirtualPath?
        public var idleTimeout: Duration?

        public init(
            command: String,
            workingDirectory: ColonyFileSystem.VirtualPath? = nil,
            idleTimeout: Duration? = nil
        ) {
            self.command = command
            self.workingDirectory = workingDirectory
            self.idleTimeout = idleTimeout
        }
    }
}

// MARK: - ColonyShell.SessionReadResult

extension ColonyShell {
    public struct SessionReadResult: Sendable, Equatable {
        public var stdout: String
        public var stderr: String
        public var eof: Bool
        public var wasTruncated: Bool

        public init(stdout: String, stderr: String = "", eof: Bool, wasTruncated: Bool = false) {
            self.stdout = stdout
            self.stderr = stderr
            self.eof = eof
            self.wasTruncated = wasTruncated
        }
    }
}

// MARK: - ColonyShell.SessionSnapshot

extension ColonyShell {
    public struct SessionSnapshot: Sendable, Equatable {
        public var id: ColonyShell.SessionID
        public var command: String
        public var workingDirectory: ColonyFileSystem.VirtualPath?
        public var startedAt: Date
        public var isRunning: Bool

        public init(
            id: ColonyShell.SessionID,
            command: String,
            workingDirectory: ColonyFileSystem.VirtualPath?,
            startedAt: Date,
            isRunning: Bool
        ) {
            self.id = id
            self.command = command
            self.workingDirectory = workingDirectory
            self.startedAt = startedAt
            self.isRunning = isRunning
        }
    }
}

// MARK: - ColonyShellBackend (top-level protocol)

/// A backend that can execute single shell commands.
public protocol ColonyShellExecutor: Sendable {
    func execute(_ request: ColonyShell.ExecutionRequest) async throws -> ColonyShell.ExecutionResult
}

/// A backend that can manage interactive shell sessions.
public protocol ColonyShellSessionProvider: Sendable {
    func openSession(_ request: ColonyShell.SessionOpenRequest) async throws -> ColonyShell.SessionID
    func writeToSession(_ sessionID: ColonyShell.SessionID, data: Data) async throws
    func readFromSession(
        _ sessionID: ColonyShell.SessionID,
        maxBytes: Int,
        timeout: Duration?
    ) async throws -> ColonyShell.SessionReadResult
    func closeSession(_ sessionID: ColonyShell.SessionID) async
    func listSessions() async -> [ColonyShell.SessionSnapshot]
}

/// A full shell backend that supports both command execution and interactive sessions.
public protocol ColonyShellBackend: ColonyShellExecutor, ColonyShellSessionProvider {}

public extension ColonyShellSessionProvider {
    func openSession(_ request: ColonyShell.SessionOpenRequest) async throws -> ColonyShell.SessionID {
        _ = request
        throw ColonyShell.ExecutionError.sessionManagementUnsupported
    }

    func writeToSession(_ sessionID: ColonyShell.SessionID, data: Data) async throws {
        _ = sessionID
        _ = data
        throw ColonyShell.ExecutionError.sessionManagementUnsupported
    }

    func readFromSession(
        _ sessionID: ColonyShell.SessionID,
        maxBytes: Int,
        timeout: Duration?
    ) async throws -> ColonyShell.SessionReadResult {
        _ = sessionID
        _ = maxBytes
        _ = timeout
        throw ColonyShell.ExecutionError.sessionManagementUnsupported
    }

    func closeSession(_ sessionID: ColonyShell.SessionID) async {
        _ = sessionID
    }

    func listSessions() async -> [ColonyShell.SessionSnapshot] {
        []
    }
}

// MARK: - ColonyShell.ExecutionError

extension ColonyShell {
    public enum ExecutionError: Error, Sendable, Equatable {
        case invalidConfinementRoot(String)
        case invalidWorkingDirectory(ColonyFileSystem.VirtualPath)
        case workingDirectoryDenied(ColonyFileSystem.VirtualPath)
        case workingDirectoryOutsideConfinement(ColonyFileSystem.VirtualPath)
        case launchFailed(String)
        case sessionNotFound(ColonyShell.SessionID)
        case sessionManagementUnsupported
    }
}

// MARK: - ColonyShell.ConfinementPolicy

extension ColonyShell {
    public struct ConfinementPolicy: Sendable, Equatable {
        public let allowedRoot: URL
        public let deniedPrefixes: [ColonyFileSystem.VirtualPath]

        public init(
            allowedRoot: URL,
            deniedPrefixes: [ColonyFileSystem.VirtualPath] = []
        ) throws {
            guard allowedRoot.isFileURL else {
                throw ColonyShell.ExecutionError.invalidConfinementRoot("Confinement root must be a file URL.")
            }
            self.allowedRoot = allowedRoot.resolvingSymlinksInPath().standardizedFileURL
            self.deniedPrefixes = deniedPrefixes
        }

        public func resolveWorkingDirectory(_ workingDirectory: ColonyFileSystem.VirtualPath?) throws -> URL {
            let requested = workingDirectory ?? .root

            for denied in deniedPrefixes where Self.hasPathPrefix(requested.rawValue, prefix: denied.rawValue) {
                throw ColonyShell.ExecutionError.workingDirectoryDenied(requested)
            }

            let relative = requested.rawValue == "/" ? "" : String(requested.rawValue.dropFirst())
            let resolved = allowedRoot
                .appendingPathComponent(relative, isDirectory: true)
                .resolvingSymlinksInPath()
                .standardizedFileURL

            guard Self.isWithinRoot(resolved, root: allowedRoot) else {
                throw ColonyShell.ExecutionError.workingDirectoryOutsideConfinement(requested)
            }
            return resolved
        }
    }
}

extension ColonyShell.ConfinementPolicy {
    private static func hasPathPrefix(_ path: String, prefix: String) -> Bool {
        if prefix == "/" { return true }
        guard path.hasPrefix(prefix) else { return false }
        if path.count == prefix.count { return true }
        let boundaryIndex = path.index(path.startIndex, offsetBy: prefix.count)
        return path[boundaryIndex] == "/"
    }

    private static func isWithinRoot(_ candidate: URL, root: URL) -> Bool {
        let candidatePath = candidate.standardizedFileURL.path
        let rootPath = root.standardizedFileURL.path
        if rootPath == "/" { return true }
        return candidatePath == rootPath || candidatePath.hasPrefix(rootPath + "/")
    }
}

