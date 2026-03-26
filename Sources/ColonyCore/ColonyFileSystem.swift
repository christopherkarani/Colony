import Foundation

// MARK: - Namespace

/// Namespace for Colony's virtual filesystem types.
///
/// The virtual filesystem provides a consistent, path-based interface for file operations
/// across different backend implementations (memory, disk, etc.).
public enum ColonyFileSystem {}

// MARK: - Nested Types

extension ColonyFileSystem {
    /// A normalized, validated virtual path within Colony's filesystem.
    ///
    /// `VirtualPath` represents an absolute path within the virtual filesystem.
    /// Paths are normalized on construction: duplicate slashes are collapsed, trailing
    /// slashes are removed (except for root `/`), and `..` components are rejected.
    ///
    /// Example:
    /// ```swift
    /// let path = try ColonyFileSystem.VirtualPath("/foo/bar")
    /// let root = ColonyFileSystem.VirtualPath.root
    /// ```
    public struct VirtualPath: Hashable, Sendable, Codable {
        /// The normalized string value of the path.
        public let rawValue: String
        private init(knownNormalizedValue: String) {
            self.rawValue = knownNormalizedValue
        }

        public init(_ rawValue: String) throws {
            self.rawValue = try Self.normalize(rawValue)
        }

        public init(from decoder: any Decoder) throws {
            if let single = try? decoder.singleValueContainer(),
               let raw = try? single.decode(String.self)
            {
                self.rawValue = try Self.normalize(raw)
                return
            }

            let container = try decoder.container(keyedBy: CodingKeys.self)
            let raw = try container.decode(String.self, forKey: .rawValue)
            self.rawValue = try Self.normalize(raw)
        }

        public func encode(to encoder: any Encoder) throws {
            var container = encoder.singleValueContainer()
            try container.encode(rawValue)
        }

        private enum CodingKeys: String, CodingKey {
            case rawValue
        }

        public static var root: VirtualPath { rootPath }
        public static var scratchbookRoot: VirtualPath { scratchbookPath }
        public static var conversationHistoryRoot: VirtualPath { conversationHistoryPath }
        public static var toolAuditRoot: VirtualPath { toolAuditPath }

        private static let rootPath = VirtualPath(knownNormalizedValue: "/")
        private static let scratchbookPath = VirtualPath(knownNormalizedValue: "/scratchbook")
        private static let conversationHistoryPath = VirtualPath(knownNormalizedValue: "/conversation_history")
        private static let toolAuditPath = VirtualPath(knownNormalizedValue: "/audit/tool_decisions")

        private static func normalize(_ input: String) throws -> String {
            if input.contains("..") || input.hasPrefix("~") {
                throw Error.invalidPath(input)
            }

            var path = input.replacingOccurrences(of: "\\", with: "/")
            if path.isEmpty {
                path = "/"
            }
            if path.hasPrefix("/") == false {
                path = "/" + path
            }

            // Collapse duplicate slashes.
            while path.contains("//") {
                path = path.replacingOccurrences(of: "//", with: "/")
            }

            // Canonicalize trailing slash (keep "/" only for root).
            if path.count > 1, path.hasSuffix("/") {
                path.removeLast()
            }

            return path
        }
    }
}

extension ColonyFileSystem {
    /// Metadata about a file or directory in the virtual filesystem.
    public struct FileInfo: Sendable, Codable, Equatable {
        /// The path to this file or directory.
        public let path: VirtualPath
        /// Whether this entry is a directory.
        public let isDirectory: Bool
        /// Size in bytes, `nil` for directories.
        public let sizeBytes: Int?

        public init(path: VirtualPath, isDirectory: Bool, sizeBytes: Int?) {
            self.path = path
            self.isDirectory = isDirectory
            self.sizeBytes = sizeBytes
        }
    }
}

