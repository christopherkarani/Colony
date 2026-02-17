import Foundation
import ColonyCore

public enum ColonyCommandRule: Sendable, Codable, Equatable {
    case exact(String)
    case prefix(String)
    case regex(String)

    private enum CodingKeys: String, CodingKey {
        case kind
        case value
    }

    private enum Kind: String, Codable {
        case exact
        case prefix
        case regex
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .kind)
        let value = try container.decode(String.self, forKey: .value)

        switch kind {
        case .exact:
            self = .exact(value)
        case .prefix:
            self = .prefix(value)
        case .regex:
            self = .regex(value)
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .exact(let value):
            try container.encode(Kind.exact, forKey: .kind)
            try container.encode(value, forKey: .value)
        case .prefix(let value):
            try container.encode(Kind.prefix, forKey: .kind)
            try container.encode(value, forKey: .value)
        case .regex(let value):
            try container.encode(Kind.regex, forKey: .kind)
            try container.encode(value, forKey: .value)
        }
    }

    func matches(_ candidate: String) throws -> Bool {
        switch self {
        case .exact(let value):
            return candidate == value
        case .prefix(let value):
            return candidate.hasPrefix(value)
        case .regex(let pattern):
            do {
                let regex = try NSRegularExpression(pattern: pattern)
                let range = NSRange(candidate.startIndex ..< candidate.endIndex, in: candidate)
                return regex.firstMatch(in: candidate, range: range) != nil
            } catch {
                throw ColonyExecutionPolicyError.invalidCommandPattern(pattern)
            }
        }
    }
}

public struct ColonyExecutionPolicy: Sendable, Codable, Equatable {
    public var restrictToWorkspace: Bool
    public var workspaceRoot: ColonyVirtualPath?
    public var blockedCommandRules: [ColonyCommandRule]
    public var allowedCommandRules: [ColonyCommandRule]
    public var maxStdoutBytes: Int?
    public var maxRuntimeMilliseconds: Int?
    public var safeCommandOverrides: Set<String>

    public init(
        restrictToWorkspace: Bool = false,
        workspaceRoot: ColonyVirtualPath? = nil,
        blockedCommandRules: [ColonyCommandRule] = [],
        allowedCommandRules: [ColonyCommandRule] = [],
        maxStdoutBytes: Int? = nil,
        maxRuntimeMilliseconds: Int? = nil,
        safeCommandOverrides: Set<String> = []
    ) {
        self.restrictToWorkspace = restrictToWorkspace
        self.workspaceRoot = workspaceRoot
        self.blockedCommandRules = blockedCommandRules
        self.allowedCommandRules = allowedCommandRules
        self.maxStdoutBytes = maxStdoutBytes
        self.maxRuntimeMilliseconds = maxRuntimeMilliseconds
        self.safeCommandOverrides = safeCommandOverrides
    }
}

public enum ColonyExecutionPolicyError: Error, Sendable, Equatable, CustomStringConvertible {
    case workspaceRootRequired
    case pathOutsideWorkspace(path: String, workspaceRoot: String)
    case commandBlocked(String)
    case commandNotAllowed(String)
    case nondeterministicCommand(String)
    case invalidCommandPattern(String)

    public var description: String {
        switch self {
        case .workspaceRootRequired:
            return "Execution policy requires workspaceRoot when restrictToWorkspace is enabled."
        case .pathOutsideWorkspace(let path, let root):
            return "Path '\(path)' is outside workspace root '\(root)'."
        case .commandBlocked(let command):
            return "Command blocked by policy: \(command)"
        case .commandNotAllowed(let command):
            return "Command not allow-listed by policy: \(command)"
        case .nondeterministicCommand(let command):
            return "Command rejected as non-deterministic: \(command)"
        case .invalidCommandPattern(let pattern):
            return "Invalid policy regex: \(pattern)"
        }
    }
}

public struct ColonyDeterministicCommandValidator: Sendable {
    public init() {}

    public func validate(command: String, policy: ColonyExecutionPolicy) throws {
        let trimmedCommand = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedCommand.isEmpty == false else {
            throw ColonyExecutionPolicyError.commandNotAllowed(command)
        }

        // Reject shell substitution forms that can hide non-deterministic commands.
        if trimmedCommand.contains("`") || trimmedCommand.contains("$(") {
            throw ColonyExecutionPolicyError.nondeterministicCommand(trimmedCommand)
        }

        let segments = splitSegments(trimmedCommand)
        for segment in segments {
            let commandName = firstCommandToken(in: segment)
            if commandName.isEmpty {
                continue
            }

            if policy.safeCommandOverrides.contains(commandName) || policy.safeCommandOverrides.contains(segment) {
                continue
            }

            if try isBlocked(segment: segment, commandName: commandName, policy: policy) {
                throw ColonyExecutionPolicyError.commandBlocked(segment)
            }

            if try isAllowed(segment: segment, commandName: commandName, policy: policy) == false {
                throw ColonyExecutionPolicyError.commandNotAllowed(segment)
            }
        }
    }

