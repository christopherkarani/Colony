import Foundation

/// Terminal emulation mode for shell sessions.
public enum ColonyShellTerminalMode: String, Sendable, Codable {
    /// Simple pipes-based I/O without terminal emulation.
    case pipes
    /// PTY-based terminal with full emulation (supports colors, cursor control, etc.).
    case pty
}

/// Request to execute a shell command.
public struct ColonyShellExecutionRequest: Sendable, Equatable {
    /// The command string to execute.
    public var command: String
    /// The working directory for the command, or `nil` for inherited.
    public var workingDirectory: ColonyVirtualPath?
    /// Execution timeout in nanoseconds, or `nil` for no timeout.
    public var timeoutNanoseconds: UInt64?
    /// Terminal emulation mode, or `nil` for default (`.pipes`).
    public var terminalMode: ColonyShellTerminalMode?

    public init(
        command: String,
        workingDirectory: ColonyVirtualPath? = nil,
        timeoutNanoseconds: UInt64? = nil,
        terminalMode: ColonyShellTerminalMode? = nil
    ) {
        self.command = command
        self.workingDirectory = workingDirectory
        self.timeoutNanoseconds = timeoutNanoseconds
        self.terminalMode = terminalMode
    }
}

/// Result of a shell command execution.
public struct ColonyShellExecutionResult: Sendable, Equatable {
    /// The exit code returned by the process. `0` indicates success.
    public var exitCode: Int32
    /// Standard output from the command.
    public var stdout: String
    /// Standard error output from the command.
    public var stderr: String
    /// Whether the output was truncated due to size limits.
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

    /// Returns stdout if non-empty, otherwise stderr, otherwise empty string.
    ///
    /// Useful when a command only uses one output stream.
    public var combinedOutput: String {
        if stdout.isEmpty { return stderr }
        if stderr.isEmpty { return stdout }
        return stdout + "\n" + stderr
    }
}

// MARK: - Service Protocol

/// Response type for shell execution requests.
/// This is a typealias for backward compatibility with `ColonyShellExecutionResult`.
public typealias ColonyShellExecutionResponse = ColonyShellExecutionResult

/// Service protocol for shell execution operations.
///
/// This protocol defines the service interface for executing shell commands.
/// Implementations provide the actual execution logic, while consumers depend
/// on this abstract interface.
///
/// Migration from `ColonyShellBackend`:
/// - Replace `ColonyShellBackend` with `ColonyShellService` in new code
/// - The `execute` method signature remains compatible
public protocol ColonyShellService: Sendable {
    /// Execute a shell command and return the result.
    /// - Parameter request: The execution request containing command and options
    /// - Returns: The execution response with exit code, stdout, and stderr
    func execute(_ request: ColonyShellExecutionRequest) async throws -> ColonyShellExecutionResponse
}

/// Unique identifier for a persistent shell session.
public struct ColonyShellSessionID: Hashable, Codable, Sendable, Equatable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}

/// Request to open a new persistent shell session.
public struct ColonyShellSessionOpenRequest: Sendable, Equatable {
    /// The initial command to run in the session.
    public var command: String
    /// The working directory for the session.
    public var workingDirectory: ColonyVirtualPath?
    /// Idle timeout in nanoseconds before the session is automatically closed.

    public var idleTimeoutNanoseconds: UInt64?

    public init(
        command: String,
        workingDirectory: ColonyVirtualPath? = nil,
        idleTimeoutNanoseconds: UInt64? = nil
    ) {
        self.command = command
        self.workingDirectory = workingDirectory
        self.idleTimeoutNanoseconds = idleTimeoutNanoseconds
    }
}

/// Result from reading output from a shell session.
public struct ColonyShellSessionReadResult: Sendable, Equatable {
    /// Standard output received since the last read.
    public var stdout: String
    /// Standard error received since the last read.
    public var stderr: String
    /// Whether end-of-file has been reached (process exited).
    public var eof: Bool
    /// Whether the output was truncated due to size limits.
    public var wasTruncated: Bool

    public init(stdout: String, stderr: String = "", eof: Bool, wasTruncated: Bool = false) {
        self.stdout = stdout
        self.stderr = stderr
        self.eof = eof
        self.wasTruncated = wasTruncated
    }
}

/// Snapshot of a shell session's current state.
public struct ColonyShellSessionSnapshot: Sendable, Equatable {
    /// Unique identifier for the session.
    public var id: ColonyShellSessionID
    /// The command running in this session.
    public var command: String
    /// The working directory of the session.
    public var workingDirectory: ColonyVirtualPath?
    /// When the session was opened.
    public var startedAt: Date
    /// Whether the session's process is still running.
    public var isRunning: Bool