extension ColonyFileSystem {
    /// A single line match from a grep search.
    public struct GrepMatch: Sendable, Codable, Equatable {
        /// Path to the file containing the match.
        public let path: VirtualPath
        /// 1-based line number of the match.
        public let line: Int
        /// The full text of the matching line.
        public let text: String

        public init(path: VirtualPath, line: Int, text: String) {
            self.path = path
            self.line = line
            self.text = text
        }
    }
}

extension ColonyFileSystem {
    /// Errors that can occur during filesystem operations.
    public enum Error: Swift.Error, Sendable, Equatable {
        /// Path contains invalid components (e.g., `..`, `~`).
        case invalidPath(String)
        /// The requested path does not exist.
        case notFound(VirtualPath)
        /// The path exists but is a directory (file operation expected).
        case isDirectory(VirtualPath)
        /// The path already exists (create operation failed).
        case alreadyExists(VirtualPath)
        /// A generic I/O error with a description.
        case ioError(String)
    }
}

extension ColonyFileSystem {
    /// Protocol for filesystem service implementations.
    ///
    /// Implement this protocol to provide custom filesystem backends for Colony.
    /// The service provides a consistent interface for file operations regardless
    /// of the underlying storage mechanism.
    public protocol Service: Sendable {
        /// Lists the contents of a directory.
        ///
        /// - Parameter path: The directory path to list
        /// - Returns: Array of file info entries in the directory
        func list(at path: VirtualPath) async throws -> [FileInfo]

        /// Reads the contents of a file.
        ///
        /// - Parameter path: The file path to read
        /// - Returns: The file contents as a string
        func read(at path: VirtualPath) async throws -> String

        /// Writes content to a file (fails if file exists).
        ///
        /// - Parameters:
        ///   - path: The file path to write
        ///   - content: The content to write
        func write(at path: VirtualPath, content: String) async throws

        /// Edits a file by replacing text.
        ///
        /// - Parameters:
        ///   - path: The file path to edit
        ///   - oldString: The text to find and replace
        ///   - newString: The replacement text
        ///   - replaceAll: Whether to replace all occurrences or just the first
        /// - Returns: The number of replacements made
        func edit(
            at path: VirtualPath,
            oldString: String,
            newString: String,
            replaceAll: Bool
        ) async throws -> Int

        /// Finds paths matching a glob pattern.
        ///
        /// - Parameter pattern: Glob pattern (supports `*` and `?`)
        /// - Returns: Array of matching paths
        func glob(pattern: String) async throws -> [VirtualPath]

        /// Searches for lines matching a pattern.
        ///
        /// - Parameters:
        ///   - pattern: The text pattern to search for
        ///   - glob: Optional glob pattern to filter files
        /// - Returns: Array of matching lines with context
        func grep(pattern: String, glob: String?) async throws -> [GrepMatch]
    }
}

// MARK: - Deprecated Typealiases

public typealias ColonyVirtualPath = ColonyFileSystem.VirtualPath

public typealias ColonyFileInfo = ColonyFileSystem.FileInfo

public typealias ColonyGrepMatch = ColonyFileSystem.GrepMatch

public typealias FileSystemError = ColonyFileSystem.Error

public typealias ColonyFileSystemError = ColonyFileSystem.Error

public typealias ColonyFileSystemService = ColonyFileSystem.Service

public typealias ColonyFileSystemBackend = ColonyFileSystem.Service

// MARK: - In-Memory Backend

