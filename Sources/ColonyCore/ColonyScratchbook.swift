import Foundation

/// A single item in the scratchbook/workspace.
///
/// `ColonyWorkspaceItem` represents a note, todo, or task that the agent
/// can create, update, and track. Items are identified by a unique string ID
/// and contain timestamps for ordering and synchronization.
public struct ColonyWorkspaceItem: Codable, Sendable, Equatable, Identifiable {
    /// The kind of workspace item.
    public enum Kind: String, Codable, Sendable, Equatable {
        /// A free-form note or observation.
        case note
        /// A todo item without detailed tracking.
        case todo
        /// A task with phase and progress tracking.
        case task
    }

    /// The completion/active status of a workspace item.
    public enum Status: String, Codable, Sendable, Equatable {
        // Base canonical cases
        /// Item is open and active.
        case open
        /// Item is actively being worked on.
        case inProgress = "in_progress"
        /// Item is blocked by a dependency.
        case blocked
        /// Item is completed.
        case done
        /// Item is archived and hidden from default views.
        case archived

        // MARK: - Agent-friendly status names (alternative raw values)

        /// Item is active and ready to work on (canonical: open)
        case active = "active"

        /// Item is pending/start (canonical: open)
        case pending = "pending"

        /// Item is completed (canonical: done)
        case completed = "completed"

        // MARK: - Coding

        public func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
            case .open, .active, .pending:
                // All active/pending states encode as their own raw value
                try container.encode(self.rawValue)
            case .inProgress:
                try container.encode("in_progress")
            case .blocked:
                try container.encode("blocked")
            case .done, .completed:
                // Both done and completed encode as "completed"
                try container.encode(self.rawValue)
            case .archived:
                try container.encode("archived")
            }
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            let rawValue = try container.decode(String.self)
            if let status = Status(rawValue: rawValue) {
                self = status
            } else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid Status: \(rawValue)")
            }
        }
    }

    /// Unique identifier for this item.
    public let id: String
    /// The kind of this item (note, todo, or task).
    public var kind: Kind
    /// The current status of this item.
    public var status: Status
    /// Short title for this item.
    public var title: String
    /// Full body/content text.
    public var body: String
    /// Tags for categorizing this item.
    public var tags: [String]
    /// Creation timestamp in nanoseconds since epoch.
    public var createdAtNanoseconds: UInt64
    /// Last update timestamp in nanoseconds since epoch.
    public var updatedAtNanoseconds: UInt64
    /// For task items, the current phase name.
    public var phase: String?
    /// For task items, progress from 0.0 to 1.0.
    public var progress: Double?

    public init(
        id: String,
        kind: Kind,
        status: Status,
        title: String,
        body: String,
        tags: [String] = [],
        createdAtNanoseconds: UInt64,
        updatedAtNanoseconds: UInt64? = nil,
        phase: String? = nil,
        progress: Double? = nil
    ) {
        self.id = id
        self.kind = kind
        self.status = status
        self.title = title
        self.body = body
        self.tags = Self.normalizeTags(tags)
        self.createdAtNanoseconds = createdAtNanoseconds

        let resolvedUpdatedAt = updatedAtNanoseconds ?? createdAtNanoseconds
        self.updatedAtNanoseconds = max(createdAtNanoseconds, resolvedUpdatedAt)

        if kind == .task {
            let trimmedPhase = phase?.trimmingCharacters(in: .whitespacesAndNewlines)
            self.phase = trimmedPhase?.isEmpty == false ? trimmedPhase : nil
            self.progress = Self.normalizeProgress(progress)
        } else {
            self.phase = nil
            self.progress = nil
        }
    }

    // MARK: - Convenience Initializer

    /// Creates a new workspace item with automatic ID and timestamp generation.
    ///
    /// - Parameters:
    ///   - id: Optional custom ID (defaults to UUID)
    ///   - kind: The kind of item
    ///   - status: The status (defaults to `.active`)
    ///   - title: The title
    ///   - content: The content/body text
    public init(
        id: String? = nil,
        kind: Kind,
        status: Status = .active,
        title: String,
        content: String
    ) {
        let now = UInt64(Date().timeIntervalSince1970 * 1_000_000_000)
        self.id = id ?? UUID().uuidString
        self.kind = kind
        self.status = status
        self.title = title
        self.body = content
        self.tags = []
        self.createdAtNanoseconds = now
        self.updatedAtNanoseconds = now
        self.phase = nil
        self.progress = nil
    }

    // MARK: - Property Aliases

    /// Alias for `body` - the content text of the item.
    public var content: String {
        get { body }
        set { body = newValue }
    }

    /// The creation date as a `Date`.
    public var createdAt: Date {
        Date(timeIntervalSince1970: Double(createdAtNanoseconds) / 1_000_000_000)
    }

    private static func normalizeProgress(_ progress: Double?) -> Double? {
        guard let progress else { return nil }
        guard progress.isFinite else { return nil }
        return min(1.0, max(0.0, progress))
    }

    private static func normalizeTags(_ tags: [String]) -> [String] {
        tags
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.isEmpty == false }
            .map { Self.normalizeTag($0) }
            .filter { $0.isEmpty == false }
            .sorted { $0.utf8.lexicographicallyPrecedes($1.utf8) }
    }

    private static func normalizeTag(_ input: String) -> String {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return "" }

        var result: String = ""
        result.reserveCapacity(trimmed.count)

        var previousWasSeparator = false
        for scalar in trimmed.unicodeScalars {
            if scalar.properties.isWhitespace || scalar == ":" || scalar == "/" || scalar == "\\" {
                if previousWasSeparator { continue }
                result.append("_")
                previousWasSeparator = true
                continue
            }
            previousWasSeparator = false
            result.append(Character(scalar))
        }

        while result.hasPrefix("_") { result.removeFirst() }
        while result.hasSuffix("_") { result.removeLast() }
        return result
    }
}

