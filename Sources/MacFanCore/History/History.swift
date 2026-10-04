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

/// Recent values for sparklines: every sensor, each category's hottest value, each fan's RPM.
public struct HistoryStore: Sendable {
    public let capacity: Int
    private var series: [String: RingBuffer<Double>] = [:]

    /// At the default 2 s refresh, 300 samples is ten minutes.
    public init(capacity: Int = 300) {
        self.capacity = capacity
    }

    public static func key(for category: SensorCategory) -> String { "category.\(category.rawValue)" }
    public static func key(forFan index: Int) -> String { "fan.\(index)" }

    public mutating func record(_ snapshot: HardwareSnapshot) {
        for reading in snapshot.readings {
            append(reading.celsius, to: reading.id)
        }
        for summary in snapshot.summaries(includeUnidentified: true) {
            append(summary.hottest.celsius, to: Self.key(for: summary.category))
        }
        for fan in snapshot.fans {
            append(fan.currentRPM, to: Self.key(forFan: fan.index))
        }
    }

    public func values(for key: String) -> [Double] {
        series[key]?.elements ?? []
    }

    private mutating func append(_ value: Double, to key: String) {
        series[key, default: RingBuffer(capacity: capacity)].append(value)
    }
}
