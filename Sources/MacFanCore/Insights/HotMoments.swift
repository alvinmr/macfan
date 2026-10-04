import Foundation

/// A stretch of time when the Mac ran hot or slowed itself down, and what was keeping it busy.
public struct HotMoment: Codable, Hashable, Sendable, Identifiable {
    /// An app's average share of the whole Mac's CPU over the moment.
    public struct Culprit: Codable, Hashable, Sendable {
        /// Same as `AppActivity.id`.
        public let id: String
        public let name: String
        public let bundlePath: String?
        public let share: Double

        public init(id: String, name: String, bundlePath: String?, share: Double) {
            self.id = id
            self.name = name
            self.bundlePath = bundlePath
            self.share = share
        }

        public var isSystemComponent: Bool { AppActivity.isSystemComponent(id: id) }
    }

    public let start: Date
    public var end: Date
    public var peakCelsius: Double
    public var peakSensor: String
    public var peakCategory: SensorCategory
    /// How long macOS limited performance because of heat.
    public var throttledSeconds: TimeInterval
    /// Busiest first, at most three.
    public var culprits: [Culprit]

    public var id: Date { start }
    public var duration: TimeInterval { end.timeIntervalSince(start) }
}

/// Turns a stream of snapshots into `HotMoment`s.
///
/// A moment counts once something safety-relevant has been hot, or macOS has been limiting
/// performance, for `sustain`, and it is recorded from when that began. It ends after
/// `coolDown` of calm, so heat that returns within that time stays one moment. A gap in
/// updates longer than `maximumGap` (the Mac slept) ends it where the updates stopped.
public struct HotMomentRecorder: Sendable {
    public static let sustain: TimeInterval = 30
    public static let coolDown: TimeInterval = 120
    public static let maximumGap: TimeInterval = 300

    /// From the first hot reading; becomes a moment once it has lasted `sustain`.
    private var draft: HotMoment?
    private var isConfirmed = false
    private var coolSince: Date?
    private var lastUpdate: Date?
    private var usage: [String: (name: String, bundlePath: String?, total: Double)] = [:]
    private var activitySamples = 0

    public init() {}

    /// The confirmed moment in progress, if any.
    public var inProgress: HotMoment? { isConfirmed ? draft.map(withCulprits) : nil }

    /// Whether app activity is worth sampling: while it's hot, not while cooling down, so
    /// the calm afterwards doesn't water down who caused the heat.
    public var wantsActivity: Bool { draft != nil && coolSince == nil }

    /// Returns a moment once it has ended.
    public mutating func update(_ snapshot: HardwareSnapshot, isThrottling: Bool) -> HotMoment? {
        let date = snapshot.date
        let previous = lastUpdate
        lastUpdate = date

        if let previous, date.timeIntervalSince(previous) > Self.maximumGap, draft != nil {
            return finish()
        }

        let isHot = isThrottling || snapshot.worstLevel >= .hot
        if !isHot {
            guard draft != nil else { return nil }
            guard isConfirmed else {
                reset()
                return nil
            }
            let since = coolSince ?? date
            coolSince = since
            return date.timeIntervalSince(since) >= Self.coolDown ? finish() : nil
        }

        coolSince = nil
        var moment = draft ?? HotMoment(start: date, end: date, peakCelsius: 0, peakSensor: "",
                                        peakCategory: .cpu, throttledSeconds: 0, culprits: [])
        moment.end = date
        if let hottest = snapshot.hottest(in: Self.safetyCategories), hottest.celsius > moment.peakCelsius {
            moment.peakCelsius = hottest.celsius
            moment.peakSensor = hottest.sensor.name
            moment.peakCategory = hottest.sensor.category
        }
        if isThrottling, let previous, draft != nil {
            moment.throttledSeconds += date.timeIntervalSince(previous)
        }
        draft = moment
        if moment.duration >= Self.sustain { isConfirmed = true }
        return nil
    }

    /// Adds one activity sample. Apps missing from a sample count as idle for it.
    public mutating func record(_ apps: [AppActivity]) {
        guard wantsActivity else { return }
        activitySamples += 1
        // The macOS remainder isn't something anyone can act on.
        for app in apps where !app.isSystem {
            usage[app.id, default: (app.name, app.bundlePath, 0)].total += app.shareOfMac
        }
    }

    private static let safetyCategories = Set(SensorCategory.allCases.filter(\.isSafetyRelevant))

    private mutating func finish() -> HotMoment? {
        defer { reset() }
        return isConfirmed ? draft.map(withCulprits) : nil
    }

    private mutating func reset() {
        draft = nil
        isConfirmed = false
        coolSince = nil
        usage = [:]
        activitySamples = 0
    }

    private func withCulprits(_ moment: HotMoment) -> HotMoment {
        guard activitySamples > 0 else { return moment }
        var moment = moment
        moment.culprits = usage
            .map { HotMoment.Culprit(id: $0.key, name: $0.value.name, bundlePath: $0.value.bundlePath,
                                     share: $0.value.total / Double(activitySamples)) }
            .filter { $0.share >= 1 }
            .sorted { $0.share > $1.share }
            .prefix(3)
            .map { $0 }
        return moment
    }
}