/// A collection of workspace items representing the agent's scratchbook.
///
/// `ColonyWorkspace` holds all notes, todos, and tasks for a thread/session.
/// It provides rendering logic to produce a compact view for inclusion in the
/// system prompt, respecting token and item count limits.
public struct ColonyWorkspace: Codable, Sendable, Equatable {
    /// All items in the workspace.
    public var items: [ColonyWorkspaceItem]
    /// Ordered list of pinned item IDs.
    public var pinnedItemIDs: [ColonyWorkspaceItem.ID]

    /// Alias for `pinnedItemIDs` - the set of pinned item IDs.
    public var pinnedItems: Set<ColonyWorkspaceItem.ID> {
        get { Set(pinnedItemIDs) }
        set { pinnedItemIDs = Array(newValue) }
    }

    public init(
        items: [ColonyWorkspaceItem] = [],
        pinnedItemIDs: [ColonyWorkspaceItem.ID] = []
    ) {
        self.items = items
        self.pinnedItemIDs = pinnedItemIDs
    }

    /// Convenience initializer using `pinnedItems`.
    public init(
        items: [ColonyWorkspaceItem] = [],
        pinnedItems: Set<ColonyWorkspaceItem.ID>
    ) {
        self.items = items
        self.pinnedItemIDs = Array(pinnedItems)
    }

    /// Renders the workspace view using a policy's token and item limits.
    ///
    /// - Parameter policy: The scratchbook policy with view constraints
    /// - Returns: A compact string representation of the workspace
    public func renderView(policy: ColonyScratchbookPolicy) -> String {
        renderView(viewTokenLimit: policy.viewTokenLimit, maxRenderedItems: policy.maxRenderedItems)
    }

