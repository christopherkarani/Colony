import Foundation

enum ResearchPhase: String, Hashable, Sendable {
    case idle = "Ready"
    case clarifying = "Clarifying..."
    case planning = "Planning research..."
    case searching = "Searching the web..."
    case reading = "Reading pages..."
    case synthesizing = "Synthesizing findings..."
    case done = "Research complete"

    static func fromToolName(_ name: String) -> ResearchPhase {
        switch name {
        case "tavily_search": return .searching
        case "tavily_extract": return .reading
        case "write_todos", "read_todos": return .planning
        case "scratch_add", "scratch_read", "scratch_update": return .synthesizing
        default: return .searching
        }
    }
}
