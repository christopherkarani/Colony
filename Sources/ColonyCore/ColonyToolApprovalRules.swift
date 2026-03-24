import Foundation

/// Decision returned when a tool approval rule is matched.
///
/// Use these decisions to control how matching tools are handled:
/// - `.allowOnce` - Permit the tool call exactly one time, then remove the rule
/// - `.allowAlways` - Permanently permit tool calls matching this rule
/// - `.rejectAlways` - Permanently reject tool calls matching this rule
public enum ColonyToolApprovalRuleDecision: String, Codable, Sendable, Equatable {
    /// Permit the tool call exactly one time. After the tool executes, the rule is removed.
    case allowOnce = "allow_once"
    /// Permit all future tool calls matching this rule without further approval.
    case allowAlways = "allow_always"
    /// Permanently reject all tool calls matching this rule.
    case rejectAlways = "reject_always"
}

/// Pattern matching strategy for tool name matching in approval rules.
///
/// Supports three matching modes:
/// - Exact match for precise tool name targeting
/// - Prefix match for all tools starting with a given string
/// - Glob pattern matching for flexible wildcard-based matching
public enum ColonyToolApprovalPattern: Codable, Sendable, Equatable {
    /// Match a tool name exactly (case-sensitive).
    case exact(String)
    /// Match all tool names that start with the given prefix.
    case prefix(String)
    /// Match tool names using a glob pattern with `*` (any characters) and `?` (single character).
    case glob(String)

    public func matches(toolName: String) -> Bool {
        switch self {
        case .exact(let value):
            return toolName == value
        case .prefix(let value):
            return toolName.hasPrefix(value)
        case .glob(let value):
            return Self.globMatches(pattern: value, input: toolName)
        }
    }

    private static func globMatches(pattern: String, input: String) -> Bool {
        let escaped = NSRegularExpression.escapedPattern(for: pattern)
        let regexPattern = "^" + escaped
            .replacingOccurrences(of: "\\*", with: ".*")
            .replacingOccurrences(of: "\\?", with: ".") + "$"
        guard let regex = try? NSRegularExpression(pattern: regexPattern) else {
            return false
        }
        let range = NSRange(input.startIndex ..< input.endIndex, in: input)
        return regex.firstMatch(in: input, options: [], range: range) != nil
    }
}

/// A rule that controls whether a tool requires approval before execution.
///
/// Rules are evaluated in priority order (exact > prefix > glob, then by most recently updated).
/// When a tool name matches a rule's pattern, the rule's decision determines whether to allow,
/// allow once, or reject the tool call.
///
/// Example:
/// ```swift
/// let rule = ColonyToolApprovalRule(
///     pattern: .prefix("dangerous_"),
///     decision: .allowOnce
/// )
/// ```
public struct ColonyToolApprovalRule: Codable, Sendable, Equatable {
    /// Unique identifier for this rule.
    public var id: String
    /// Pattern to match against tool names.
    public var pattern: ColonyToolApprovalPattern
    /// Decision to apply when this rule matches.
    public var decision: ColonyToolApprovalRuleDecision
    /// Timestamp when this rule was created.
    public var createdAt: Date
    /// Timestamp when this rule was last modified.
    public var updatedAt: Date

