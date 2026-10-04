import Foundation
import Testing
@testable import MacFanCore

@Suite("BatteryInfo")
struct BatteryInfoTests {
    @Test func `parses recent macOS nested layout`() throws {
        // Shape observed on macOS 26+: capacities live under BatteryData, top-level values are percentages.
        let battery = try #require(BatteryInfo(properties: [
            "BatteryInstalled": true,
            "MaxCapacity": 100,
            "CurrentCapacity": 55,
            "CycleCount": 518,
            "IsCharging": true,
            "ExternalConnected": true,
            "DesignCycleCount9C": 1000,
            "BatteryData": [
                "DesignCapacity": 6075,
                "NominalChargeCapacity": 5156,
                "FullChargeCapacity": 5006,
            ] as [String: Any],
        ]))
        #expect(battery.designCapacity == 6075)
        #expect(battery.fullChargeCapacity == 5156)
        #expect(battery.charge == 0.55)
        #expect(battery.cycleCount == 518)
        #expect(battery.condition == .normal)
        #expect(battery.celsius == nil)
    }

    @Test func `parses apple silicon raw layout`() throws {
        let battery = try #require(BatteryInfo(properties: [
            "DesignCapacity": 5000,
            "AppleRawMaxCapacity": 3500,
            "AppleRawCurrentCapacity": 1750,
            "MaxCapacity": 100,
            "CurrentCapacity": 50,
            "Temperature": 3050,
        ]))
        #expect(battery.health == 0.7)
        #expect(battery.charge == 0.5)
        #expect(battery.celsius == 30.5)
        #expect(battery.condition == .serviceRecommended)
    }

    @Test func `parses intel layout`() throws {
        let battery = try #require(BatteryInfo(properties: [
            "DesignCapacity": 6000,
            "MaxCapacity": 5400,
            "CurrentCapacity": 2700,
        ]))
        #expect(battery.health == 0.9)
        #expect(battery.charge == 0.5)
        #expect(battery.ratedCycles == BatteryInfo.defaultRatedCycles)
    }

    @Test func `permanent failure recommends service`() throws {
        let battery = try #require(BatteryInfo(properties: [
            "DesignCapacity": 5000, "AppleRawMaxCapacity": 5000, "PermanentFailureStatus": 1,
        ]))
        #expect(battery.condition == .serviceRecommended)
    }

    @Test func `reads charge rate adapter and time left`() throws {
        let charging = try #require(BatteryInfo(properties: [
            "DesignCapacity": 5000,
            "Voltage": 12500,
            // Published as the unsigned bit pattern of the signed value.
            "InstantAmperage": NSNumber(value: UInt64(bitPattern: 2000)),
            "IsCharging": true,
            "ExternalConnected": true,
            "AdapterDetails": ["Watts": 96] as [String: Any],
            "AvgTimeToFull": 45,
            "TimeRemaining": 300,
        ]))
        #expect(charging.power == 25)
        #expect(charging.adapterWatts == 96)
        #expect(charging.minutesRemaining == 45)

        let draining = try #require(BatteryInfo(properties: [
            "DesignCapacity": 5000,
            "Voltage": 12000,
            "Amperage": NSNumber(value: UInt64(bitPattern: -1000)),
            "TimeRemaining": 65535,
        ]))
        #expect(draining.power == -12)
        #expect(draining.adapterWatts == nil)
        #expect(draining.minutesRemaining == nil, "65535 means macOS is still estimating")
    }

    @Test func `no battery means nil`() {
        #expect(BatteryInfo(properties: ["BatteryInstalled": false, "DesignCapacity": 5000]) == nil)
        #expect(BatteryInfo(properties: [:]) == nil)
    }
}

@Suite("History")
struct HistoryTests {
    @Test func `ring buffer keeps the newest in order`() {
        var buffer = RingBuffer<Int>(capacity: 3)
        (1...5).forEach { buffer.append($0) }
        #expect(buffer.elements == [3, 4, 5])
        #expect(buffer.count == 3)
    }

    @Test func `records sensors categories and fans`() {
        var history = HistoryStore(capacity: 10)
        let snapshot = Fixtures.snapshot(
            [Fixtures.reading(50, id: "a"), Fixtures.reading(70, id: "b")],
            fans: [Fixtures.fan(index: 0, current: 2500)]
        )
        history.record(snapshot)
        history.record(snapshot)

        #expect(history.values(for: "a") == [50, 50])
        #expect(history.values(for: HistoryStore.key(for: .cpu)) == [70, 70])
        #expect(history.values(for: HistoryStore.key(forFan: 0)) == [2500, 2500])
        #expect(history.values(for: "unknown").isEmpty)
    }

