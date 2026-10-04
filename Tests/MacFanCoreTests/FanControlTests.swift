import Foundation
import Testing
@testable import MacFanCore

@Suite("FanCurve")
struct FanCurveTests {
    let curve = FanCurve([(40, 0), (60, 0.5), (80, 1)])

    @Test func `interpolates between points`() {
        #expect(curve.speed(at: 50) == 0.25)
        #expect(curve.speed(at: 70) == 0.75)
    }

    @Test func `holds flat outside the curve`() {
        #expect(curve.speed(at: 20) == 0)
        #expect(curve.speed(at: 100) == 1)
    }

    @Test func `normalization sorts and forbids hotter being slower`() {
        let messy = FanCurve([(80, 0.2), (40, 0.6), (60, 0.1)])
        #expect(messy.points.map(\.temperature) == [40, 60, 80])
        #expect(messy.points.map(\.speed) == [0.6, 0.6, 0.6])
    }

    @Test func `normalization separates duplicate temperatures`() {
        let duplicates = FanCurve([(50, 0), (50, 1)])
        #expect(duplicates.points[1].temperature == 50 + FanCurve.minimumGap)
    }

    @Test func `moving up lifts later points`() {
        var edited = curve
        edited.move(pointAt: 0, to: CurvePoint(temperature: 40, speed: 0.8))
        #expect(edited.points.map(\.speed) == [0.8, 0.8, 1])
    }

    @Test func `moving down lowers earlier points`() {
        var edited = curve
        edited.move(pointAt: 2, to: CurvePoint(temperature: 80, speed: 0.2))
        #expect(edited.points.map(\.speed) == [0, 0.2, 0.2])
    }

    @Test func `points cannot pass their neighbours`() {
        var edited = curve
        edited.move(pointAt: 1, to: CurvePoint(temperature: 95, speed: 0.5))
        #expect(edited.points[1].temperature == 80 - FanCurve.minimumGap)
    }

    @Test func `presets are valid`() throws {
        for preset in CurvePreset.allCases where preset != .custom {
            let curve = try #require(preset.curve)
            #expect(curve.points.first?.speed ?? 1 <= curve.points.last?.speed ?? 0)
        }
    }
}

@Suite("SpeedGovernor")
struct SpeedGovernorTests {
    let start = Date(timeIntervalSince1970: 0)

    @Test func `speeds up immediately`() {
        var governor = SpeedGovernor()
        _ = governor.next(target: 0.2, at: start)
        #expect(governor.next(target: 0.9, at: start + 1) == 0.9)
    }

    @Test func `slows down gradually`() {
        var governor = SpeedGovernor()
        _ = governor.next(target: 1, at: start)
        let next = governor.next(target: 0, at: start + 2)
        #expect(abs(next - (1 - 2 * governor.maximumDecreasePerSecond)) < 0.0001)
    }

    @Test func `ignores tiny decreases`() {
        var governor = SpeedGovernor()
        _ = governor.next(target: 0.5, at: start)
        #expect(governor.next(target: 0.49, at: start + 10) == 0.5)
    }
}

@Suite("CoolingPlanner")
struct CoolingPlannerTests {
    func settings(_ mode: CoolingMode) -> CoolingSettings {
        var settings = CoolingSettings()
        settings.mode = mode
        return settings
    }

    @Test func `automatic leaves fans to macOS`() {
        var planner = CoolingPlanner()
        let decision = planner.decide(settings: settings(.automatic), snapshot: Fixtures.snapshot([Fixtures.reading(60)]))
        #expect(decision == .system(.userChoice))
    }

    @Test func `fixed uses the chosen speed`() {
        var planner = CoolingPlanner()
        var fixed = settings(.fixed)
        fixed.fixedSpeed = 0.3
        #expect(planner.decide(settings: fixed, snapshot: Fixtures.snapshot([Fixtures.reading(60)])) == .manual(speed: 0.3, temperature: nil))
    }

    @Test func `curve follows its source`() {
        var planner = CoolingPlanner()
        var curve = settings(.curve)
        curve.preset = .custom
        curve.customCurve = FanCurve([(40, 0), (80, 1)])
        let snapshot = Fixtures.snapshot([Fixtures.reading(60), Fixtures.reading(30, category: .storage)])
        #expect(planner.decide(settings: curve, snapshot: snapshot) == .manual(speed: 0.5, temperature: 60))
    }

    @Test func `curve without data hands back to macOS`() {
        var planner = CoolingPlanner()
        var curve = settings(.curve)
        curve.source = .sensor(id: "missing")
        #expect(planner.decide(settings: curve, snapshot: Fixtures.snapshot([Fixtures.reading(60)])) == .system(.noData))
    }

    @Test func `critical temperature hands back to macOS`() {
        var planner = CoolingPlanner()
        let hot = Fixtures.snapshot([Fixtures.reading(SensorCategory.cpu.thresholds.critical + 1)])
        #expect(planner.decide(settings: settings(.fixed), snapshot: hot) == .system(.emergency))
        #expect(planner.decide(settings: settings(.curve), snapshot: hot) == .system(.emergency))
    }

    @Test func `max mode is never overridden`() {
        var planner = CoolingPlanner()
        let hot = Fixtures.snapshot([Fixtures.reading(SensorCategory.cpu.thresholds.critical + 1)])
        #expect(planner.decide(settings: settings(.max), snapshot: hot) == .manual(speed: 1, temperature: nil))
    }

    @Test func `emergency ends only after cooling down`() {
        var planner = CoolingPlanner()
        let critical = SensorCategory.cpu.thresholds.critical
        _ = planner.decide(settings: settings(.fixed), snapshot: Fixtures.snapshot([Fixtures.reading(critical)]))

        let slightlyCooler = Fixtures.snapshot([Fixtures.reading(critical - 1)])
        #expect(planner.decide(settings: settings(.fixed), snapshot: slightlyCooler) == .system(.emergency))

        let cool = Fixtures.snapshot([Fixtures.reading(critical - SafetyPolicy.recoveryMargin - 1)])
        #expect(planner.decide(settings: settings(.fixed), snapshot: cool) != .system(.emergency))
    }

    @Test func `unidentified or irrelevant sensors never trigger an emergency`() {
        let readings = [
            Fixtures.reading(120, category: .other, identified: false),
            Fixtures.reading(120, category: .enclosure),
        ]
        #expect(!SafetyPolicy.isEmergency(readings, wasInEmergency: false))
    }
}

@Suite("Fans")
struct FanTests {
    @Test func `speed maps onto the supported range`() {
        let fan = Fixtures.fan(minimum: 1000, maximum: 5000)
        #expect(fan.rpm(forSpeed: 0) == 1000)
        #expect(fan.rpm(forSpeed: 0.5) == 3000)
        #expect(fan.rpm(forSpeed: 2) == 5000)
    }

    @Test func `names`() {
        #expect(FanStatus.name(forIndex: 0, count: 1) == "Fan")
        #expect(FanStatus.name(forIndex: 1, count: 2) == "Fan 2")
    }
}
