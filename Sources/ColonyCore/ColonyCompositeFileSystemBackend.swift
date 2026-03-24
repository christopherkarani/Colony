import Foundation

// MARK: - Composite Service

/// A filesystem service that routes requests to different backends based on path prefixes.
///
/// `ColonyCompositeFileSystemService` provides a mounting mechanism similar to Unix filesystems.
/// Paths are routed to different backend services based on longest-prefix matching against
/// a configured route table. Paths that don't match any route fall through to the default backend.
///
/// Example:
/// ```swift
/// let composite = ColonyCompositeFileSystemService(
///     default: diskBackend,
///     routes: [
///         ColonyFileSystem.VirtualPath.scratchbookRoot: memoryBackend,
///         try ColonyFileSystem.VirtualPath("/memory"): memoryBackend
///     ]
/// )
/// ```
public struct ColonyCompositeFileSystemService: ColonyFileSystem.Service {
    public let `default`: any ColonyFileSystem.Service
    public let routes: [ColonyFileSystem.VirtualPath: any ColonyFileSystem.Service]

    private let routeTable: [RouteEntry]

    public init(
        `default`: any ColonyFileSystem.Service,
        routes: [ColonyFileSystem.VirtualPath: any ColonyFileSystem.Service]
    ) {
        self.`default` = `default`
        self.routes = routes
        self.routeTable = routes
            .map { RouteEntry(prefix: $0.key, backend: $0.value) }
            .sorted(by: RouteEntry.moreSpecificFirst)
    }

    public func list(at path: ColonyFileSystem.VirtualPath) async throws -> [ColonyFileSystem.FileInfo] {
        let (backend, mountPrefix, backendPath) = try routedBackend(for: path)

        var results = try await backend.list(at: backendPath)
        results = try restorePrefix(mountPrefix, in: results)
        results.append(contentsOf: virtualRouteDirectories(under: path))
        return Self.mergeAndSort(results)
    }

    public func read(at path: ColonyFileSystem.VirtualPath) async throws -> String {
        let (backend, _, backendPath) = try routedBackend(for: path)
        return try await backend.read(at: backendPath)
    }

    public func write(at path: ColonyFileSystem.VirtualPath, content: String) async throws {
        let (backend, _, backendPath) = try routedBackend(for: path)
        try await backend.write(at: backendPath, content: content)
    }

    public func edit(
        at path: ColonyFileSystem.VirtualPath,
        oldString: String,
        newString: String,
        replaceAll: Bool
    ) async throws -> Int {
        let (backend, _, backendPath) = try routedBackend(for: path)
        return try await backend.edit(
            at: backendPath,
            oldString: oldString,
            newString: newString,
            replaceAll: replaceAll
        )
    }

    public func glob(pattern: String) async throws -> [ColonyFileSystem.VirtualPath] {
        let allPattern = "*"
        var candidates: [ColonyFileSystem.VirtualPath] = []

        let defaultMatches = try await `default`.glob(pattern: allPattern)
        for path in defaultMatches {
            guard bestRoute(for: path.rawValue) == nil else { continue }
            guard ColonyInMemoryFileSystemBackend.matchesGlob(pattern: pattern, path: path.rawValue) else { continue }
            candidates.append(path)
        }

        for entry in routeTable {
            let routedMatches = try await entry.backend.glob(pattern: allPattern)
            for path in routedMatches {
                let restored = try Self.restoringPrefix(entry.prefix, to: path)
                guard bestRoute(for: restored.rawValue)?.prefix == entry.prefix else { continue }
                guard ColonyInMemoryFileSystemBackend.matchesGlob(pattern: pattern, path: restored.rawValue) else { continue }
                candidates.append(restored)
            }
        }

        let unique = Self.uniquePaths(candidates)
        return unique.sorted { $0.rawValue.utf8.lexicographicallyPrecedes($1.rawValue.utf8) }
    }

