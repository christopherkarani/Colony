/// A type-safe wrapper for model names that provides autocomplete for well-known models.
///
/// ```swift
/// let config = ColonyConfiguration(modelName: .foundationModels)
/// let request = ColonyModelRequest(model: .claude4Sonnet, ...)
/// ```
public struct ColonyModelName: Hashable, Codable, Sendable,
                                ExpressibleByStringLiteral,
                                RawRepresentable,
                                CustomStringConvertible {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: String) {
        self.init(rawValue: value)
    }

    public var description: String { rawValue }
}

// MARK: - Well-Known Model Names

extension ColonyModelName {
    public static let `default`: ColonyModelName = "default"
    public static let foundationModels: ColonyModelName = "foundation-models"
}