    @Test func `timeline averages each bucket and keeps the highest`() {
        var history = HistoryStore(capacity: 10, bucketDuration: 10, bucketCapacity: 3)
        let start = Date(timeIntervalSinceReferenceDate: 1000)
        for (offset, value) in [(0.0, 40.0), (5, 60), (10, 50), (12, 70)] {
            history.record(Fixtures.snapshot([Fixtures.reading(value, id: "a")], at: start.addingTimeInterval(offset)))
        }

        let timeline = history.timeline(for: "a")
        #expect(timeline.map(\.date) == [start, start.addingTimeInterval(10)])
        #expect(timeline.map(\.mean) == [50, 60])
        #expect(timeline.map(\.max) == [60, 70])
        #expect(history.timeline(for: "a", since: start.addingTimeInterval(5)).count == 1)
        #expect(history.peak(for: "a") == 70)
    }

    @Test func `timeline memory is bounded`() {
        var history = HistoryStore(capacity: 10, bucketDuration: 10, bucketCapacity: 3)
        let start = Date(timeIntervalSinceReferenceDate: 0)
        for step in 0..<20 {
            history.record(Fixtures.snapshot([Fixtures.reading(Double(step), id: "a")], at: start.addingTimeInterval(Double(step) * 10)))
        }
        // Three finished buckets plus the one still filling.
        #expect(history.timeline(for: "a").map(\.mean) == [16, 17, 18, 19])
    }

    @Test func `records system power`() {
        var history = HistoryStore()
        var snapshot = Fixtures.snapshot([])
        snapshot.systemPower = 12.5
        history.record(snapshot)
        #expect(history.values(for: HistoryStore.systemPowerKey) == [12.5])
    }
}

@Suite("App activity")
struct ActivityTests {
    @Test func `helpers count toward the app that contains them`() {
        #expect(ActivityTracker.owner(ofExecutable: "/Applications/Google Chrome.app/Contents/Frameworks/Google Chrome Framework.framework/Helpers/Google Chrome Helper (Renderer).app/Contents/MacOS/Google Chrome Helper (Renderer)").name == "Google Chrome")
        let tool = ActivityTracker.owner(ofExecutable: "/usr/local/bin/ffmpeg")
        #expect(tool.name == "ffmpeg")
        #expect(tool.bundlePath == nil)
    }

    @Test func `cpu percent is time used over time elapsed`() throws {
        var tracker = ActivityTracker()
        let start = Date(timeIntervalSinceReferenceDate: 0)
        let app = "/Applications/Foo.app/Contents/MacOS/Foo"
        let helper = "/Applications/Foo.app/Contents/Frameworks/Foo Helper.app/Contents/MacOS/Foo Helper"
        let tool = "/usr/bin/bar"

        let baseline = tracker.update([
            ProcessSample(pid: 1, path: app, cpuNanoseconds: 1_000_000_000),
            ProcessSample(pid: 2, path: helper, cpuNanoseconds: 0),
            ProcessSample(pid: 3, path: tool, cpuNanoseconds: 0),
        ], at: start)
        #expect(baseline == nil, "The first sample is only a baseline")

        let update = tracker.update([
            ProcessSample(pid: 1, path: app, cpuNanoseconds: 2_000_000_000),
            ProcessSample(pid: 2, path: helper, cpuNanoseconds: 1_000_000_000),
            ProcessSample(pid: 3, path: tool, cpuNanoseconds: 500_000_000),
        ], at: start.addingTimeInterval(2))
        let apps = try #require(update)

        #expect(apps.map(\.name) == ["Foo", "bar"])
        #expect(apps.map(\.cpuPercent) == [100, 25])
    }

    @Test func `what macOS won't itemize is counted as the system`() throws {
        var tracker = ActivityTracker()
        let start = Date(timeIntervalSinceReferenceDate: 0)
        let app = "/Applications/Foo.app/Contents/MacOS/Foo"
        _ = tracker.update([ProcessSample(pid: 1, path: app, cpuNanoseconds: 0)],
                           load: CPULoad(busyTicks: 0, totalTicks: 0, cores: 4), at: start)
        // Over one second the Mac was 50% busy across 4 cores (200% of one core); Foo used 50%.
        let update = tracker.update([ProcessSample(pid: 1, path: app, cpuNanoseconds: 500_000_000)],
                                    load: CPULoad(busyTicks: 200, totalTicks: 400, cores: 4), at: start.addingTimeInterval(1))
        let apps = try #require(update)

        #expect(apps.map(\.isSystem) == [true, false])
        #expect(apps.map(\.cpuPercent) == [150, 50])
    }

