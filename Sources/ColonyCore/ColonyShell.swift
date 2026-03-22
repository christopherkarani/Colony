import Foundation

/// Namespace for shell-related types used by Colony.
public enum ColonyShell {}

// MARK: - ColonyShell.TerminalMode

/// The terminal mode for shell execution.
extension ColonyShell {
    public enum TerminalMode: String, Sendable, Codable {
        /// Use standard input/output pipes — suitable for non-interactive commands.
        case pipes
        /// Use a pseudo-terminal (PTY) — supports interactive programs with terminal features.
        case pty
    }
}

// MARK: - ColonyShell.ExecutionRequest

/// A request to execute a single shell command.
extension ColonyShell {
    public struct ExecutionRequest: Sendable, Equatable {
        /// The shell command to execute.
        public var command: String
        /// The working directory for the command. Defaults to the confinement root.
        public var workingDirectory: ColonyFileSystem.VirtualPath?
        /// Optional timeout for the command.
        public var timeout: Duration?
        /// Terminal mode — `.pipes` for batch, `.pty` for interactive.
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

/// The result of a shell command execution.
extension ColonyShell {
    public struct ExecutionResult: Sendable, Equatable {
        /// The process exit code. Zero indicates success on Unix systems.
        public var exitCode: Int32
        /// Standard output of the command.
        public var stdout: String
        /// Standard error output of the command.
        public var stderr: String
        /// True if the output was truncated due to size limits.
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

        /// Returns stdout if non-empty, otherwise stderr, for simple command output retrieval.
        public var combinedOutput: String {
            if stdout.isEmpty { return stderr }
            if stderr.isEmpty { return stdout }
            return stdout + "\n" + stderr
        }
    }
}

// MARK: - ColonyShell.SessionID

extension ColonyShell {
    /// Alias for the underlying shell session identifier.
    public typealias SessionID = ColonyShellSessionID
}

// MARK: - ColonyShell.SessionOpenRequest

/// A request to open an interactive shell session.
extension ColonyShell {
    public struct SessionOpenRequest: Sendable, Equatable {
        /// The shell command to run in the session (e.g., `/bin/bash`).
        public var command: String
        /// The working directory for the session.
        public var workingDirectory: ColonyFileSystem.VirtualPath?
        /// Idle timeout — session closes if no I/O for this duration.
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

/// The result of reading from an interactive shell session.
extension ColonyShell {
    public struct SessionReadResult: Sendable, Equatable {
        /// Bytes read from stdout since the last read.
        public var stdout: String
        /// Bytes read from stderr since the last read.
        public var stderr: String
        /// True when the process has closed and all output has been consumed.
        public var eof: Bool
        /// True if output was truncated due to size limits.
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

/// A point-in-time snapshot of an interactive shell session.
extension ColonyShell {
    public struct SessionSnapshot: Sendable, Equatable {
        /// The unique identifier for this session.
        public var id: ColonyShell.SessionID
        /// The command running in this session.
        public var command: String
        /// The working directory at session start.
        public var workingDirectory: ColonyFileSystem.VirtualPath?
        /// When the session was opened.
        public var startedAt: Date
        /// True if the session process is still running.
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

/// Errors thrown by shell execution backends.
extension ColonyShell {
    public enum ExecutionError: Error, Sendable, Equatable {
        /// The confinement root URL is not a valid file URL.
        case invalidConfinementRoot(String)
        /// The working directory path is malformed.
        case invalidWorkingDirectory(ColonyFileSystem.VirtualPath)
        /// The working directory is explicitly denied by policy.
        case workingDirectoryDenied(ColonyFileSystem.VirtualPath)
        /// The resolved working directory escapes the confinement root.
        case workingDirectoryOutsideConfinement(ColonyFileSystem.VirtualPath)
        /// The shell process failed to launch.
        case launchFailed(String)
        /// The referenced session ID does not exist.
        case sessionNotFound(ColonyShell.SessionID)
        /// This backend does not support interactive session management.
        case sessionManagementUnsupported
    }
}

// MARK: - ColonyShell.ConfinementPolicy

/// A security policy that restricts shell commands to an allowed directory tree.
///
/// The confinement policy prevents shell commands from accessing files outside the
/// configured `allowedRoot`. Use `deniedPrefixes` to block specific subdirectories.
extension ColonyShell {
    public struct ConfinementPolicy: Sendable, Equatable {
        /// The root directory that all shell commands are confined to.
        public let allowedRoot: URL
        /// Subdirectories under `allowedRoot` that are also denied even if under the root.
        public let deniedPrefixes: [ColonyFileSystem.VirtualPath]

        /// Creates a confinement policy with an allowed root directory.
        /// - Parameter deniedPrefixes: Paths under `allowedRoot` to explicitly deny.
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

        /// Resolves and validates a working directory against this policy.
        /// Returns the resolved `FileManager`-compatible URL, or throws if the path escapes confinement.
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