    public func grep(pattern: String, glob: String?) async throws -> [ColonyFileSystem.GrepMatch] {
        guard pattern.isEmpty == false else { return [] }
        var results: [ColonyFileSystem.GrepMatch] = []

        let defaultMatches = try await `default`.grep(pattern: pattern, glob: glob)
        for match in defaultMatches {
            guard bestRoute(for: match.path.rawValue) == nil else { continue }
            if let glob, ColonyInMemoryFileSystemBackend.matchesGlob(pattern: glob, path: match.path.rawValue) == false {
                continue
            }
            results.append(match)
        }

        for entry in routeTable {
            let backendGlob = glob.flatMap { compositeGlob -> String? in
                guard Self.hasPathPrefix(compositeGlob, prefix: entry.prefix.rawValue) else { return nil }
                return Self.stripPrefix(entry.prefix.rawValue, from: compositeGlob)
            }

            let routedMatches = try await entry.backend.grep(pattern: pattern, glob: backendGlob)
            for match in routedMatches {
                let restoredPath = try Self.restoringPrefix(entry.prefix, to: match.path)
                guard bestRoute(for: restoredPath.rawValue)?.prefix == entry.prefix else { continue }
                if let glob, ColonyInMemoryFileSystemBackend.matchesGlob(pattern: glob, path: restoredPath.rawValue) == false {
                    continue
                }
                results.append(ColonyFileSystem.GrepMatch(path: restoredPath, line: match.line, text: match.text))
            }
        }

        results.sort {
            if $0.path.rawValue == $1.path.rawValue { return $0.line < $1.line }
            return $0.path.rawValue.utf8.lexicographicallyPrecedes($1.path.rawValue.utf8)
        }
        return results
    }
}

// MARK: - Routing

extension ColonyCompositeFileSystemService {
    private struct RouteEntry: Sendable {
        let prefix: ColonyFileSystem.VirtualPath
        let backend: any ColonyFileSystem.Service

        static func moreSpecificFirst(_ lhs: RouteEntry, _ rhs: RouteEntry) -> Bool {
            let left = lhs.prefix.rawValue
            let right = rhs.prefix.rawValue
            if left.count != right.count { return left.count > right.count }
            return left.utf8.lexicographicallyPrecedes(right.utf8)
        }
    }

    private func routedBackend(
        for path: ColonyFileSystem.VirtualPath
    ) throws -> (backend: any ColonyFileSystem.Service, mountPrefix: ColonyFileSystem.VirtualPath, backendPath: ColonyFileSystem.VirtualPath) {
        guard let entry = bestRoute(for: path.rawValue) else {
            return (backend: `default`, mountPrefix: .root, backendPath: path)
        }

        let backendPath = try Self.strippingPrefix(entry.prefix.rawValue, from: path.rawValue)
        return (backend: entry.backend, mountPrefix: entry.prefix, backendPath: backendPath)
    }

    private func bestRoute(for rawPath: String) -> RouteEntry? {
        for entry in routeTable where Self.hasPathPrefix(rawPath, prefix: entry.prefix.rawValue) {
            return entry
        }
        return nil
    }

    private static func hasPathPrefix(_ path: String, prefix: String) -> Bool {
        if prefix == "/" { return true }
        guard path.hasPrefix(prefix) else { return false }
        if path.count == prefix.count { return true }
        let idx = path.index(path.startIndex, offsetBy: prefix.count)
        return path[idx] == "/"
    }

    private static func strippingPrefix(_ prefix: String, from rawPath: String) throws -> ColonyFileSystem.VirtualPath {
        if prefix == "/" { return try ColonyFileSystem.VirtualPath(rawPath) }
        guard hasPathPrefix(rawPath, prefix: prefix) else { return try ColonyFileSystem.VirtualPath(rawPath) }
        if rawPath.count == prefix.count { return .root }
        let suffix = String(rawPath.dropFirst(prefix.count))
        return try ColonyFileSystem.VirtualPath(suffix.isEmpty ? "/" : suffix)
    }

