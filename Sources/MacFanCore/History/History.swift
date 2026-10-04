import Foundation

/// Fixed-capacity FIFO. Appending past capacity drops the oldest element.
public struct RingBuffer<Element> {
    public let capacity: Int
    private var storage: [Element] = []
    private var head = 0

    public init(capacity: Int) {
        precondition(capacity > 0)
        self.capacity = capacity
        storage.reserveCapacity(capacity)
    }

    public mutating func append(_ element: Element) {
        if storage.count < capacity {
            storage.append(element)
        } else {
            storage[head] = element
            head = (head + 1) % capacity
        }
    }

    /// Oldest first.
    public var elements: [Element] {
        Array(storage[head...] + storage[..<head])
    }

    public var count: Int { storage.count }
}

extension RingBuffer: Sendable where Element: Sendable {}

/// One stretch of the long-term timeline.
public struct HistoryPoint: Hashable, Sendable {
    /// Start of the bucket.
    public let date: Date
    public let mean: Double
    public let max: Double
}

/// Recent values, kept at two resolutions so memory stays flat however long MacFan runs:
/// every sample for the last few minutes (sparklines), and one averaged point per
/// `bucketDuration` for the last hour (detail charts). Also remembers each series' peak.
public struct HistoryStore: Sendable {
    public let capacity: Int
    public let bucketDuration: TimeInterval
    public let bucketCapacity: Int

    private var series: [String: RingBuffer<Double>] = [:]
    private var timelines: [String: RingBuffer<HistoryPoint>] = [:]
    private var openBuckets: [String: Accumulator] = [:]
    private var peaks: [String: Double] = [:]

    /// At the default 2 s refresh, 300 samples is ten minutes; 360 ten-second buckets is an hour.
    public init(capacity: Int = 300, bucketDuration: TimeInterval = 10, bucketCapacity: Int = 360) {
        self.capacity = capacity
        self.bucketDuration = bucketDuration
        self.bucketCapacity = bucketCapacity
    }

    public static func key(for category: SensorCategory) -> String { "category.\(category.rawValue)" }
    public static func key(forFan index: Int) -> String { "fan.\(index)" }
    public static let systemPowerKey = "power.system"

    public mutating func record(_ snapshot: HardwareSnapshot) {
        let date = snapshot.date
        for reading in snapshot.readings {
            append(reading.celsius, to: reading.id, at: date)
        }
        for summary in snapshot.summaries(includeUnidentified: true) {
            append(summary.hottest.celsius, to: Self.key(for: summary.category), at: date)
        }
        for fan in snapshot.fans {
            append(fan.currentRPM, to: Self.key(forFan: fan.index), at: date)
        }
        if let watts = snapshot.systemPower {
            append(watts, to: Self.systemPowerKey, at: date)
        }
    }

    /// Recent samples, oldest first.
    public func values(for key: String) -> [Double] {
        series[key]?.elements ?? []
    }

    /// The averaged timeline since `date`, oldest first, including the bucket still filling.
    public func timeline(for key: String, since date: Date = .distantPast) -> [HistoryPoint] {
        var points = timelines[key]?.elements ?? []
        if let open = openBuckets[key]?.point { points.append(open) }
        return points.filter { $0.date >= date }
    }

    /// The highest value seen since MacFan started.
    public func peak(for key: String) -> Double? {
        peaks[key]
    }

    private mutating func append(_ value: Double, to key: String, at date: Date) {
        series[key, default: RingBuffer(capacity: capacity)].append(value)
        peaks[key] = Swift.max(peaks[key] ?? value, value)

        let start = Date(timeIntervalSinceReferenceDate:
            (date.timeIntervalSinceReferenceDate / bucketDuration).rounded(.down) * bucketDuration)
        if let open = openBuckets[key], open.start != start, let point = open.point {
            timelines[key, default: RingBuffer(capacity: bucketCapacity)].append(point)
            openBuckets[key] = nil
        }
        openBuckets[key, default: Accumulator(start: start)].add(value)
    }

    private struct Accumulator: Sendable {
        let start: Date
        var sum = 0.0
        var count = 0
        var max = -Double.infinity

        mutating func add(_ value: Double) {
            sum += value
            count += 1
            max = Swift.max(max, value)
        }

        var point: HistoryPoint? {
            count > 0 ? HistoryPoint(date: start, mean: sum / Double(count), max: max) : nil
        }
    }
}
