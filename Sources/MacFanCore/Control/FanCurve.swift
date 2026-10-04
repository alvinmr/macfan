import Foundation

public struct CurvePoint: Hashable, Codable, Sendable {
    /// Degrees Celsius.
    public var temperature: Double
    /// 0…1 of the fan's range (0 = the fan's minimum speed).
    public var speed: Double

    public init(temperature: Double, speed: Double) {
        self.temperature = temperature
        self.speed = speed
    }
}

/// Maps a temperature to a fan speed by linear interpolation between points.
///
/// Invariants (enforced on every mutation):
/// - points are sorted by temperature, at least `minimumGap` degrees apart
/// - speeds never decrease as temperature rises — hotter never means slower
public struct FanCurve: Hashable, Codable, Sendable {
    public static let temperatureRange: ClosedRange<Double> = 30...105
    public static let minimumGap: Double = 1

    public private(set) var points: [CurvePoint]

    public init(points: [CurvePoint]) {
        precondition(points.count >= 2, "A curve needs at least two points")
        self.points = Self.normalized(points)
    }

    public init(_ pairs: [(temperature: Double, speed: Double)]) {
        self.init(points: pairs.map { CurvePoint(temperature: $0.temperature, speed: $0.speed) })
    }

    public func speed(at celsius: Double) -> Double {
        guard let first = points.first, let last = points.last else { return 1 }
        if celsius <= first.temperature { return first.speed }
        if celsius >= last.temperature { return last.speed }

        let upperIndex = points.firstIndex { $0.temperature >= celsius }!
        let lower = points[upperIndex - 1]
        let upper = points[upperIndex]
        let progress = (celsius - lower.temperature) / (upper.temperature - lower.temperature)
        return lower.speed + (upper.speed - lower.speed) * progress
    }

    /// Where point `index` may move on the temperature axis without passing its neighbours.
    public func temperatureBounds(forPointAt index: Int) -> ClosedRange<Double> {
        let lower = index == 0 ? Self.temperatureRange.lowerBound : points[index - 1].temperature + Self.minimumGap
        let upper = index == points.count - 1 ? Self.temperatureRange.upperBound : points[index + 1].temperature - Self.minimumGap
        return lower...max(lower, upper)
    }

    /// Moves a point. Temperature is clamped between neighbours; speed is clamped to 0…1
    /// and *pushes* neighbours so the curve stays non-decreasing — dragging a point up
    /// lifts the ones after it, dragging down lowers the ones before it.
    public mutating func move(pointAt index: Int, to target: CurvePoint) {
        guard points.indices.contains(index) else { return }
        let temperature = target.temperature.clamped(to: temperatureBounds(forPointAt: index))
        let speed = target.speed.clamped(to: 0...1)
        points[index] = CurvePoint(temperature: temperature, speed: speed)

        for later in points.indices where later > index {
            points[later].speed = max(points[later].speed, speed)
        }
        for earlier in points.indices where earlier < index {
            points[earlier].speed = min(points[earlier].speed, speed)
        }
    }

    static func normalized(_ input: [CurvePoint]) -> [CurvePoint] {
        var result = input
            .map { CurvePoint(temperature: $0.temperature.clamped(to: temperatureRange), speed: $0.speed.clamped(to: 0...1)) }
            .sorted { $0.temperature < $1.temperature }

        for index in result.indices.dropFirst() {
            let previous = result[index - 1]
            result[index].temperature = max(result[index].temperature, previous.temperature + minimumGap)
            result[index].speed = max(result[index].speed, previous.speed)
        }
        return result
    }
}

/// Ready-made curves. Each is a deliberate trade-off between noise and temperature.
public enum CurvePreset: String, Codable, CaseIterable, Sendable {
    case quiet
    case balanced
    case performance
    case custom

    /// `nil` for `.custom`, whose points live in `CoolingSettings.customCurve`.
    public var curve: FanCurve? {
        switch self {
        case .quiet: FanCurve([(50, 0), (65, 0.15), (78, 0.4), (88, 0.7), (95, 1)])
        case .balanced: FanCurve([(45, 0), (60, 0.25), (72, 0.5), (84, 0.8), (92, 1)])
        case .performance: FanCurve([(40, 0.15), (55, 0.4), (68, 0.7), (78, 0.9), (85, 1)])
        case .custom: nil
        }
    }
}

extension Comparable {
    public func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
