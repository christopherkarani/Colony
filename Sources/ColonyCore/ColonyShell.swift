import Foundation

public struct ColonyShellExecutionRequest: Sendable, Equatable {
    public var command: String
    public var workingDirectory: ColonyVirtualPath?
    public var timeoutNanoseconds: UInt64?

    public init(
        command: String,
        workingDirectory: ColonyVirtualPath? = nil,
        timeoutNanoseconds: UInt64? = nil
    ) {
        self.command = command
        self.workingDirectory = workingDirectory
        self.timeoutNanoseconds = timeoutNanoseconds
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

public protocol ColonyShellBackend: Sendable {
    func execute(_ request: ColonyShellExecutionRequest) async throws -> ColonyShellExecutionResult
}