    private func isBlocked(
        segment: String,
        commandName: String,
        policy: ColonyExecutionPolicy
    ) throws -> Bool {
        for rule in policy.blockedCommandRules {
            if try rule.matches(segment) || (try rule.matches(commandName)) {
                return true
            }
        }
        return false
    }

    private func isAllowed(
        segment: String,
        commandName: String,
        policy: ColonyExecutionPolicy
    ) throws -> Bool {
        if policy.allowedCommandRules.isEmpty {
            return true
        }

        for rule in policy.allowedCommandRules {
            if try rule.matches(segment) || (try rule.matches(commandName)) {
                return true
            }
        }
        return false
    }

    private func splitSegments(_ command: String) -> [String] {
        var segments: [String] = []
        var current = ""

        var index = command.startIndex
        while index < command.endIndex {
            let character = command[index]
            let nextIndex = command.index(after: index)
            let nextCharacter = nextIndex < command.endIndex ? command[nextIndex] : nil

            let isSeparator: Bool = {
                if character == ";" || character == "\n" || character == "|" {
                    return true
                }
                if character == "&", nextCharacter == "&" {
                    return true
                }
                if character == "|", nextCharacter == "|" {
                    return true
                }
                return false
            }()

            if isSeparator {
                let segment = current.trimmingCharacters(in: .whitespacesAndNewlines)
                if segment.isEmpty == false {
                    segments.append(segment)
                }
                current.removeAll(keepingCapacity: true)

                if character == "&" || character == "|" {
                    if nextCharacter == character {
                        index = nextIndex
                    }
                }
            } else {
                current.append(character)
            }
            index = command.index(after: index)
        }

        let finalSegment = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if finalSegment.isEmpty == false {
            segments.append(finalSegment)
        }
        return segments
    }

    private func firstCommandToken(in segment: String) -> String {
        segment
            .split(whereSeparator: \.isWhitespace)
            .first
            .map(String.init) ?? ""
    }
}

public struct ColonyPolicyAwareFileSystemBackend: ColonyFileSystemBackend, Sendable {
    public let base: any ColonyFileSystemBackend
    public let policy: ColonyExecutionPolicy

    public init(
        base: any ColonyFileSystemBackend,
        policy: ColonyExecutionPolicy
    ) {
        self.base = base
        self.policy = policy
    }

    public func list(at path: ColonyVirtualPath) async throws -> [ColonyFileInfo] {
        try assertPathAllowed(path)
        let items = try await base.list(at: path)
        return try filterToWorkspace(items) { $0.path }
    }

    public func read(at path: ColonyVirtualPath) async throws -> String {
        try assertPathAllowed(path)
        return try await base.read(at: path)
    }

    public func write(at path: ColonyVirtualPath, content: String) async throws {
        try assertPathAllowed(path)
        try await base.write(at: path, content: content)
    }

    public func edit(
        at path: ColonyVirtualPath,
        oldString: String,
        newString: String,
        replaceAll: Bool
    ) async throws -> Int {
        try assertPathAllowed(path)
        return try await base.edit(
            at: path,
            oldString: oldString,
            newString: newString,
            replaceAll: replaceAll
        )
    }

    public func glob(pattern: String) async throws -> [ColonyVirtualPath] {
        let matches = try await base.glob(pattern: pattern)
        return try filterToWorkspace(matches, path: { $0 })
    }

    public func grep(pattern: String, glob: String?) async throws -> [ColonyGrepMatch] {
        let matches = try await base.grep(pattern: pattern, glob: glob)
        return try filterToWorkspace(matches) { $0.path }
    }
}

public struct ColonyPolicyAwareShellBackend: ColonyShellBackend, Sendable {
    public let base: any ColonyShellBackend
    public let policy: ColonyExecutionPolicy
    public let validator: ColonyDeterministicCommandValidator

    public init(
        base: any ColonyShellBackend,
        policy: ColonyExecutionPolicy,
        validator: ColonyDeterministicCommandValidator = ColonyDeterministicCommandValidator()
    ) {
        self.base = base
        self.policy = policy
        self.validator = validator
    }

    public func execute(_ request: ColonyShellExecutionRequest) async throws -> ColonyShellExecutionResult {
        try validator.validate(command: request.command, policy: policy)

        var effective = request
        effective.workingDirectory = try effectiveWorkingDirectory(from: request.workingDirectory)
        effective.timeoutNanoseconds = effectiveTimeout(request.timeoutNanoseconds)

        let result = try await base.execute(effective)
        return truncateStdoutIfNeeded(result)
    }

