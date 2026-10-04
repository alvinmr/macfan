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
