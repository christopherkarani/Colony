import Foundation

public struct ColonyVirtualPath: Hashable, Sendable, Codable {
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

    public static var root: ColonyVirtualPath {
        // swiftlint:disable:next force_try
        try! ColonyVirtualPath("/")
    }

    private static func normalize(_ input: String) throws -> String {
        if input.contains("..") || input.hasPrefix("~") {
            throw ColonyFileSystemError.invalidPath(input)
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

public struct ColonyFileInfo: Sendable, Codable, Equatable {
    public let path: ColonyVirtualPath
    public let isDirectory: Bool
    public let sizeBytes: Int?

    public init(path: ColonyVirtualPath, isDirectory: Bool, sizeBytes: Int?) {
        self.path = path
        self.isDirectory = isDirectory
        self.sizeBytes = sizeBytes
    }
}

public struct ColonyGrepMatch: Sendable, Codable, Equatable {
    public let path: ColonyVirtualPath
    public let line: Int
    public let text: String

    public init(path: ColonyVirtualPath, line: Int, text: String) {
        self.path = path
        self.line = line
        self.text = text
    }
}

public enum ColonyFileSystemError: Error, Sendable, Equatable {
    case invalidPath(String)
    case notFound(ColonyVirtualPath)
    case isDirectory(ColonyVirtualPath)
    case alreadyExists(ColonyVirtualPath)
    case ioError(String)
}

public protocol ColonyFileSystemBackend: Sendable {
    func list(at path: ColonyVirtualPath) async throws -> [ColonyFileInfo]
    func read(at path: ColonyVirtualPath) async throws -> String
    func write(at path: ColonyVirtualPath, content: String) async throws
    func edit(
        at path: ColonyVirtualPath,
        oldString: String,
        newString: String,
        replaceAll: Bool
    ) async throws -> Int
    func glob(pattern: String) async throws -> [ColonyVirtualPath]
    func grep(pattern: String, glob: String?) async throws -> [ColonyGrepMatch]
}

public actor ColonyInMemoryFileSystemBackend: ColonyFileSystemBackend {
    private var files: [ColonyVirtualPath: String]

    public init(files: [ColonyVirtualPath: String] = [:]) {
        self.files = files
    }

    public func list(at path: ColonyVirtualPath) async throws -> [ColonyFileInfo] {
        let prefix = path.rawValue == "/" ? "/" : (path.rawValue + "/")
        var directories: Set<String> = []
        var results: [ColonyFileInfo] = []

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
                    ColonyFileInfo(
                        path: filePath,
                        isDirectory: false,
                        sizeBytes: content.utf8.count
                    )
                )
            }
        }

        for dir in directories {
            let dirPath = try ColonyVirtualPath(dir)
            results.append(
                ColonyFileInfo(path: dirPath, isDirectory: true, sizeBytes: nil)
            )
        }

        results.sort { lhs, rhs in lhs.path.rawValue.utf8.lexicographicallyPrecedes(rhs.path.rawValue.utf8) }
        return results
    }

    public func read(at path: ColonyVirtualPath) async throws -> String {
        guard let content = files[path] else {
            throw ColonyFileSystemError.notFound(path)
        }
        return content
    }

    public func write(at path: ColonyVirtualPath, content: String) async throws {
        if files[path] != nil {
            throw ColonyFileSystemError.alreadyExists(path)
        }
        files[path] = content
    }