public actor ColonyInMemoryFileSystemBackend: ColonyFileSystem.Service {
    private var files: [ColonyFileSystem.VirtualPath: String]

    public init(files: [ColonyFileSystem.VirtualPath: String] = [:]) {
        self.files = files
    }

    public func list(at path: ColonyFileSystem.VirtualPath) async throws -> [ColonyFileSystem.FileInfo] {
        let prefix = path.rawValue == "/" ? "/" : (path.rawValue + "/")
        var directories: Set<String> = []
        var results: [ColonyFileSystem.FileInfo] = []

        for (filePath, content) in files {
            guard filePath.rawValue.hasPrefix(prefix) else { continue }
            let suffix = String(filePath.rawValue.dropFirst(prefix.count))
            guard suffix.isEmpty == false else { continue }

            if let slashIndex = suffix.firstIndex(of: "/") {
                let dirName = String(suffix[..<slashIndex])
                let dirPath = prefix + dirName
                directories.insert(dirPath)
            } else {
                results.append(
                    ColonyFileSystem.FileInfo(
                        path: filePath,
                        isDirectory: false,
                        sizeBytes: content.utf8.count
                    )
                )
            }
        }

        for dir in directories {
            let dirPath = try ColonyFileSystem.VirtualPath(dir)
            results.append(
                ColonyFileSystem.FileInfo(path: dirPath, isDirectory: true, sizeBytes: nil)
            )
        }

        results.sort { lhs, rhs in lhs.path.rawValue.utf8.lexicographicallyPrecedes(rhs.path.rawValue.utf8) }
        return results
    }

    public func read(at path: ColonyFileSystem.VirtualPath) async throws -> String {
        guard let content = files[path] else {
            throw ColonyFileSystem.Error.notFound(path)
        }
        return content
    }

    public func write(at path: ColonyFileSystem.VirtualPath, content: String) async throws {
        if files[path] != nil {
            throw ColonyFileSystem.Error.alreadyExists(path)
        }
        files[path] = content
    }

    public func edit(
        at path: ColonyFileSystem.VirtualPath,
        oldString: String,
        newString: String,
        replaceAll: Bool
    ) async throws -> Int {
        guard let content = files[path] else {
            throw ColonyFileSystem.Error.notFound(path)
        }
        guard oldString.isEmpty == false else {
            throw ColonyFileSystem.Error.ioError("oldString must be non-empty.")
        }

        let occurrences = content.components(separatedBy: oldString).count - 1
        if occurrences == 0 {
            throw ColonyFileSystem.Error.ioError("No occurrences of the provided oldString were found.")
        }

        let updated: String
        if replaceAll {
            updated = content.replacingOccurrences(of: oldString, with: newString)
        } else {
            updated = content.replacingOccurrences(of: oldString, with: newString, options: [], range: content.range(of: oldString))
        }

        files[path] = updated
        return replaceAll ? occurrences : 1
    }

    public func glob(pattern: String) async throws -> [ColonyFileSystem.VirtualPath] {
        let matches = files.keys
            .filter { Self.matchesGlob(pattern: pattern, path: $0.rawValue) }
            .sorted { $0.rawValue.utf8.lexicographicallyPrecedes($1.rawValue.utf8) }
        return matches
    }

    public func grep(pattern: String, glob: String?) async throws -> [ColonyFileSystem.GrepMatch] {
        guard pattern.isEmpty == false else { return [] }
        var matches: [ColonyFileSystem.GrepMatch] = []

        let candidatePaths = files.keys.filter { path in
            if let glob {
                return Self.matchesGlob(pattern: glob, path: path.rawValue)
            }
            return true
        }

        for path in candidatePaths {
            guard let content = files[path] else { continue }
            let lines = content.split(separator: "\n", omittingEmptySubsequences: false)
            for (index, line) in lines.enumerated() where line.contains(pattern) {
                matches.append(
                    ColonyFileSystem.GrepMatch(path: path, line: index + 1, text: String(line))
                )
            }
        }

        matches.sort {
            if $0.path.rawValue == $1.path.rawValue { return $0.line < $1.line }
            return $0.path.rawValue.utf8.lexicographicallyPrecedes($1.path.rawValue.utf8)
        }
        return matches
    }

    static func matchesGlob(pattern: String, path: String) -> Bool {
        // Minimal glob: supports "*" and "?" (no "**" special-casing in v1).
        // Deterministic fallback used by ColonyInMemoryFileSystemBackend.
        let escaped = NSRegularExpression.escapedPattern(for: pattern)
        let regexPattern = "^" + escaped
            .replacingOccurrences(of: "\\*", with: ".*")
            .replacingOccurrences(of: "\\?", with: ".") + "$"
        return (try? NSRegularExpression(pattern: regexPattern))
            .map { $0.firstMatch(in: path, range: NSRange(location: 0, length: path.utf16.count)) != nil } ?? false
    }
}