    @Test func `no system entry when the apps account for everything`() throws {
        var tracker = ActivityTracker()
        let start = Date(timeIntervalSinceReferenceDate: 0)
        let app = "/Applications/Foo.app/Contents/MacOS/Foo"
        _ = tracker.update([ProcessSample(pid: 1, path: app, cpuNanoseconds: 0)],
                           load: CPULoad(busyTicks: 0, totalTicks: 0, cores: 1), at: start)
        let update = tracker.update([ProcessSample(pid: 1, path: app, cpuNanoseconds: 1_000_000_000)],
                                    load: CPULoad(busyTicks: 100, totalTicks: 100, cores: 1), at: start.addingTimeInterval(1))
        let apps = try #require(update)
        #expect(apps.allSatisfy { !$0.isSystem })
    }

    @Test func `idle and exited processes are left out`() throws {
        var tracker = ActivityTracker()
        let start = Date(timeIntervalSinceReferenceDate: 0)
        _ = tracker.update([
            ProcessSample(pid: 1, path: "/bin/idle", cpuNanoseconds: 5),
            ProcessSample(pid: 2, path: "/bin/gone", cpuNanoseconds: 5),
        ], at: start)
        let update = tracker.update([ProcessSample(pid: 1, path: "/bin/idle", cpuNanoseconds: 5)], at: start.addingTimeInterval(1))
        let apps = try #require(update)
        #expect(apps.isEmpty)
    }
}

@Suite("Power profiles")
struct PowerProfileTests {
    @Test func `picks the mode for the power source`() {
        var profiles = PowerProfiles()
        profiles.onBattery = .automatic
        profiles.onAdapter = .max
        #expect(profiles.mode(onBattery: true) == .automatic)
        #expect(profiles.mode(onBattery: false) == .max)
    }

    @Test func `off by default so nothing changes behind the user's back`() {
        #expect(PowerProfiles().isEnabled == false)
    }
}

@Suite("Snapshot")
struct SnapshotTests {
    @Test func `summaries hide unidentified by default`() {
        let snapshot = Fixtures.snapshot([
            Fixtures.reading(60, id: "cpu"),
            Fixtures.reading(90, category: .other, id: "mystery", identified: false),
        ])
        #expect(snapshot.summaries().map(\.category) == [.cpu])
        #expect(snapshot.summaries(includeUnidentified: true).map(\.category) == [.cpu, .other])
    }

    @Test func `worst level ignores irrelevant categories`() {
        let snapshot = Fixtures.snapshot([
            Fixtures.reading(40, id: "cpu"),
            Fixtures.reading(100, category: .enclosure, id: "case"),
        ])
        #expect(snapshot.worstLevel == .cool)
    }

    @Test func `temperature sources fall back to hottest overall`() {
        let snapshot = Fixtures.snapshot([Fixtures.reading(55, category: .memory, id: "mem")])
        #expect(TemperatureSource.hottestGPU.temperature(in: snapshot) == 55)
    }
}

@Suite("CSVLogger")
struct CSVLoggerTests {
    @Test func `escapes fields that need it`() {
        #expect(CSVLogger.escape("plain") == "plain")
        #expect(CSVLogger.escape("a,b") == "\"a,b\"")
        #expect(CSVLogger.escape("say \"hi\"") == "\"say \"\"hi\"\"\"")
    }

    @Test func `writes header and rows`() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }

        let logger = CSVLogger(directory: directory)
        let snapshot = Fixtures.snapshot([Fixtures.reading(50.25, id: "cpu")], at: Date())
        try await logger.append(snapshot)
        try await logger.append(snapshot)
        await logger.close()

        let file = try #require(try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).first)
        let lines = try String(contentsOf: file, encoding: .utf8).split(separator: "\n")
        #expect(lines.count == 3)
        #expect(lines[0] == "time,cpu (°C),Fan (rpm)")
        #expect(lines[1].hasSuffix(",50.2,2000") || lines[1].hasSuffix(",50.3,2000"))
    }
}