    private static func stripPrefix(_ prefix: String, from rawPattern: String) -> String {
        if prefix == "/" { return rawPattern }
        guard hasPathPrefix(rawPattern, prefix: prefix) else { return rawPattern }
        if rawPattern.count == prefix.count { return "/" }
        let suffix = String(rawPattern.dropFirst(prefix.count))
        return suffix.isEmpty ? "/" : suffix
    }

    private static func restoringPrefix(_ prefix: ColonyFileSystem.VirtualPath, to path: ColonyFileSystem.VirtualPath) throws -> ColonyFileSystem.VirtualPath {
        if prefix.rawValue == "/" { return path }
        if path.rawValue == "/" { return prefix }
        return try ColonyFileSystem.VirtualPath(prefix.rawValue + path.rawValue)
    }

    private func restorePrefix(_ prefix: ColonyFileSystem.VirtualPath, in infos: [ColonyFileSystem.FileInfo]) throws -> [ColonyFileSystem.FileInfo] {
        guard prefix.rawValue != "/" else { return infos }
        var restored: [ColonyFileSystem.FileInfo] = []
        restored.reserveCapacity(infos.count)
        for info in infos {
            let restoredPath = try Self.restoringPrefix(prefix, to: info.path)
            restored.append(ColonyFileSystem.FileInfo(path: restoredPath, isDirectory: info.isDirectory, sizeBytes: info.sizeBytes))
        }
        return restored
    }

    private func virtualRouteDirectories(under path: ColonyFileSystem.VirtualPath) -> [ColonyFileSystem.FileInfo] {
        let raw = path.rawValue
        let prefix = raw == "/" ? "/" : (raw + "/")

        var dirs: Set<String> = []
        for entry in routeTable {
            let route = entry.prefix.rawValue
            guard route != raw else { continue }
            guard route.hasPrefix(prefix) else { continue }
            let remainder = route.dropFirst(prefix.count)
            guard remainder.isEmpty == false else { continue }
            guard let firstComponent = remainder.split(separator: "/").first else { continue }
            let dirRaw = prefix == "/" ? "/" + firstComponent : prefix + firstComponent
            dirs.insert(String(dirRaw))
        }

        var results: [ColonyFileSystem.FileInfo] = []
        results.reserveCapacity(dirs.count)
        for dir in dirs.sorted(by: { $0.utf8.lexicographicallyPrecedes($1.utf8) }) {
            guard let path = try? ColonyFileSystem.VirtualPath(dir) else { continue }
            results.append(ColonyFileSystem.FileInfo(path: path, isDirectory: true, sizeBytes: nil))
        }
        return results
    }
}

// MARK: - Deterministic merging

extension ColonyCompositeFileSystemService {
    private static func uniquePaths(_ paths: [ColonyFileSystem.VirtualPath]) -> [ColonyFileSystem.VirtualPath] {
        var byRaw: [String: ColonyFileSystem.VirtualPath] = [:]
        byRaw.reserveCapacity(paths.count)
        for path in paths {
            byRaw[path.rawValue] = path
        }
        return Array(byRaw.values)
    }

    private static func mergeAndSort(_ infos: [ColonyFileSystem.FileInfo]) -> [ColonyFileSystem.FileInfo] {
        var byRaw: [String: ColonyFileSystem.FileInfo] = [:]
        byRaw.reserveCapacity(infos.count)

        for info in infos {
            let key = info.path.rawValue
            if let existing = byRaw[key] {
                if existing.isDirectory == false, info.isDirectory == true {
                    byRaw[key] = info
                }
                continue
            }
            byRaw[key] = info
        }

        var merged = Array(byRaw.values)
        merged.sort { $0.path.rawValue.utf8.lexicographicallyPrecedes($1.path.rawValue.utf8) }
        return merged
    }
}

// MARK: - Deprecated Typealiases

@available(*, deprecated, renamed: "ColonyCompositeFileSystemService")
public typealias ColonyCompositeFileSystemBackend = ColonyCompositeFileSystemService

@available(*, deprecated, renamed: "ColonyFileSystem.CompositeService")
public typealias ColonyFileSystemCompositeService = ColonyCompositeFileSystemService