    public func openSession(_ request: ColonyShellSessionOpenRequest) async throws -> ColonyShellSessionID {
        try validator.validate(command: request.command, policy: policy)

        var effective = request
        effective.workingDirectory = try effectiveWorkingDirectory(from: request.workingDirectory)
        return try await base.openSession(effective)
    }

    public func writeToSession(_ sessionID: ColonyShellSessionID, data: Data) async throws {
        try await base.writeToSession(sessionID, data: data)
    }

    public func readFromSession(
        _ sessionID: ColonyShellSessionID,
        maxBytes: Int,
        timeoutNanoseconds: UInt64?
    ) async throws -> ColonyShellSessionReadResult {
        try await base.readFromSession(
            sessionID,
            maxBytes: maxBytes,
            timeoutNanoseconds: timeoutNanoseconds
        )
    }

    public func closeSession(_ sessionID: ColonyShellSessionID) async {
        await base.closeSession(sessionID)
    }

    public func listSessions() async -> [ColonyShellSessionSnapshot] {
        await base.listSessions()
    }

    private func effectiveTimeout(_ requested: UInt64?) -> UInt64? {
        guard let maxRuntimeMilliseconds = policy.maxRuntimeMilliseconds,
              maxRuntimeMilliseconds >= 0
        else {
            return requested
        }
        let policyTimeout = UInt64(maxRuntimeMilliseconds) * 1_000_000
        guard let requested else { return policyTimeout }
        return min(requested, policyTimeout)
    }

    private func truncateStdoutIfNeeded(_ result: ColonyShellExecutionResult) -> ColonyShellExecutionResult {
        guard let maxStdoutBytes = policy.maxStdoutBytes,
              maxStdoutBytes > 0,
              result.stdout.utf8.count > maxStdoutBytes
        else {
            return result
        }

        let limitedData = Data(result.stdout.utf8.prefix(maxStdoutBytes))
        let limitedStdout = String(decoding: limitedData, as: UTF8.self)
        return ColonyShellExecutionResult(
            exitCode: result.exitCode,
            stdout: limitedStdout,
            stderr: result.stderr,
            wasTruncated: true
        )
    }

    private func effectiveWorkingDirectory(
        from requested: ColonyVirtualPath?
    ) throws -> ColonyVirtualPath? {
        guard policy.restrictToWorkspace else {
            return requested
        }

        guard let workspaceRoot = policy.workspaceRoot else {
            throw ColonyExecutionPolicyError.workspaceRootRequired
        }

        let candidate = requested ?? workspaceRoot
        guard Self.hasPathPrefix(candidate.rawValue, prefix: workspaceRoot.rawValue) else {
            throw ColonyExecutionPolicyError.pathOutsideWorkspace(
                path: candidate.rawValue,
                workspaceRoot: workspaceRoot.rawValue
            )
        }

        return candidate
    }
}

private extension ColonyPolicyAwareFileSystemBackend {
    func assertPathAllowed(_ path: ColonyVirtualPath) throws {
        guard policy.restrictToWorkspace else { return }
        guard let workspaceRoot = policy.workspaceRoot else {
            throw ColonyExecutionPolicyError.workspaceRootRequired
        }
        guard Self.hasPathPrefix(path.rawValue, prefix: workspaceRoot.rawValue) else {
            throw ColonyExecutionPolicyError.pathOutsideWorkspace(
                path: path.rawValue,
                workspaceRoot: workspaceRoot.rawValue
            )
        }
    }

    func filterToWorkspace<T>(
        _ values: [T],
        path: (T) -> ColonyVirtualPath
    ) throws -> [T] {
        guard policy.restrictToWorkspace else { return values }
        guard let workspaceRoot = policy.workspaceRoot else {
            throw ColonyExecutionPolicyError.workspaceRootRequired
        }

        return values.filter { value in
            Self.hasPathPrefix(path(value).rawValue, prefix: workspaceRoot.rawValue)
        }
    }

    func filterToWorkspace<T>(
        _ values: [T],
        _ path: (T) -> ColonyVirtualPath
    ) throws -> [T] {
        try filterToWorkspace(values, path: path)
    }

    static func hasPathPrefix(_ path: String, prefix: String) -> Bool {
        if prefix == "/" { return true }
        guard path.hasPrefix(prefix) else { return false }
        if path.count == prefix.count { return true }
        let boundary = path.index(path.startIndex, offsetBy: prefix.count)
        return path[boundary] == "/"
    }
}

private extension ColonyPolicyAwareShellBackend {
    static func hasPathPrefix(_ path: String, prefix: String) -> Bool {
        if prefix == "/" { return true }
        guard path.hasPrefix(prefix) else { return false }
        if path.count == prefix.count { return true }
        let boundary = path.index(path.startIndex, offsetBy: prefix.count)
        return path[boundary] == "/"
    }
}
