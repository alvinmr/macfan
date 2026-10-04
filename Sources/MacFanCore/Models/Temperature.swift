import Foundation

/// How concerning a temperature is. Drives color, copy and safety decisions.
public enum TemperatureLevel: Int, Comparable, CaseIterable, Sendable {
    case cool
    case warm
    case hot
    case critical

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

public struct TemperatureThresholds: Hashable, Sendable {
    public let warm: Double
    public let hot: Double
    public let critical: Double

    public init(warm: Double, hot: Double, critical: Double) {
        precondition(warm < hot && hot < critical, "Thresholds must increase")
        self.warm = warm
        self.hot = hot
        self.critical = critical
    }

    public func level(for celsius: Double) -> TemperatureLevel {
        switch celsius {
        case critical...: .critical
        case hot...: .hot
        case warm...: .warm
        default: .cool
        }
    }
}

public enum TemperatureUnit: String, Codable, CaseIterable, Sendable {
    case celsius
    case fahrenheit

    public func convert(fromCelsius celsius: Double) -> Double {
        switch self {
        case .celsius: celsius
        case .fahrenheit: celsius * 9 / 5 + 32
        }
    }

    /// Converts a temperature *difference*, e.g. for "+3°" deltas.
    public func convertDelta(fromCelsius delta: Double) -> Double {
        switch self {
        case .celsius: delta
        case .fahrenheit: delta * 9 / 5
        }
    }

    public var symbol: String {
        switch self {
        case .celsius: "°C"
        case .fahrenheit: "°F"
        }
    }

    /// `52°` by default, `52°C` with `showsUnit`.
    public func format(_ celsius: Double, fractionDigits: Int = 0, showsUnit: Bool = false) -> String {
        let value = convert(fromCelsius: celsius)
        let number = value.formatted(.number.precision(.fractionLength(fractionDigits)))
        return number + (showsUnit ? symbol : "°")
    }
}