    public init(
        id: String = "rule:" + UUID().uuidString.lowercased(),
        pattern: ColonyToolApprovalPattern,
        decision: ColonyToolApprovalRuleDecision,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.pattern = pattern
        self.decision = decision
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

/// Result of matching a tool name against the approval rule store.
///
/// Contains the matched rule's ID and the decision to apply.
/// Returned by `ColonyToolApprovalRuleStore.resolveDecision(forToolName:consumeOneShot:)`.
public struct ColonyMatchedToolApprovalRule: Sendable, Equatable {
    /// The unique identifier of the matched rule.
    public var ruleID: String
    /// The decision to apply (allowOnce, allowAlways, or rejectAlways).
    public var decision: ColonyToolApprovalRuleDecision

    public init(ruleID: String, decision: ColonyToolApprovalRuleDecision) {
        self.ruleID = ruleID
        self.decision = decision
    }
}

/// Persistent storage for tool approval rules.
///
/// Implementations may store rules in memory, on disk, or in an external service.
/// The store supports listing, adding, updating, removing rules, and resolving
/// decisions for tool names in priority order.
public protocol ColonyToolApprovalRuleStore: Sendable {
    /// Returns all approval rules sorted by specificity and recency.
    func listRules() async throws -> [ColonyToolApprovalRule]
    /// Adds a new rule or updates an existing rule with the same ID.
    func upsertRule(_ rule: ColonyToolApprovalRule) async throws
    /// Removes the rule with the given ID.
    func removeRule(id: String) async throws
    /// Finds the first matching rule for a tool name and optionally consumes one-shot rules.
    ///
    /// - Parameters:
    ///   - toolName: The name of the tool to evaluate.
    ///   - consumeOneShot: If true, rules with `.allowOnce` decision are removed after a match.
    /// - Returns: The matched rule and its decision, or nil if no rule matches.
    func resolveDecision(forToolName toolName: String, consumeOneShot: Bool) async throws -> ColonyMatchedToolApprovalRule?
}

/// An in-memory implementation of `ColonyToolApprovalRuleStore`.
///
/// Rules are stored in memory and lost when the actor is deallocated.
/// Intended for short-lived processes or testing.
public actor ColonyInMemoryToolApprovalRuleStore: ColonyToolApprovalRuleStore {
    private var rulesByID: [String: ColonyToolApprovalRule] = [:]

    /// Creates a new in-memory rule store with optional initial rules.
    public init(rules: [ColonyToolApprovalRule] = []) {
        for rule in rules {
            rulesByID[rule.id] = rule
        }
    }

    public func listRules() async throws -> [ColonyToolApprovalRule] {
        rulesByID.values.sorted(by: ruleOrder)
    }

    public func upsertRule(_ rule: ColonyToolApprovalRule) async throws {
        rulesByID[rule.id] = ColonyToolApprovalRule(
            id: rule.id,
            pattern: rule.pattern,
            decision: rule.decision,
            createdAt: rulesByID[rule.id]?.createdAt ?? rule.createdAt,
            updatedAt: Date()
        )
    }

    public func removeRule(id: String) async throws {
        rulesByID.removeValue(forKey: id)
    }

    public func resolveDecision(forToolName toolName: String, consumeOneShot: Bool) async throws -> ColonyMatchedToolApprovalRule? {
        guard let matched = rulesByID.values
            .sorted(by: ruleOrder)
            .first(where: { $0.pattern.matches(toolName: toolName) })
        else {
            return nil
        }

        if consumeOneShot, matched.decision == .allowOnce {
            rulesByID.removeValue(forKey: matched.id)
        }

        return ColonyMatchedToolApprovalRule(ruleID: matched.id, decision: matched.decision)
    }
}

/// A file-backed implementation of `ColonyToolApprovalRuleStore`.
///
/// Rules are persisted to a JSON file on disk, enabling survival across process restarts.
/// Thread-safe writes use atomic file operations to prevent corruption.
public actor ColonyFileToolApprovalRuleStore: ColonyToolApprovalRuleStore {
    private let fileURL: URL
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    /// Creates a new file-backed rule store at the specified URL.
    ///
    /// - Parameters:
    ///   - fileURL: URL path to the JSON file storing rules.
    ///   - fileManager: File manager for disk operations (defaults to `.default`).
    public init(fileURL: URL, fileManager: FileManager = .default) {
        self.fileURL = fileURL
        self.fileManager = fileManager

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    public func listRules() async throws -> [ColonyToolApprovalRule] {
        try loadRulesFromDisk().sorted(by: ruleOrder)
    }

    public func upsertRule(_ rule: ColonyToolApprovalRule) async throws {
        var rules = try loadRulesFromDisk()

        if let index = rules.firstIndex(where: { $0.id == rule.id }) {
            var existing = rules[index]
            existing.pattern = rule.pattern
            existing.decision = rule.decision
            existing.updatedAt = Date()
            rules[index] = existing
        } else {
            rules.append(rule)
        }

        try saveRulesToDisk(rules)
    }

    public func removeRule(id: String) async throws {
        let rules = try loadRulesFromDisk().filter { $0.id != id }
        try saveRulesToDisk(rules)
    }

    public func resolveDecision(forToolName toolName: String, consumeOneShot: Bool) async throws -> ColonyMatchedToolApprovalRule? {
        var rules = try loadRulesFromDisk()

        guard let matchedIndex = rules
            .sorted(by: ruleOrder)
            .compactMap({ candidate in rules.firstIndex(where: { $0.id == candidate.id }) })
            .first(where: { rules[$0].pattern.matches(toolName: toolName) })
        else {
            return nil
        }

        let matched = rules[matchedIndex]

        if consumeOneShot, matched.decision == .allowOnce {
            rules.remove(at: matchedIndex)
            try saveRulesToDisk(rules)
        }

        return ColonyMatchedToolApprovalRule(ruleID: matched.id, decision: matched.decision)
    }

    private func loadRulesFromDisk() throws -> [ColonyToolApprovalRule] {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return []
        }

        let data = try Data(contentsOf: fileURL)
        return try decoder.decode([ColonyToolApprovalRule].self, from: data)
    }

    private func saveRulesToDisk(_ rules: [ColonyToolApprovalRule]) throws {
        try fileManager.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try encoder.encode(rules)
        try data.write(to: fileURL, options: [.atomic])
    }
}

private func ruleOrder(lhs: ColonyToolApprovalRule, rhs: ColonyToolApprovalRule) -> Bool {
    if specificity(of: lhs.pattern) != specificity(of: rhs.pattern) {
        return specificity(of: lhs.pattern) > specificity(of: rhs.pattern)
    }
    if lhs.updatedAt != rhs.updatedAt {
        return lhs.updatedAt > rhs.updatedAt
    }
    return lhs.id.utf8.lexicographicallyPrecedes(rhs.id.utf8)
}

private func specificity(of pattern: ColonyToolApprovalPattern) -> Int {
    switch pattern {
    case .exact(let value):
        return 3_000 + value.count
    case .prefix(let value):
        return 2_000 + value.count
    case .glob(let value):
        return 1_000 + value.count
    }
}
