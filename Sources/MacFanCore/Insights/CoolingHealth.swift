import Foundation

/// How hard the Mac had to work to stay cool under one steady workload, for one minute.
public struct CoolingSample: Hashable, Sendable {
    public let date: Date
    /// System watts, or the whole Mac's CPU share (0…100) on Macs without a power sensor.
    public let load: Double
    /// Hottest CPU minus the coolest air or surface sensor, so the room's temperature
    /// matters less. Without such a sensor, the CPU's own temperature.
    public let rise: Double
    /// Average across fans; `nil` on Macs without fans.
    public let fanRPM: Double?
}

/// Collects `CoolingSample`s from snapshots: one per minute, and only from minutes worth
/// comparing over weeks. A minute is skipped when its average workload differs a lot from
/// the minute before, when someone other than macOS was driving the fans, or soon after the
/// Mac woke or MacFan started.
///
/// Steadiness is judged minute to minute, not within the minute: power on Apple Silicon
/// jumps around from second to second, but chips heat up over tens of seconds, so what
/// matters is that the average stayed put.
public struct CoolingSampler: Sendable {
    public static let window: TimeInterval = 60
    /// Temperatures need a few minutes to settle after a wake or a launch.
    public static let settleTime: TimeInterval = 300
    /// A gap in readings longer than this is treated as the Mac having slept.
    public static let maximumGap: TimeInterval = 30

    private var settledFrom: Date?
    private var lastUpdate: Date?
    private var windowStart: Date?
    private var window = Window()
    private var previousLoad: Double?

    /// Running totals for the current minute, so a refresh costs a few additions.
    private struct Window: Sendable {
        var count = 0
        var loadSum = 0.0
        var riseSum = 0.0
        var rpmSum = 0.0
        var rpmCount = 0
        var isValid = true
    }

    public init() {}

    /// `load` is the same measure as `CoolingSample.load`; `fansByMacOS` is whether macOS,
    /// not MacFan or another app, chose the fan speeds.
    public mutating func add(_ snapshot: HardwareSnapshot, load: Double?, fansByMacOS: Bool) -> CoolingSample? {
        let date = snapshot.date
        if let lastUpdate, date.timeIntervalSince(lastUpdate) <= Self.maximumGap {
            // Readings are continuous.
        } else {
            settledFrom = date.addingTimeInterval(Self.settleTime)
            previousLoad = nil
            resetWindow(at: date)
        }
        lastUpdate = date

        guard let settledFrom, date >= settledFrom else { return nil }
        if windowStart == nil { resetWindow(at: date) }

        if let load, let rise = Self.rise(in: snapshot), fansByMacOS, !snapshot.fans.contains(where: \.isManual) {
            window.count += 1
            window.loadSum += load
            window.riseSum += rise
            if !snapshot.fans.isEmpty {
                window.rpmSum += snapshot.fans.map(\.currentRPM).reduce(0, +) / Double(snapshot.fans.count)
                window.rpmCount += 1
            }
        } else {
            window.isValid = false
        }

        guard let windowStart, date.timeIntervalSince(windowStart) >= Self.window else { return nil }
        defer { resetWindow(at: date) }
        guard window.isValid, window.count >= 3 else {
            previousLoad = nil
            return nil
        }
        let meanLoad = window.loadSum / Double(window.count)
        defer { previousLoad = meanLoad }
        // Steady: within 20% (or 1 unit, for light loads) of the minute before.
        guard let previousLoad, abs(meanLoad - previousLoad) <= max(meanLoad * 0.2, 1) else { return nil }
        return CoolingSample(
            date: date,
            load: meanLoad,
            rise: window.riseSum / Double(window.count),
            fanRPM: window.rpmCount > 0 ? window.rpmSum / Double(window.rpmCount) : nil
        )
    }

    private mutating func resetWindow(at date: Date) {
        windowStart = date
        window = Window()
    }

