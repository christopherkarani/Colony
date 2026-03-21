import Foundation

public struct ColonyScratchItem: Codable, Sendable, Equatable, Identifiable {
    public enum Kind: String, Codable, Sendable, Equatable {
        case note
        case todo
        case task
    }

    public enum Status: String, Codable, Sendable, Equatable {
        case open
        case inProgress = "in_progress"
        case blocked
        case done
        case archived
    }

    public let id: String
    public var kind: Kind
    public var status: Status
    public var title: String
    public var body: String
    public var tags: [String]
    public var createdAtNanoseconds: UInt64
    public var updatedAtNanoseconds: UInt64
    public var phase: String?
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

public struct ColonyScratchbook: Codable, Sendable, Equatable {
    public var items: [ColonyScratchItem]
    public var pinnedItemIDs: [ColonyScratchItem.ID]

    public init(
        items: [ColonyScratchItem] = [],
        pinnedItemIDs: [ColonyScratchItem.ID] = []
    ) {
        self.items = items
        self.pinnedItemIDs = pinnedItemIDs
    }

    public func renderView(policy: ColonyScratchbookPolicy) -> String {
        renderView(viewTokenLimit: policy.viewTokenLimit, maxRenderedItems: policy.maxRenderedItems)
    }

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
    ) -> ([ColonyScratchItem], Set<ColonyScratchItem.ID>) {
        var itemsByID: [ColonyScratchItem.ID: ColonyScratchItem] = [:]
        itemsByID.reserveCapacity(items.count)
        for item in items where itemsByID[item.id] == nil {
            itemsByID[item.id] = item
        }

        var pinnedIDs: Set<ColonyScratchItem.ID> = []
        pinnedIDs.reserveCapacity(pinnedItemIDs.count)

        var pinnedItems: [ColonyScratchItem] = []
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

        var combined: [ColonyScratchItem] = []
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

    private static func isActiveForView(_ status: ColonyScratchItem.Status) -> Bool {
        switch status {
        case .open, .inProgress, .blocked:
            return true
        case .done, .archived:
            return false
        }
    }

    private static func statusViewPriority(_ status: ColonyScratchItem.Status) -> Int {
        switch status {
        case .inProgress: return 0
        case .open: return 1
        case .blocked: return 2
        case .done: return 3
        case .archived: return 4
        }
    }

    private static func taskTodoComparator(
        _ lhs: ColonyScratchItem,
        _ rhs: ColonyScratchItem
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
        _ lhs: ColonyScratchItem,
        _ rhs: ColonyScratchItem
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
        _ item: ColonyScratchItem,
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
