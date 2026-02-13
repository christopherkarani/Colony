import Foundation

public enum ColonyScratchbookStore {
    public static func path(
        threadID: String,
        policy: ColonyScratchbookPolicy
    ) throws -> ColonyVirtualPath {
        let sanitized = sanitizeThreadID(threadID)
        let filename = sanitized + ".json"
        return try ColonyVirtualPath(policy.pathPrefix.rawValue + "/" + filename)
    }

    public static func load(
        filesystem: any ColonyFileSystemBackend,
        threadID: String,
        policy: ColonyScratchbookPolicy
    ) async throws -> ColonyScratchbook {
        let scratchbookPath = try path(threadID: threadID, policy: policy)

        let content: String
        do {
            content = try await filesystem.read(at: scratchbookPath)
        } catch let error as ColonyFileSystemError {
            switch error {
            case .notFound:
                return ColonyScratchbook()
            default:
                throw error
            }
        }

        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return ColonyScratchbook() }

        guard let data = trimmed.data(using: .utf8) else {
            throw ColonyFileSystemError.ioError("Scratchbook file was not valid UTF-8: \(scratchbookPath.rawValue)")
        }

        return try JSONDecoder().decode(ColonyScratchbook.self, from: data)
    }

    public static func save(
        _ scratchbook: ColonyScratchbook,
        filesystem: any ColonyFileSystemBackend,
        threadID: String,
        policy: ColonyScratchbookPolicy
    ) async throws {
        let scratchbookPath = try path(threadID: threadID, policy: policy)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(scratchbook)
        let json = String(decoding: data, as: UTF8.self)

        try await writeOrOverwrite(filesystem: filesystem, path: scratchbookPath, content: json)
    }

    // MARK: - Helpers

    private static func sanitizeThreadID(_ threadID: String) -> String {
        let trimmed = threadID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return "thread" }

        var raw: String = ""
        raw.reserveCapacity(trimmed.count)

        var previousWasUnderscore = false
        for scalar in trimmed.unicodeScalars {
            let isSafeASCII: Bool = {
                guard scalar.isASCII else { return false }
                switch scalar.value {
                case 48 ... 57: return true // 0-9
                case 65 ... 90: return true // A-Z
                case 97 ... 122: return true // a-z
                case 45, 95: return true // - _
                default: return false
                }
            }()

            if isSafeASCII {
                raw.append(Character(scalar))
                previousWasUnderscore = false
            } else {
                if previousWasUnderscore { continue }
                raw.append("_")
                previousWasUnderscore = true
            }
        }

        while raw.hasPrefix("_") { raw.removeFirst() }
        while raw.hasSuffix("_") { raw.removeLast() }

        return raw.isEmpty ? "thread" : raw
    }

    private static func writeOrOverwrite(
        filesystem: any ColonyFileSystemBackend,
        path: ColonyVirtualPath,
        content: String
    ) async throws {
        do {
            try await filesystem.write(at: path, content: content)
        } catch let error as ColonyFileSystemError {
            switch error {
            case .alreadyExists:
                let existing = try await filesystem.read(at: path)
                guard existing.isEmpty == false else {
                    throw ColonyFileSystemError.ioError("Scratchbook file exists but is empty and cannot be overwritten safely: \(path.rawValue)")
                }
                _ = try await filesystem.edit(at: path, oldString: existing, newString: content, replaceAll: false)
            default:
                throw error
            }
        }
    }
}

