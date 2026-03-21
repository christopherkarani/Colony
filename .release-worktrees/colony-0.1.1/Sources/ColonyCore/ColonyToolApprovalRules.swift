import Foundation

public enum ColonyToolApprovalRuleDecision: String, Codable, Sendable, Equatable {
    case allowOnce = "allow_once"
    case allowAlways = "allow_always"
    case rejectAlways = "reject_always"
}

public enum ColonyToolApprovalPattern: Codable, Sendable, Equatable {
    case exact(String)
    case prefix(String)
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

public struct ColonyToolApprovalRule: Codable, Sendable, Equatable {
    public var id: String
    public var pattern: ColonyToolApprovalPattern
    public var decision: ColonyToolApprovalRuleDecision
    public var createdAt: Date
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

public struct ColonyMatchedToolApprovalRule: Sendable, Equatable {
    public var ruleID: String
    public var decision: ColonyToolApprovalRuleDecision

    public init(ruleID: String, decision: ColonyToolApprovalRuleDecision) {
        self.ruleID = ruleID
        self.decision = decision
    }
}

public protocol ColonyToolApprovalRuleStore: Sendable {
    func listRules() async throws -> [ColonyToolApprovalRule]
    func upsertRule(_ rule: ColonyToolApprovalRule) async throws
    func removeRule(id: String) async throws
    func resolveDecision(forToolName toolName: String, consumeOneShot: Bool) async throws -> ColonyMatchedToolApprovalRule?
}

public actor ColonyInMemoryToolApprovalRuleStore: ColonyToolApprovalRuleStore {
    private var rulesByID: [String: ColonyToolApprovalRule] = [:]

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
