import Foundation
@_spi(ColonyInternal) import Swarm

/// Policy for redacting sensitive information from logs and artifacts.
///
/// This policy identifies and redacts sensitive keys (like passwords, tokens, API keys)
/// and inline secrets from strings before they are logged or stored.
public struct ColonyRedactionPolicy: Sendable {
    /// Default keys that are considered sensitive.
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

    /// Keys to redact (case-insensitive matching).
    public var sensitiveKeys: Set<String>

    /// The replacement string for redacted values.
    public var replacement: String

    /// Creates a new redaction policy.
    ///
    /// - Parameters:
    ///   - sensitiveKeys: Keys to redact. Defaults to `defaultSensitiveKeys`.
    ///   - replacement: Replacement string. Defaults to `"[REDACTED]"`.
    public init(
        sensitiveKeys: Set<String> = ColonyRedactionPolicy.defaultSensitiveKeys,
        replacement: String = "[REDACTED]"
    ) {
        self.sensitiveKeys = Set(sensitiveKeys.map { $0.lowercased() })
        self.replacement = replacement
    }

    /// Redacts a value if its key is sensitive.
    ///
    /// - Parameters:
    ///   - key: The key to check.
    ///   - value: The value to potentially redact.
    /// - Returns: The redacted value if the key is sensitive, otherwise the original value.
    public func redact(key: String, value: String) -> String {
        if sensitiveKeys.contains(key.lowercased()) {
            return replacement
        }
        return redactInlineSecrets(in: value)
    }

    /// Redacts all sensitive values in a dictionary.
    ///
    /// - Parameter values: Dictionary of key-value pairs to redact.
    /// - Returns: Dictionary with sensitive values redacted.
    public func redact(values: [String: String]) -> [String: String] {
        var redacted: [String: String] = [:]
        redacted.reserveCapacity(values.count)

        for (key, value) in values {
            redacted[key] = redact(key: key, value: value)
        }

        return redacted
    }

    /// Redacts inline secrets from a string value.
    ///
    /// Detects and redacts patterns like bearer tokens, API keys, and credentials
    /// embedded in strings.
    ///
    /// - Parameter value: The string to redact.
    /// - Returns: The string with inline secrets redacted.
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

/// Internal utilities for Colony persistence operations.
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