    public func edit(
        at path: ColonyVirtualPath,
        oldString: String,
        newString: String,
        replaceAll: Bool
    ) async throws -> Int {
        guard let content = files[path] else {
            throw ColonyFileSystemError.notFound(path)
        }
        guard oldString.isEmpty == false else {
            throw ColonyFileSystemError.ioError("oldString must be non-empty.")
        }

        let occurrences = content.components(separatedBy: oldString).count - 1
        if occurrences == 0 {
            throw ColonyFileSystemError.ioError("No occurrences of the provided oldString were found.")
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

    public func glob(pattern: String) async throws -> [ColonyVirtualPath] {
        let matches = files.keys
            .filter { Self.matchesGlob(pattern: pattern, path: $0.rawValue) }
            .sorted { $0.rawValue.utf8.lexicographicallyPrecedes($1.rawValue.utf8) }
        return matches
    }

    public func grep(pattern: String, glob: String?) async throws -> [ColonyGrepMatch] {
        guard pattern.isEmpty == false else { return [] }
        var matches: [ColonyGrepMatch] = []

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
                    ColonyGrepMatch(path: path, line: index + 1, text: String(line))
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

public actor ColonyDiskFileSystemBackend: ColonyFileSystemBackend {
    private let root: URL
    private let fileManager: FileManager

    public init(root: URL, fileManager: FileManager = .default) {
        self.root = root
        self.fileManager = fileManager
    }

    public func list(at path: ColonyVirtualPath) async throws -> [ColonyFileInfo] {
        let url = try resolve(path, asDirectory: true)
        let keys: [URLResourceKey] = [.isDirectoryKey, .fileSizeKey]
        let children = try fileManager.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        )
        var results: [ColonyFileInfo] = []
        results.reserveCapacity(children.count)
        for child in children {
            let resource = try child.resourceValues(forKeys: Set(keys))
            let isDirectory = resource.isDirectory ?? false
            let size = isDirectory ? nil : resource.fileSize
            results.append(ColonyFileInfo(path: virtualPath(for: child), isDirectory: isDirectory, sizeBytes: size))
        }
        results.sort { lhs, rhs in lhs.path.rawValue.utf8.lexicographicallyPrecedes(rhs.path.rawValue.utf8) }
        return results
    }

    public func read(at path: ColonyVirtualPath) async throws -> String {
        let url = try resolve(path, asDirectory: false)
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            throw ColonyFileSystemError.notFound(path)
        }
        if isDirectory.boolValue {
            throw ColonyFileSystemError.isDirectory(path)
        }
        return try String(contentsOf: url, encoding: .utf8)
    }

    public func write(at path: ColonyVirtualPath, content: String) async throws {
        let url = try resolve(path, asDirectory: false)
        if fileManager.fileExists(atPath: url.path) {
            throw ColonyFileSystemError.alreadyExists(path)
        }
        let parent = url.deletingLastPathComponent()
        try fileManager.createDirectory(at: parent, withIntermediateDirectories: true, attributes: nil)
        do {
            try content.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            throw ColonyFileSystemError.ioError(error.localizedDescription)
        }
    }

    public func edit(
        at path: ColonyVirtualPath,
        oldString: String,
        newString: String,
        replaceAll: Bool
    ) async throws -> Int {
        let existing = try await read(at: path)
        guard oldString.isEmpty == false else {
            throw ColonyFileSystemError.ioError("oldString must be non-empty.")
        }
        let occurrences = existing.components(separatedBy: oldString).count - 1
        if occurrences == 0 {
            throw ColonyFileSystemError.ioError("No occurrences of the provided oldString were found.")
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
            throw ColonyFileSystemError.ioError(error.localizedDescription)
        }
        return replaceAll ? occurrences : 1
    }

    public func glob(pattern: String) async throws -> [ColonyVirtualPath] {
        let urls = try allFileURLs()
        let matched = urls.compactMap { url -> ColonyVirtualPath? in
            let virt = virtualPath(for: url)
            guard ColonyInMemoryFileSystemBackend.matchesGlob(pattern: pattern, path: virt.rawValue) else { return nil }
            return virt
        }
        return matched.sorted { $0.rawValue.utf8.lexicographicallyPrecedes($1.rawValue.utf8) }
    }

    public func grep(pattern: String, glob: String?) async throws -> [ColonyGrepMatch] {
        guard pattern.isEmpty == false else { return [] }
        let urls = try allFileURLs()
        var matches: [ColonyGrepMatch] = []
        for url in urls {
            let virt = virtualPath(for: url)
            if let glob, ColonyInMemoryFileSystemBackend.matchesGlob(pattern: glob, path: virt.rawValue) == false {
                continue
            }
            let content = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
            let lines = content.split(separator: "\n", omittingEmptySubsequences: false)
            for (index, line) in lines.enumerated() where line.contains(pattern) {
                matches.append(ColonyGrepMatch(path: virt, line: index + 1, text: String(line)))
            }
        }
        matches.sort {
            if $0.path.rawValue == $1.path.rawValue { return $0.line < $1.line }
            return $0.path.rawValue.utf8.lexicographicallyPrecedes($1.path.rawValue.utf8)
        }
        return matches
    }

    // MARK: - Internals

    private func resolve(_ path: ColonyVirtualPath, asDirectory: Bool) throws -> URL {
        let relative = path.rawValue == "/" ? "" : String(path.rawValue.dropFirst())
        let url = root.appendingPathComponent(relative, isDirectory: asDirectory).standardizedFileURL

        let rootPath = root.standardizedFileURL.path
        guard url.path.hasPrefix(rootPath) else {
            throw ColonyFileSystemError.invalidPath(path.rawValue)
        }
        return url
    }

    private func allFileURLs() throws -> [URL] {
        let rootURL = root.standardizedFileURL
        let enumerator = fileManager.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        var urls: [URL] = []
        while let next = enumerator?.nextObject() as? URL {
            let values = try next.resourceValues(forKeys: [.isDirectoryKey])
            if values.isDirectory == true { continue }
            urls.append(next)
        }
        urls.sort { lhs, rhs in
            lhs.path.utf8.lexicographicallyPrecedes(rhs.path.utf8)
        }
        return urls
    }

    private func virtualPath(for url: URL) -> ColonyVirtualPath {
        let standardized = url.standardizedFileURL
        let rootPath = root.standardizedFileURL.path
        let suffix = standardized.path.hasPrefix(rootPath) ? String(standardized.path.dropFirst(rootPath.count)) : standardized.path
        let trimmed = suffix.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        // swiftlint:disable:next force_try
        return try! ColonyVirtualPath("/" + trimmed)
    }
}
