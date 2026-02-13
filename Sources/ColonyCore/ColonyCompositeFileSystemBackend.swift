import Foundation

public struct ColonyCompositeFileSystemBackend: ColonyFileSystemBackend {
    public let `default`: any ColonyFileSystemBackend
    public let routes: [ColonyVirtualPath: any ColonyFileSystemBackend]

    private let routeTable: [RouteEntry]

    public init(
        `default`: any ColonyFileSystemBackend,
        routes: [ColonyVirtualPath: any ColonyFileSystemBackend]
    ) {
        self.`default` = `default`
        self.routes = routes
        self.routeTable = routes
            .map { RouteEntry(prefix: $0.key, backend: $0.value) }
            .sorted(by: RouteEntry.moreSpecificFirst)
    }

    public func list(at path: ColonyVirtualPath) async throws -> [ColonyFileInfo] {
        let (backend, mountPrefix, backendPath) = try routedBackend(for: path)

        var results = try await backend.list(at: backendPath)
        results = try restorePrefix(mountPrefix, in: results)
        results.append(contentsOf: virtualRouteDirectories(under: path))
        return Self.mergeAndSort(results)
    }

    public func read(at path: ColonyVirtualPath) async throws -> String {
        let (backend, _, backendPath) = try routedBackend(for: path)
        return try await backend.read(at: backendPath)
    }

    public func write(at path: ColonyVirtualPath, content: String) async throws {
        let (backend, _, backendPath) = try routedBackend(for: path)
        try await backend.write(at: backendPath, content: content)
    }

    public func edit(
        at path: ColonyVirtualPath,
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

    public func glob(pattern: String) async throws -> [ColonyVirtualPath] {
        let allPattern = "*"
        var candidates: [ColonyVirtualPath] = []

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

    public func grep(pattern: String, glob: String?) async throws -> [ColonyGrepMatch] {
        guard pattern.isEmpty == false else { return [] }
        var results: [ColonyGrepMatch] = []

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
                results.append(ColonyGrepMatch(path: restoredPath, line: match.line, text: match.text))
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

extension ColonyCompositeFileSystemBackend {
    private struct RouteEntry: Sendable {
        let prefix: ColonyVirtualPath
        let backend: any ColonyFileSystemBackend

        static func moreSpecificFirst(_ lhs: RouteEntry, _ rhs: RouteEntry) -> Bool {
            let left = lhs.prefix.rawValue
            let right = rhs.prefix.rawValue
            if left.count != right.count { return left.count > right.count }
            return left.utf8.lexicographicallyPrecedes(right.utf8)
        }
    }

    private func routedBackend(
        for path: ColonyVirtualPath
    ) throws -> (backend: any ColonyFileSystemBackend, mountPrefix: ColonyVirtualPath, backendPath: ColonyVirtualPath) {
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

    private static func strippingPrefix(_ prefix: String, from rawPath: String) throws -> ColonyVirtualPath {
        if prefix == "/" { return try ColonyVirtualPath(rawPath) }
        guard hasPathPrefix(rawPath, prefix: prefix) else { return try ColonyVirtualPath(rawPath) }
        if rawPath.count == prefix.count { return .root }
        let suffix = String(rawPath.dropFirst(prefix.count))
        return try ColonyVirtualPath(suffix.isEmpty ? "/" : suffix)
    }

    private static func stripPrefix(_ prefix: String, from rawPattern: String) -> String {
        if prefix == "/" { return rawPattern }
        guard hasPathPrefix(rawPattern, prefix: prefix) else { return rawPattern }
        if rawPattern.count == prefix.count { return "/" }
        let suffix = String(rawPattern.dropFirst(prefix.count))
        return suffix.isEmpty ? "/" : suffix
    }

    private static func restoringPrefix(_ prefix: ColonyVirtualPath, to path: ColonyVirtualPath) throws -> ColonyVirtualPath {
        if prefix.rawValue == "/" { return path }
        if path.rawValue == "/" { return prefix }
        return try ColonyVirtualPath(prefix.rawValue + path.rawValue)
    }

    private func restorePrefix(_ prefix: ColonyVirtualPath, in infos: [ColonyFileInfo]) throws -> [ColonyFileInfo] {
        guard prefix.rawValue != "/" else { return infos }
        var restored: [ColonyFileInfo] = []
        restored.reserveCapacity(infos.count)
        for info in infos {
            let restoredPath = try Self.restoringPrefix(prefix, to: info.path)
            restored.append(ColonyFileInfo(path: restoredPath, isDirectory: info.isDirectory, sizeBytes: info.sizeBytes))
        }
        return restored
    }

    private func virtualRouteDirectories(under path: ColonyVirtualPath) -> [ColonyFileInfo] {
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

        var results: [ColonyFileInfo] = []
        results.reserveCapacity(dirs.count)
        for dir in dirs.sorted(by: { $0.utf8.lexicographicallyPrecedes($1.utf8) }) {
            guard let path = try? ColonyVirtualPath(dir) else { continue }
            results.append(ColonyFileInfo(path: path, isDirectory: true, sizeBytes: nil))
        }
        return results
    }
}

// MARK: - Deterministic merging

extension ColonyCompositeFileSystemBackend {
    private static func uniquePaths(_ paths: [ColonyVirtualPath]) -> [ColonyVirtualPath] {
        var byRaw: [String: ColonyVirtualPath] = [:]
        byRaw.reserveCapacity(paths.count)
        for path in paths {
            byRaw[path.rawValue] = path
        }
        return Array(byRaw.values)
    }

    private static func mergeAndSort(_ infos: [ColonyFileInfo]) -> [ColonyFileInfo] {
        var byRaw: [String: ColonyFileInfo] = [:]
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
