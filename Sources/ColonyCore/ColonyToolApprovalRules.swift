import Foundation

/// The outcome of a rule match in the tool approval rule store.
public enum ColonyToolApprovalRuleDecision: String, Codable, Sendable, Equatable {
    /// Auto-approve this tool call once; remove the rule after use.
    case allowOnce = "allow_once"
    /// Auto-approve this tool call every time; rule persists indefinitely.
    case allowAlways = "allow_always"
    /// Always reject this tool call regardless of other rules.
    case rejectAlways = "reject_always"
}

/// The pattern used to match a tool name against a rule.
public enum ColonyToolApprovalPattern: Codable, Sendable, Equatable {
    /// Match an exact tool name string (case-sensitive).
    case exact(String)
    /// Match any tool name with the given prefix.
    case prefix(String)
    /// Match tool names against a glob pattern (`*` and `?` wildcards).
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

/// A named rule that matches tool calls by pattern and controls their approval decision.
///
/// Rules are matched in specificity order: `.exact` > `.prefix` > `.glob`. Within the same
/// specificity, newer rules (by `updatedAt`) take precedence.
public struct ColonyToolApprovalRule: Codable, Sendable, Equatable {
    /// Unique identifier for this rule.
    public var id: String
    /// The pattern used to match tool names.
    public var pattern: ColonyToolApprovalPattern
    /// The decision to apply when this rule matches.
    public var decision: ColonyToolApprovalRuleDecision
    /// When this rule was created.
    public var createdAt: Date
    /// When this rule was last modified.
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

/// The result of resolving a tool approval rule decision.
public struct ColonyMatchedToolApprovalRule: Sendable, Equatable {
    /// The ID of the rule that matched.
    public var ruleID: String
    /// The decision from the matched rule.
    public var decision: ColonyToolApprovalRuleDecision

    public init(ruleID: String, decision: ColonyToolApprovalRuleDecision) {
        self.ruleID = ruleID
        self.decision = decision
    }
}

/// A persistent store for tool approval rules that supports listing, upserting, and resolving decisions.
///
/// Use `ColonyInMemoryToolApprovalRuleStore` for testing or ephemeral environments,
/// and `ColonyFileToolApprovalRuleStore` for durable rule persistence.
public protocol ColonyToolApprovalRuleStore: Sendable {
    /// List all rules in specificity order.
    func listRules() async throws -> [ColonyToolApprovalRule]
    /// Create or update a rule by ID.
    func upsertRule(_ rule: ColonyToolApprovalRule) async throws
    /// Remove a rule by ID.
    func removeRule(id: String) async throws
    /// Resolve the first matching rule for a tool name. If `consumeOneShot` is true
    /// and the rule is `.allowOnce`, the rule is deleted after being applied.
    func resolveDecision(forToolName toolName: String, consumeOneShot: Bool) async throws -> ColonyMatchedToolApprovalRule?
}

package actor ColonyInMemoryToolApprovalRuleStore: ColonyToolApprovalRuleStore {
    private var rulesByID: [String: ColonyToolApprovalRule] = [:]

    package init(rules: [ColonyToolApprovalRule] = []) {
        for rule in rules {
            rulesByID[rule.id] = rule
        }
    }

    package func listRules() async throws -> [ColonyToolApprovalRule] {
        rulesByID.values.sorted(by: ruleOrder)
    }

    package func upsertRule(_ rule: ColonyToolApprovalRule) async throws {
        rulesByID[rule.id] = ColonyToolApprovalRule(
            id: rule.id,
            pattern: rule.pattern,
            decision: rule.decision,
            createdAt: rulesByID[rule.id]?.createdAt ?? rule.createdAt,
            updatedAt: Date()
        )
    }

    package func removeRule(id: String) async throws {
        rulesByID.removeValue(forKey: id)
    }

    package func resolveDecision(forToolName toolName: String, consumeOneShot: Bool) async throws -> ColonyMatchedToolApprovalRule? {
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

public actor ColonyFileToolApprovalRuleStore: ColonyToolApprovalRuleStore {
    private let fileURL: URL
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

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
