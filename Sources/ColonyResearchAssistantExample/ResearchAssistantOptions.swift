import Foundation
import Colony

enum ResearchAssistantModelMode: String, Sendable {
    case auto
    case foundation
    case mock
}

enum ResearchAssistantProfileOption: String, Sendable {
    case onDevice = "on-device"
    case cloud

    var colonyProfile: ColonyProfile {
        switch self {
        case .onDevice:
            return .onDevice4k
        case .cloud:
            return .cloud
        }
    }
}

enum ResearchAssistantOptionsError: Error, Equatable, CustomStringConvertible {
    case usage(String)

    var description: String {
        switch self {
        case .usage(let message):
            return message
        }
    }
}

struct ResearchAssistantOptions: Sendable, Equatable {
    var modelMode: ResearchAssistantModelMode
    var root: String
    var profile: ResearchAssistantProfileOption

    static let usage: String = """
Usage: swift run ColonyResearchAssistantExample [options]

Options:
  --model-mode auto|foundation|mock   Model selection mode (default: auto)
  --root <path>                       Workspace root to research (default: current directory)
  --profile on-device|cloud           Runtime profile (default: on-device)
  --help                              Show this help
"""

    static func parse(arguments: [String], cwd: String = FileManager.default.currentDirectoryPath) throws -> ResearchAssistantOptions {
        var modelMode: ResearchAssistantModelMode = .auto
        var profile: ResearchAssistantProfileOption = .onDevice
        var root = normalizeRootPath(cwd, cwd: cwd)

        var index = 0
        while index < arguments.count {
            let argument = arguments[index]
            switch argument {
            case "--model-mode":
                guard let value = valueAfterFlag(arguments, index: index) else {
                    throw usageError("Missing value for --model-mode.")
                }
                guard let parsed = ResearchAssistantModelMode(rawValue: value) else {
                    throw usageError("Invalid --model-mode value '\(value)'. Expected auto|foundation|mock.")
                }
                modelMode = parsed
                index += 2

            case "--root":
                guard let value = valueAfterFlag(arguments, index: index) else {
                    throw usageError("Missing value for --root.")
                }
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                guard trimmed.isEmpty == false else {
                    throw usageError("Value for --root must be non-empty.")
                }
                root = normalizeRootPath(trimmed, cwd: cwd)
                index += 2

            case "--profile":
                guard let value = valueAfterFlag(arguments, index: index) else {
                    throw usageError("Missing value for --profile.")
                }
                guard let parsed = ResearchAssistantProfileOption(rawValue: value) else {
                    throw usageError("Invalid --profile value '\(value)'. Expected on-device|cloud.")
                }
                profile = parsed
                index += 2

            case "--help", "-h":
                throw ResearchAssistantOptionsError.usage(Self.usage)

            default:
                throw usageError("Unknown argument '\(argument)'.")
            }
        }

        return ResearchAssistantOptions(
            modelMode: modelMode,
            root: root,
            profile: profile
        )
    }

    private static func valueAfterFlag(
        _ arguments: [String],
        index: Int
    ) -> String? {
        let nextIndex = index + 1
        guard arguments.indices.contains(nextIndex) else { return nil }
        let value = arguments[nextIndex]
        guard value.hasPrefix("-") == false else { return nil }
        return value
    }

    private static func normalizeRootPath(_ raw: String, cwd: String) -> String {
        let url: URL
        if raw.hasPrefix("/") {
            url = URL(fileURLWithPath: raw, isDirectory: true)
        } else {
            url = URL(fileURLWithPath: cwd, isDirectory: true)
                .appendingPathComponent(raw, isDirectory: true)
        }
        return url.standardizedFileURL.path
    }

    private static func usageError(_ message: String) -> ResearchAssistantOptionsError {
        .usage(message + "\n\n" + Self.usage)
    }
}
