import Foundation
import HiveCore

public struct ColonyRedactionPolicy: Sendable {
    public static let defaultSensitiveKeys: Set<String> = [
        "authorization",
        "api_key",
        "apikey",
        "token",
        "password",
        "secret",
        "content",
        "delta",
        "arguments_json",
    ]

    public var sensitiveKeys: Set<String>
    public var replacement: String

    public init(
        sensitiveKeys: Set<String> = ColonyRedactionPolicy.defaultSensitiveKeys,
        replacement: String = "[REDACTED]"
    ) {
        self.sensitiveKeys = Set(sensitiveKeys.map { $0.lowercased() })
        self.replacement = replacement
    }

    public func redact(key: String, value: String) -> String {
        if sensitiveKeys.contains(key.lowercased()) {
            return replacement
        }
        return redactInlineSecrets(in: value)
    }

    public func redact(values: [String: String]) -> [String: String] {
        var redacted: [String: String] = [:]
        redacted.reserveCapacity(values.count)

        for (key, value) in values {
            redacted[key] = redact(key: key, value: value)
        }

        return redacted
    }

    public func redactInlineSecrets(in value: String) -> String {
        var output = value

        output = replacing(pattern: #"(?i)(bearer\s+)([A-Za-z0-9._~+\-/]+=*)"#, in: output, withTemplate: "$1" + escapedReplacement())
        output = replacing(
            pattern: #"(?i)((?:api[_-]?key|token|password|secret|authorization)\s*[:=]\s*)([^\s,;]+)"#,
            in: output,
            withTemplate: "$1" + escapedReplacement()
        )

        return output
    }

    private func replacing(pattern: String, in value: String, withTemplate template: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return value
        }

        let range = NSRange(value.startIndex ..< value.endIndex, in: value)
        return regex.stringByReplacingMatches(in: value, options: [], range: range, withTemplate: template)
    }

    private func escapedReplacement() -> String {
        replacement
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "$", with: "\\$")
    }
}

enum ColonyPersistenceIO {
    static func ensureDirectoryExists(_ url: URL, fileManager: FileManager) throws {
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
    }

    static func writeJSON<T: Encodable>(
        _ value: T,
        to url: URL,
        encoder: JSONEncoder,
        fileManager: FileManager
    ) throws {
        let data = try encoder.encode(value)
        try ensureDirectoryExists(url.deletingLastPathComponent(), fileManager: fileManager)
        try data.write(to: url, options: [.atomic])
    }

    static func readJSON<T: Decodable>(_ type: T.Type, from url: URL, decoder: JSONDecoder) throws -> T {
        let data = try Data(contentsOf: url)
        return try decoder.decode(type, from: data)
    }

    static func listFiles(in directoryURL: URL, fileManager: FileManager) throws -> [URL] {
        guard fileManager.fileExists(atPath: directoryURL.path) else {
            return []
        }

        let entries = try fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )

        return entries.filter { url in
            (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) ?? false
        }
    }

    static func fileCreationDate(at url: URL, fileManager: FileManager) -> Date? {
        guard let attrs = try? fileManager.attributesOfItem(atPath: url.path) else {
            return nil
        }
        return attrs[.creationDate] as? Date
    }

    static func safeFileComponent(_ raw: String) -> String {
        guard raw.isEmpty == false else { return "value" }

        var output = ""
        output.reserveCapacity(raw.count)

        for scalar in raw.unicodeScalars {
            if scalar.isASCII {
                switch scalar.value {
                case 48 ... 57, 65 ... 90, 97 ... 122, 45, 95:
                    output.append(Character(scalar))
                default:
                    output.append("_")
                }
            } else {
                output.append("_")
            }
        }

        while output.hasPrefix("_") { output.removeFirst() }
        while output.hasSuffix("_") { output.removeLast() }
        return output.isEmpty ? "value" : output
    }

    static func stableThreadDirectoryName(threadID: HiveThreadID) -> String {
        let base64 = Data(threadID.rawValue.utf8)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")

        return "thread-" + base64
    }
}
