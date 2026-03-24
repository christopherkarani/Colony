import Foundation

public enum ColonyShellTerminalMode: String, Sendable, Codable {
    case pipes
    case pty
}

public struct ColonyShellExecutionRequest: Sendable, Equatable {
    public var command: String
    public var workingDirectory: ColonyVirtualPath?
    public var timeoutNanoseconds: UInt64?
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

public struct ColonyShellExecutionResult: Sendable, Equatable {
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

public struct ColonyShellSessionID: Hashable, Codable, Sendable, Equatable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}

public struct ColonyShellSessionOpenRequest: Sendable, Equatable {
    public var command: String
    public var workingDirectory: ColonyVirtualPath?
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

public struct ColonyShellSessionReadResult: Sendable, Equatable {
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

public struct ColonyShellSessionSnapshot: Sendable, Equatable {
    public var id: ColonyShellSessionID
    public var command: String
    public var workingDirectory: ColonyVirtualPath?
    public var startedAt: Date
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
@available(*, deprecated, renamed: "ColonyShellService", message: "Use ColonyShellService instead. Session management methods are being moved to a separate protocol.")
public protocol ColonyShellBackend: ColonyShellService {
    func openSession(_ request: ColonyShellSessionOpenRequest) async throws -> ColonyShellSessionID
    func writeToSession(_ sessionID: ColonyShellSessionID, data: Data) async throws
    func readFromSession(
        _ sessionID: ColonyShellSessionID,
        maxBytes: Int,
        timeoutNanoseconds: UInt64?
    ) async throws -> ColonyShellSessionReadResult
    func closeSession(_ sessionID: ColonyShellSessionID) async
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

public enum ColonyShellExecutionError: Error, Sendable, Equatable {
    case invalidConfinementRoot(String)
    case invalidWorkingDirectory(ColonyVirtualPath)
    case workingDirectoryDenied(ColonyVirtualPath)
    case workingDirectoryOutsideConfinement(ColonyVirtualPath)
    case launchFailed(String)
    case sessionNotFound(ColonyShellSessionID)
    case sessionManagementUnsupported
}

public struct ColonyShellConfinementPolicy: Sendable, Equatable {
    public let allowedRoot: URL
    public let deniedPrefixes: [ColonyVirtualPath]

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
