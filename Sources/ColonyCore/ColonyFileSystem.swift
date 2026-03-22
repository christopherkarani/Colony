import Foundation

// MARK: - Namespace

/// Namespace for Colony file-system types.
public enum ColonyFileSystem {}

// MARK: - VirtualPath

/// A normalized, slash-separated virtual path used across Colony's file system abstraction.
///
/// `VirtualPath` normalizes paths to absolute form (starting with `/`), collapses
/// duplicate slashes, and rejects `..` and `~` to prevent path traversal attacks.
/// Use `root` for the root of the virtual filesystem.
extension ColonyFileSystem {
    public struct VirtualPath: Hashable, Sendable, Codable {
        public let rawValue: String

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

        /// The root of the virtual filesystem (`/`).
        public static var root: ColonyFileSystem.VirtualPath {
            // swiftlint:disable:next force_try
            try! ColonyFileSystem.VirtualPath("/")
        }

        private static func normalize(_ input: String) throws -> String {
            if input.contains("..") || input.hasPrefix("~") {
                throw ColonyFileSystem.Error.invalidPath(input)
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

// MARK: - FileInfo

/// Metadata about a file or directory in the virtual filesystem.
extension ColonyFileSystem {
    public struct FileInfo: Sendable, Codable, Equatable {
        /// The full virtual path to this file or directory.
        public let path: ColonyFileSystem.VirtualPath
        /// True if this entry is a directory.
        public let isDirectory: Bool
        /// The size of the file in bytes, or nil for directories.
        public let sizeBytes: Int?

        public init(path: ColonyFileSystem.VirtualPath, isDirectory: Bool, sizeBytes: Int?) {
            self.path = path
            self.isDirectory = isDirectory
            self.sizeBytes = sizeBytes
        }
    }
}

// MARK: - GrepMatch

/// A single line match returned by `grep`.
extension ColonyFileSystem {
    public struct GrepMatch: Sendable, Codable, Equatable {
        /// The path of the file that contained the match.
        public let path: ColonyFileSystem.VirtualPath
        /// The 1-based line number of the match.
        public let line: Int
        /// The full text of the line containing the match.
        public let text: String

        public init(path: ColonyFileSystem.VirtualPath, line: Int, text: String) {
            self.path = path
            self.line = line
            self.text = text
        }
    }
}

// MARK: - Error

/// Errors thrown by the file system backend.
extension ColonyFileSystem {
    public enum Error: Swift.Error, Sendable, Equatable {
        /// The path contains invalid characters or a path traversal attempt.
        case invalidPath(String)
        /// The path does not exist.
        case notFound(ColonyFileSystem.VirtualPath)
        /// The path is a directory but a file was expected.
        case isDirectory(ColonyFileSystem.VirtualPath)
        /// A file already exists at this path when creating a new file.
        case alreadyExists(ColonyFileSystem.VirtualPath)
        /// A low-level I/O error occurred.
        case ioError(String)
    }
}

// MARK: - ColonyFileSystemBackend (top-level protocol)

/// The backend interface for Colony's file system abstraction.
///
/// Colony ships with two built-in implementations:
/// - `ColonyFileSystem.DiskBackend` — maps virtual paths to a real directory on disk
/// - `ColonyFileSystem.InMemoryBackend` — an ephemeral in-memory filesystem for testing
///
/// Custom backends can be implemented to provide encrypted filesystems, remote
/// storage, or sandboxed environments.
public protocol ColonyFileSystemBackend: Sendable {
    /// List the contents of a directory.
    func list(at path: ColonyFileSystem.VirtualPath) async throws -> [ColonyFileSystem.FileInfo]
    /// Read the full contents of a file.
    func read(at path: ColonyFileSystem.VirtualPath) async throws -> String
    /// Create a new file with the given contents. Fails if a file already exists at the path.
    func write(at path: ColonyFileSystem.VirtualPath, content: String) async throws
    /// Edit a file by replacing `oldString` with `newString`. Returns the number of replacements made.
    func edit(
        at path: ColonyFileSystem.VirtualPath,
        oldString: String,
        newString: String,
        replaceAll: Bool
    ) async throws -> Int
    /// Find all paths matching a glob pattern (e.g., `**/*.swift`).
    func glob(pattern: String) async throws -> [ColonyFileSystem.VirtualPath]
    /// Search file contents for a regex pattern, optionally filtered by a glob pattern.
    func grep(pattern: String, glob: String?) async throws -> [ColonyFileSystem.GrepMatch]
}

// MARK: - InMemoryBackend

/// An in-memory file system backend for testing and ephemeral environments.
///
/// All files are stored in memory and lost when the actor is deallocated.
/// Use this for unit tests or when you need a completely isolated filesystem.
public actor ColonyInMemoryFileSystemBackend: ColonyFileSystemBackend {
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

// MARK: - ColonyFileSystem.InMemoryBackend Typealias

extension ColonyFileSystem {
    public typealias InMemoryBackend = ColonyInMemoryFileSystemBackend
}

// MARK: - DiskBackend

/// A file system backend that maps virtual paths to a real directory on disk.
///
/// All paths are resolved relative to the configured `root` URL and validated
/// to ensure they do not escape the root (no symlink traversal outside `root`).
/// Use `DiskBackend` in production when the agent needs access to a real project directory.
extension ColonyFileSystem {
    public actor DiskBackend: ColonyFileSystemBackend {
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
}