// MARK: - Disk Backend

public actor ColonyDiskFileSystemBackend: ColonyFileSystem.Service {
    private let canonicalRoot: URL
    private let fileManager: FileManager

    public init(root: URL, fileManager: FileManager = .default) {
        self.canonicalRoot = root.resolvingSymlinksInPath().standardizedFileURL
        self.fileManager = fileManager
    }

    public func list(at path: ColonyFileSystem.VirtualPath) async throws -> [ColonyFileSystem.FileInfo] {
        let url = try resolve(path, asDirectory: true)
        let keys: [URLResourceKey] = [.isDirectoryKey, .fileSizeKey]
        let children = try fileManager.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        )
        var results: [ColonyFileSystem.FileInfo] = []
        results.reserveCapacity(children.count)
        for child in children {
            let resource = try child.resourceValues(forKeys: Set(keys))
            let isDirectory = resource.isDirectory ?? false
            let size = isDirectory ? nil : resource.fileSize
            results.append(ColonyFileSystem.FileInfo(path: try virtualPath(for: child), isDirectory: isDirectory, sizeBytes: size))
        }
        results.sort { lhs, rhs in lhs.path.rawValue.utf8.lexicographicallyPrecedes(rhs.path.rawValue.utf8) }
        return results
    }

    public func read(at path: ColonyFileSystem.VirtualPath) async throws -> String {
        let url = try resolve(path, asDirectory: false)
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            throw ColonyFileSystem.Error.notFound(path)
        }
        if isDirectory.boolValue {
            throw ColonyFileSystem.Error.isDirectory(path)
        }
        return try String(contentsOf: url, encoding: .utf8)
    }

    public func write(at path: ColonyFileSystem.VirtualPath, content: String) async throws {
        let url = try resolve(path, asDirectory: false)
        let parent = url.deletingLastPathComponent()
        let resolvedParent = parent.resolvingSymlinksInPath().standardizedFileURL
        guard Self.isWithinRoot(resolvedParent, root: canonicalRoot) else {
            throw ColonyFileSystem.Error.invalidPath(path.rawValue)
        }

        if fileManager.fileExists(atPath: url.path) {
            throw ColonyFileSystem.Error.alreadyExists(path)
        }
        try fileManager.createDirectory(at: parent, withIntermediateDirectories: true, attributes: nil)
        do {
            try content.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            throw ColonyFileSystem.Error.ioError(error.localizedDescription)
        }
    }

    public func edit(
        at path: ColonyFileSystem.VirtualPath,
        oldString: String,
        newString: String,
        replaceAll: Bool
    ) async throws -> Int {
        let existing = try await read(at: path)
        guard oldString.isEmpty == false else {
            throw ColonyFileSystem.Error.ioError("oldString must be non-empty.")
        }
        let occurrences = existing.components(separatedBy: oldString).count - 1
        if occurrences == 0 {
            throw ColonyFileSystem.Error.ioError("No occurrences of the provided oldString were found.")
        }
        let updated: String
        if replaceAll {
            updated = existing.replacingOccurrences(of: oldString, with: newString)
        } else {
            updated = existing.replacingOccurrences(of: oldString, with: newString, options: [], range: existing.range(of: oldString))
        }

        let url = try resolve(path, asDirectory: false)
        do {
            try updated.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            throw ColonyFileSystem.Error.ioError(error.localizedDescription)
        }
        return replaceAll ? occurrences : 1
    }

    public func glob(pattern: String) async throws -> [ColonyFileSystem.VirtualPath] {
        let urls = try allFileURLs()
        let matched = urls.compactMap { url -> ColonyFileSystem.VirtualPath? in
            let virt = try? virtualPath(for: url)
            guard let virt else { return nil }
            guard ColonyInMemoryFileSystemBackend.matchesGlob(pattern: pattern, path: virt.rawValue) else { return nil }
            return virt
        }
        return matched.sorted { $0.rawValue.utf8.lexicographicallyPrecedes($1.rawValue.utf8) }
    }

    public func grep(pattern: String, glob: String?) async throws -> [ColonyFileSystem.GrepMatch] {
        guard pattern.isEmpty == false else { return [] }
        let urls = try allFileURLs()
        var matches: [ColonyFileSystem.GrepMatch] = []
        for url in urls {
            guard let virt = try? virtualPath(for: url) else { continue }
            if let glob, ColonyInMemoryFileSystemBackend.matchesGlob(pattern: glob, path: virt.rawValue) == false {
                continue
            }
            let content = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
            let lines = content.split(separator: "\n", omittingEmptySubsequences: false)
            for (index, line) in lines.enumerated() where line.contains(pattern) {
                matches.append(ColonyFileSystem.GrepMatch(path: virt, line: index + 1, text: String(line)))
            }
        }
        matches.sort {
            if $0.path.rawValue == $1.path.rawValue { return $0.line < $1.line }
            return $0.path.rawValue.utf8.lexicographicallyPrecedes($1.path.rawValue.utf8)
        }
        return matches
    }

    // MARK: - Internals

    private func resolve(_ path: ColonyFileSystem.VirtualPath, asDirectory: Bool) throws -> URL {
        let relative = path.rawValue == "/" ? "" : String(path.rawValue.dropFirst())
        let candidate = canonicalRoot.appendingPathComponent(relative, isDirectory: asDirectory)
        let resolved = candidate.resolvingSymlinksInPath().standardizedFileURL

        guard Self.isWithinRoot(resolved, root: canonicalRoot) else {
            throw ColonyFileSystem.Error.invalidPath(path.rawValue)
        }
        return resolved
    }

    private func allFileURLs() throws -> [URL] {
        let rootURL = canonicalRoot
        let enumerator = fileManager.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        var urls: [URL] = []
        while let next = enumerator?.nextObject() as? URL {
            let values = try next.resourceValues(forKeys: [.isDirectoryKey])
            if values.isDirectory == true { continue }
            let resolved = next.resolvingSymlinksInPath().standardizedFileURL
            guard Self.isWithinRoot(resolved, root: canonicalRoot) else { continue }
            urls.append(next)
        }
        urls.sort { lhs, rhs in
            lhs.path.utf8.lexicographicallyPrecedes(rhs.path.utf8)
        }
        return urls
    }

    private func virtualPath(for url: URL) throws -> ColonyFileSystem.VirtualPath {
        let standardized = url.standardizedFileURL
        let rootPath = canonicalRoot.path
        let fullPath = standardized.path
        let suffix: String

        if fullPath == rootPath {
            suffix = ""
        } else if fullPath.hasPrefix(rootPath + "/") {
            suffix = String(fullPath.dropFirst(rootPath.count))
        } else {
            throw ColonyFileSystem.Error.invalidPath(fullPath)
        }

        let trimmed = suffix.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return try ColonyFileSystem.VirtualPath("/" + trimmed)
    }

    private static func isWithinRoot(_ candidate: URL, root: URL) -> Bool {
        let rootPath = root.standardizedFileURL.path
        let candidatePath = candidate.standardizedFileURL.path
        if rootPath == "/" { return true }
        return candidatePath == rootPath || candidatePath.hasPrefix(rootPath + "/")
    }
}
