import Foundation

enum ResearchAssistantModelMode: String, Sendable {
    case auto
    case foundation
    case mock
}

enum ResearchAssistantProfileOption: String, Sendable {
    case onDevice = "on-device"
    case cloud
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

    static func parse(arguments: [String], cwd: String = FileManager.default.currentDirectoryPath) throws -> ResearchAssistantOptions {
        // Initial scaffold implementation; fully validated behavior is implemented after tests.
        _ = arguments
        return ResearchAssistantOptions(
            modelMode: .auto,
            root: cwd,
            profile: .onDevice
        )
    }
}