    /// Renders the workspace view with explicit limits.
    ///
    /// - Parameters:
    ///   - viewTokenLimit: Maximum tokens to use in the rendered view
    ///   - maxRenderedItems: Maximum number of items to include
    /// - Returns: A compact string representation of the workspace
    public func renderView(
        viewTokenLimit: Int,
        maxRenderedItems: Int
    ) -> String {
        guard viewTokenLimit > 0, maxRenderedItems > 0 else {
            return "(Scratchbook view disabled)"
        }

        guard items.isEmpty == false else { return "(Scratchbook empty)" }

        let (orderedItems, pinnedIDs) = orderedItemsForView(maxRenderedItems: maxRenderedItems)
        guard orderedItems.isEmpty == false else { return "(Scratchbook empty)" }

        var lines: [String] = []
        lines.reserveCapacity(orderedItems.count)
        for item in orderedItems {
            let isPinned = pinnedIDs.contains(item.id)
            lines.append(Self.renderLine(item, isPinned: isPinned))
        }

        let charBudget = Self.approximateCharacterLimit(forTokenLimit: viewTokenLimit)
        return Self.trimLinesToCharacterLimit(lines, characterLimit: charBudget)
    }

    // MARK: - View Ordering

    private func orderedItemsForView(
        maxRenderedItems: Int
    ) -> ([ColonyWorkspaceItem], Set<ColonyWorkspaceItem.ID>) {
        var itemsByID: [ColonyWorkspaceItem.ID: ColonyWorkspaceItem] = [:]
        itemsByID.reserveCapacity(items.count)
        for item in items where itemsByID[item.id] == nil {
            itemsByID[item.id] = item
        }

        var pinnedIDs: Set<ColonyWorkspaceItem.ID> = []
        pinnedIDs.reserveCapacity(pinnedItemIDs.count)

        var pinnedItems: [ColonyWorkspaceItem] = []
        pinnedItems.reserveCapacity(min(pinnedItemIDs.count, maxRenderedItems))

        for id in pinnedItemIDs where pinnedIDs.contains(id) == false {
            pinnedIDs.insert(id)
            if let item = itemsByID[id] {
                pinnedItems.append(item)
                if pinnedItems.count >= maxRenderedItems {
                    return (pinnedItems, pinnedIDs)
                }
            }
        }

        let remaining = items.filter { pinnedIDs.contains($0.id) == false }

        let tasks = remaining
            .filter { $0.kind == .task && Self.isActiveForView($0.status) }
            .sorted(by: Self.taskTodoComparator)

        let todos = remaining
            .filter { $0.kind == .todo && Self.isActiveForView($0.status) }
            .sorted(by: Self.taskTodoComparator)

        let notes = remaining
            .filter { $0.kind == .note && Self.isActiveForView($0.status) }
            .sorted(by: Self.noteComparator)

        var combined: [ColonyWorkspaceItem] = []
        combined.reserveCapacity(min(maxRenderedItems, pinnedItems.count + tasks.count + todos.count + notes.count))

        combined.append(contentsOf: pinnedItems)

        for item in tasks where combined.count < maxRenderedItems {
            combined.append(item)
        }
        for item in todos where combined.count < maxRenderedItems {
            combined.append(item)
        }
        for item in notes where combined.count < maxRenderedItems {
            combined.append(item)
        }

        return (combined, pinnedIDs)
    }

    private static func isActiveForView(_ status: ColonyWorkspaceItem.Status) -> Bool {
        switch status {
        case .open, .active, .pending, .inProgress, .blocked:
            return true
        case .done, .completed, .archived:
            return false
        }
    }

    private static func statusViewPriority(_ status: ColonyWorkspaceItem.Status) -> Int {
        switch status {
        case .inProgress:
            return 0
        case .open, .active, .pending:
            return 1
        case .blocked:
            return 2
        case .done, .completed:
            return 3
        case .archived:
            return 4
        }
    }

    private static func taskTodoComparator(
        _ lhs: ColonyWorkspaceItem,
        _ rhs: ColonyWorkspaceItem
    ) -> Bool {
        let lhsStatus = statusViewPriority(lhs.status)
        let rhsStatus = statusViewPriority(rhs.status)
        if lhsStatus != rhsStatus { return lhsStatus < rhsStatus }

        if lhs.updatedAtNanoseconds != rhs.updatedAtNanoseconds {
            return lhs.updatedAtNanoseconds > rhs.updatedAtNanoseconds
        }
        if lhs.createdAtNanoseconds != rhs.createdAtNanoseconds {
            return lhs.createdAtNanoseconds > rhs.createdAtNanoseconds
        }
        return lhs.id.utf8.lexicographicallyPrecedes(rhs.id.utf8)
    }

