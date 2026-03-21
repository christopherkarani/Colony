/// Type-safe USD cost value.
public struct ColonyCost: Hashable, Codable, Sendable,
                          Comparable, ExpressibleByFloatLiteral,
                          CustomStringConvertible, AdditiveArithmetic {
    public let rawValue: Double

    public init(_ rawValue: Double) { self.rawValue = rawValue }
    public init(floatLiteral value: Double) { self.init(value) }
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.rawValue = try container.decode(Double.self)
    }
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
    public var description: String { "$\(rawValue)" }
    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
    public static var zero: Self { .init(0) }
    public static func + (lhs: Self, rhs: Self) -> Self { .init(lhs.rawValue + rhs.rawValue) }
    public static func - (lhs: Self, rhs: Self) -> Self { .init(lhs.rawValue - rhs.rawValue) }
}

/// Type-safe token count.
public struct ColonyTokenCount: Hashable, Codable, Sendable,
                                 Comparable, ExpressibleByIntegerLiteral,
                                 CustomStringConvertible, AdditiveArithmetic {
    public let rawValue: Int

    public init(_ rawValue: Int) { self.rawValue = rawValue }
    public init(integerLiteral value: Int) { self.init(value) }
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.rawValue = try container.decode(Int.self)
    }
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
    public var description: String { "\(rawValue) tokens" }
    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
    public static var zero: Self { .init(0) }
    public static func + (lhs: Self, rhs: Self) -> Self { .init(lhs.rawValue + rhs.rawValue) }
    public static func - (lhs: Self, rhs: Self) -> Self { .init(lhs.rawValue - rhs.rawValue) }
}
