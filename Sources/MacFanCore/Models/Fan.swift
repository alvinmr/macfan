import Foundation

public struct FanStatus: Identifiable, Hashable, Sendable {
    public let index: Int
    public let name: String
    public let currentRPM: Double
    public let minimumRPM: Double
    public let maximumRPM: Double
    public let targetRPM: Double?
    public let isManual: Bool

    public init(
        index: Int,
        name: String,
        currentRPM: Double,
        minimumRPM: Double,
        maximumRPM: Double,
        targetRPM: Double?,
        isManual: Bool
    ) {
        self.index = index
        self.name = name
        self.currentRPM = currentRPM
        self.minimumRPM = minimumRPM
        self.maximumRPM = maximumRPM
        self.targetRPM = targetRPM
        self.isManual = isManual
    }

    public var id: Int { index }

    /// Current speed as a fraction of the maximum (0 when the fan is stopped).
    public var load: Double {
        guard maximumRPM > 0 else { return 0 }
        return min(max(currentRPM / maximumRPM, 0), 1)
    }

    /// Maps a 0…1 speed onto this fan's supported range. 0 is the fan's minimum, not "off".
    public func rpm(forSpeed speed: Double) -> Double {
        let clamped = min(max(speed, 0), 1)
        return minimumRPM + (maximumRPM - minimumRPM) * clamped
    }

    /// Human-readable fan names. A single fan is just "Fan".
    public static func name(forIndex index: Int, count: Int) -> String {
        count == 1 ? "Fan" : "Fan \(index + 1)"
    }
}