    private static func noteComparator(
        _ lhs: ColonyWorkspaceItem,
        _ rhs: ColonyWorkspaceItem
    ) -> Bool {
        if lhs.updatedAtNanoseconds != rhs.updatedAtNanoseconds {
            return lhs.updatedAtNanoseconds > rhs.updatedAtNanoseconds
        }
        if lhs.createdAtNanoseconds != rhs.createdAtNanoseconds {
            return lhs.createdAtNanoseconds > rhs.createdAtNanoseconds
        }
        return lhs.id.utf8.lexicographicallyPrecedes(rhs.id.utf8)
    }

    // MARK: - View Rendering

    private static func renderLine(
        _ item: ColonyWorkspaceItem,
        isPinned: Bool
    ) -> String {
        let prefix = isPinned ? "PINNED " : ""

        let title = normalizeSingleLine(item.title)
        let body = normalizeSingleLine(item.body)
        let tags = item.tags
            .sorted { $0.utf8.lexicographicallyPrecedes($1.utf8) }
            .map { "#\($0)" }
            .joined(separator: " ")

        var extras: [String] = []
        if item.kind == .task {
            if let phase = item.phase, phase.isEmpty == false {
                extras.append("phase=\(normalizeSingleLine(phase))")
            }
            if let progress = item.progress, progress.isFinite {
                let percent = Int((min(1.0, max(0.0, progress)) * 100.0).rounded())
                extras.append("progress=\(percent)%")
            }
        }

        var line = "\(prefix)[\(item.kind.rawValue)/\(item.status.rawValue)] \(item.id): \(title)"
        if extras.isEmpty == false {
            line += " (" + extras.joined(separator: ", ") + ")"
        }

        if body.isEmpty == false {
            let bodyLimit = isPinned ? 240 : 160
            line += " — " + truncate(body, maxCharacters: bodyLimit)
        }

        if tags.isEmpty == false {
            line += " " + tags
        }

        return line
    }

    private static func normalizeSingleLine(_ input: String) -> String {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return "" }

        var result: String = ""
        result.reserveCapacity(trimmed.count)

        var previousWasWhitespace = false
        for scalar in trimmed.unicodeScalars {
            if scalar.properties.isWhitespace {
                if previousWasWhitespace { continue }
                result.append(" ")
                previousWasWhitespace = true
                continue
            }
            previousWasWhitespace = false
            result.append(Character(scalar))
        }

        if result.hasSuffix(" ") { result.removeLast() }
        return result
    }

    private static func truncate(_ input: String, maxCharacters: Int) -> String {
        guard maxCharacters > 0 else { return "" }
        guard input.count > maxCharacters else { return input }
        guard maxCharacters > 1 else { return "…" }
        return String(input.prefix(maxCharacters - 1)) + "…"
    }

    private static func approximateCharacterLimit(forTokenLimit tokenLimit: Int) -> Int {
        guard tokenLimit > 0 else { return 0 }
        if tokenLimit > (Int.max / 4) { return Int.max }
        return tokenLimit * 4
    }

    private static func trimLinesToCharacterLimit(
        _ lines: [String],
        characterLimit: Int
    ) -> String {
        guard characterLimit > 0 else { return "" }
        guard lines.isEmpty == false else { return "" }

        var kept: [String] = []
        kept.reserveCapacity(lines.count)

        var used = 0
        for line in lines {
            let addition = kept.isEmpty ? line.count : (1 + line.count)
            if used + addition > characterLimit {
                if kept.isEmpty {
                    return truncate(line, maxCharacters: characterLimit)
                }
                break
            }
            kept.append(line)
            used += addition
        }

        return kept.joined(separator: "\n")
    }
}

// MARK: - Deprecation Aliases (Old Names)

public typealias ColonyScratchItem = ColonyWorkspaceItem

public typealias ColonyScratchbook = ColonyWorkspace