    public init(
        id: ColonyShellSessionID,
        command: String,
        workingDirectory: ColonyVirtualPath?,
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

/// Backend protocol for shell execution operations.
///
/// > Deprecated: Use `ColonyShellService` instead. This protocol will be removed in a future version.
///
/// The backend protocol extends `ColonyShellService` with session management capabilities.
/// For simple command execution, migrate to `ColonyShellService`.
public protocol ColonyShellBackend: ColonyShellService {
    /// Opens an interactive shell session.
    func openSession(_ request: ColonyShellSessionOpenRequest) async throws -> ColonyShellSessionID

    /// Writes data to an open shell session.
    func writeToSession(_ sessionID: ColonyShellSessionID, data: Data) async throws

    /// Reads data from an open shell session.
    func readFromSession(
        _ sessionID: ColonyShellSessionID,
        maxBytes: Int,
        timeoutNanoseconds: UInt64?
    ) async throws -> ColonyShellSessionReadResult

    /// Closes an open shell session.
    func closeSession(_ sessionID: ColonyShellSessionID) async

    /// Lists all open shell sessions.
    func listSessions() async -> [ColonyShellSessionSnapshot]
}

public extension ColonyShellBackend {
    func openSession(_ request: ColonyShellSessionOpenRequest) async throws -> ColonyShellSessionID {
        _ = request
        throw ColonyShellExecutionError.sessionManagementUnsupported
    }

    func writeToSession(_ sessionID: ColonyShellSessionID, data: Data) async throws {
        _ = sessionID
        _ = data
        throw ColonyShellExecutionError.sessionManagementUnsupported
    }

    func readFromSession(
        _ sessionID: ColonyShellSessionID,
        maxBytes: Int,
        timeoutNanoseconds: UInt64?
    ) async throws -> ColonyShellSessionReadResult {
        _ = sessionID
        _ = maxBytes
        _ = timeoutNanoseconds
        throw ColonyShellExecutionError.sessionManagementUnsupported
    }

    func closeSession(_ sessionID: ColonyShellSessionID) async {
        _ = sessionID
    }

    func listSessions() async -> [ColonyShellSessionSnapshot] {
        []
    }
}

/// Errors that can occur during shell execution.
public enum ColonyShellExecutionError: Error, Sendable, Equatable {
    /// The confinement root URL is invalid (not a file URL).
    case invalidConfinementRoot(String)
    /// The working directory path is invalid.
    case invalidWorkingDirectory(ColonyVirtualPath)
    /// The working directory is explicitly denied by policy.
    case workingDirectoryDenied(ColonyVirtualPath)
    /// The resolved working directory escapes the confinement root.
    case workingDirectoryOutsideConfinement(ColonyVirtualPath)
    /// Failed to launch the shell process.
    case launchFailed(String)
    /// The requested session does not exist.
    case sessionNotFound(ColonyShellSessionID)
    /// Session management is not supported by this backend.
    case sessionManagementUnsupported
}

/// Policy constraining shell execution to a directory subtree.
///
/// `ColonyShellConfinementPolicy` restricts shell commands to a specific directory
/// and its subdirectories, preventing access to sensitive areas of the filesystem.
public struct ColonyShellConfinementPolicy: Sendable, Equatable {
    /// The root directory that all shell commands are confined to.
    public let allowedRoot: URL
    /// Prefixes that are explicitly denied even within the root.
    public let deniedPrefixes: [ColonyVirtualPath]

    /// Creates a confinement policy with the given root directory.
    ///
    /// - Parameters:
    ///   - allowedRoot: The root URL to confine commands to
    ///   - deniedPrefixes: Paths within the root to deny access to
    /// - Throws: `ColonyShellExecutionError.invalidConfinementRoot` if root is not a file URL
    public init(
        allowedRoot: URL,
        deniedPrefixes: [ColonyVirtualPath] = []
    ) throws {
        guard allowedRoot.isFileURL else {
            throw ColonyShellExecutionError.invalidConfinementRoot("Confinement root must be a file URL.")
        }
        self.allowedRoot = allowedRoot.resolvingSymlinksInPath().standardizedFileURL
        self.deniedPrefixes = deniedPrefixes
    }

    /// Resolves a virtual working directory to a real URL within confinement.
    ///
    /// - Parameter workingDirectory: The virtual path, or `nil` for the root
    /// - Returns: The resolved URL within the confinement root
    /// - Throws: `ColonyShellExecutionError` if the path is denied or escapes confinement
    public func resolveWorkingDirectory(_ workingDirectory: ColonyVirtualPath?) throws -> URL {
        let requested = workingDirectory ?? .root

        for denied in deniedPrefixes where Self.hasPathPrefix(requested.rawValue, prefix: denied.rawValue) {
            throw ColonyShellExecutionError.workingDirectoryDenied(requested)
        }

        let relative = requested.rawValue == "/" ? "" : String(requested.rawValue.dropFirst())
        let resolved = allowedRoot
            .appendingPathComponent(relative, isDirectory: true)
            .resolvingSymlinksInPath()
            .standardizedFileURL

        guard Self.isWithinRoot(resolved, root: allowedRoot) else {
            throw ColonyShellExecutionError.workingDirectoryOutsideConfinement(requested)
        }
        return resolved
    }
}

extension ColonyShellConfinementPolicy {
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