    /// Hottest CPU reading above the coolest air or surface reading.
    static func rise(in snapshot: HardwareSnapshot) -> Double? {
        guard let cpu = snapshot.hottest(in: [.cpu])?.celsius else { return nil }
        let air = snapshot.readings.filter { $0.sensor.isAirReference }.map(\.celsius).min()
        return air.map { cpu - $0 } ?? cpu
    }
}

extension Sensor {
    /// Air and surface sensors that follow the room more than the chips: ambient, airflow and
    /// palm rest. Heat pipes, Thunderbolt and display sensors are left out.
    public var isAirReference: Bool {
        category == .enclosure && ["TA", "Ta", "Ts"].contains { rawKey.hasPrefix($0) }
    }
}

/// The whole Mac's CPU share between successive load readings, for Macs without a power sensor.
public struct CPUShareMeter: Sendable {
    private var previous: CPULoad?

    public init() {}

    /// 0…100, or `nil` on the first reading.
    public mutating func update(_ load: CPULoad) -> Double? {
        defer { previous = load }
        guard let previous, load.totalTicks > previous.totalTicks, load.busyTicks >= previous.busyTicks else { return nil }
        return Double(load.busyTicks - previous.busyTicks) / Double(load.totalTicks - previous.totalTicks) * 100
    }
}

/// Weeks of `CoolingSample`s, condensed to one entry per day and workload band.
public struct CoolingLog: Codable, Hashable, Sendable {
    public enum LoadKind: String, Codable, Sendable {
        case watts
        case cpuShare
    }

    /// Averages for one day and one band of workload.
    public struct Entry: Codable, Hashable, Sendable {
        /// Midnight of the day, local time.
        public let day: Date
        /// Lower edge of the band, in `loadKind` units.
        public let band: Int
        public var minutes: Int
        public var riseTotal: Double
        public var rpmTotal: Double
        public var rpmMinutes: Int

        public var averageRise: Double { riseTotal / Double(max(minutes, 1)) }
        public var averageRPM: Double? { rpmMinutes > 0 ? rpmTotal / Double(rpmMinutes) : nil }
    }

    public static let retentionDays = 120
    /// The comparison needs this many days with data before it means anything.
    public static let learningDays = 14

    public private(set) var loadKind: LoadKind?
    public private(set) var entries: [Entry] = []

    public init() {}

    public static func bandWidth(for kind: LoadKind) -> Double {
        switch kind {
        case .watts: 5
        case .cpuShare: 10
        }
    }

    public mutating func add(_ sample: CoolingSample, kind: LoadKind, calendar: Calendar = .current) {
        // Watts and CPU shares can't be compared; a Mac only ever reports one of them, but be safe.
        if loadKind != kind {
            loadKind = kind
            entries = []
        }
        let day = calendar.startOfDay(for: sample.date)
        let band = Int((sample.load / Self.bandWidth(for: kind)).rounded(.down))
        if let index = entries.firstIndex(where: { $0.day == day && $0.band == band }) {
            entries[index].minutes += 1
            entries[index].riseTotal += sample.rise
            if let rpm = sample.fanRPM {
                entries[index].rpmTotal += rpm
                entries[index].rpmMinutes += 1
            }
        } else {
            entries.append(Entry(day: day, band: band, minutes: 1, riseTotal: sample.rise,
                                 rpmTotal: sample.fanRPM ?? 0, rpmMinutes: sample.fanRPM == nil ? 0 : 1))
        }
        let cutoff = calendar.date(byAdding: .day, value: -Self.retentionDays, to: day) ?? day
        entries.removeAll { $0.day < cutoff }
    }

    /// Distinct days with at least `minimumMinutes` of usable data.
    public func daysCollected(minimumMinutes: Int = 10) -> Int {
        Dictionary(grouping: entries, by: \.day)
            .filter { $0.value.map(\.minutes).reduce(0, +) >= minimumMinutes }
            .count
    }
}
