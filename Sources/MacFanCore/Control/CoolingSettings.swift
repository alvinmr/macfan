import Foundation

/// The four ways MacFan can drive the fans.
public enum CoolingMode: String, Codable, CaseIterable, Sendable {
    /// macOS controls the fans. The default, and where MacFan always returns to.
    case automatic
    /// Speed follows a temperature curve.
    case curve
    /// One constant speed.
    case fixed
    /// Every fan at its maximum.
    case max

    public var requiresHelper: Bool { self != .automatic }
}

/// Which temperature a curve reacts to.
public enum TemperatureSource: Hashable, Codable, Sendable {
    case hottestCPU
    case hottestGPU
    case hottestOverall
    case sensor(id: String)

    /// Resolves to a temperature. CPU/GPU fall back to the overall hottest if absent
    /// (e.g. a Mac with no discrete GPU sensor), so a curve never runs blind.
    public func temperature(in snapshot: HardwareSnapshot) -> Double? {
        switch self {
        case .hottestCPU:
            snapshot.hottest(in: [.cpu])?.celsius ?? snapshot.hottest()?.celsius
        case .hottestGPU:
            snapshot.hottest(in: [.gpu])?.celsius ?? snapshot.hottest()?.celsius
        case .hottestOverall:
            snapshot.hottest()?.celsius
        case .sensor(let id):
            snapshot.reading(id: id)?.celsius
        }
    }
}

/// Everything the user chose about cooling. Switching mode keeps the others' settings.
public struct CoolingSettings: Hashable, Codable, Sendable {
    public var mode: CoolingMode = .automatic
    public var preset: CurvePreset = .balanced
    public var customCurve: FanCurve = CurvePreset.balanced.curve!
    public var source: TemperatureSource = .hottestCPU
    /// 0…1, used by `.fixed`.
    public var fixedSpeed: Double = 0.5

    public init() {}

    public var activeCurve: FanCurve {
        preset.curve ?? customCurve
    }
}
