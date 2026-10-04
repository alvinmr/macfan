import Foundation
import Testing
@testable import MacFanCore

/// A helper stand-in that records commands and can fail or pause on demand.
@MainActor
final class FakeCommander: FanCommanding {
    enum Failure: Error { case write, restore }

    var isReady = true
    private(set) var log: [String] = []
    var failingFans: Set<Int> = []
    var failRestore = false
    /// Pauses `setTarget` for this fan until `releasePausedTarget()`.
    var pauseFan: Int?
    private var paused: CheckedContinuation<Void, Never>?

    var isPaused: Bool { paused != nil }

    func setTarget(rpm: Double, fanIndex: Int) async throws {
        log.append("target \(fanIndex)")
        if pauseFan == fanIndex {
            pauseFan = nil
            await withCheckedContinuation { paused = $0 }
        }
        if failingFans.contains(fanIndex) { throw Failure.write }
    }

    func restoreSystemControl() async throws {
        log.append("restore")
        if failRestore { throw Failure.restore }
    }

    func restoreSystemControlBlocking() {
        log.append("restore (blocking)")
    }

    func releasePausedTarget() {
        paused?.resume()
        paused = nil
    }
}

@MainActor
@Suite("FanControlEngine")
struct FanControlEngineTests {
    let twoFans = [Fixtures.fan(index: 0), Fixtures.fan(index: 1)]

    func snapshot() -> HardwareSnapshot {
        Fixtures.snapshot([Fixtures.reading(60)], fans: twoFans)
    }

    func settings(_ mode: CoolingMode) -> CoolingSettings {
        var settings = CoolingSettings()
        settings.mode = mode
        return settings
    }

    /// R1: a failed hand-back must stay visible and be retried.
    @Test func `a failed restore is reported and retried`() async {
        let commander = FakeCommander()
        let engine = FanControlEngine(commander: commander)
        await engine.update(settings: settings(.max), snapshot: snapshot())

        commander.failRestore = true
        await engine.update(settings: settings(.automatic), snapshot: snapshot())
        #expect(engine.state == .failed("Couldn't give the fans back to macOS"))

        commander.failRestore = false
        await engine.update(settings: settings(.automatic), snapshot: snapshot())
        #expect(engine.state == .system)
        #expect(commander.log.filter { $0 == "restore" }.count == 2)
    }

    /// R2: a write that fails halfway must still be undone.
    @Test func `a partial target failure is handed back`() async {
        let commander = FakeCommander()
        let engine = FanControlEngine(commander: commander)
        await engine.update(settings: settings(.automatic), snapshot: snapshot())

        commander.failingFans = [1]
        await engine.update(settings: settings(.max), snapshot: snapshot())
        #expect(commander.log.suffix(3) == ["target 0", "target 1", "restore"])
        if case .failed = engine.state {} else { Issue.record("Expected .failed, got \(engine.state)") }
    }

    /// R2: if even that hand-back fails, the next Automatic tick and shutdown still try.
    @Test func `a partial failure keeps the restore obligation`() async {
        let commander = FakeCommander()
        let engine = FanControlEngine(commander: commander)
        await engine.update(settings: settings(.automatic), snapshot: snapshot())

        commander.failingFans = [1]
        commander.failRestore = true
        await engine.update(settings: settings(.max), snapshot: snapshot())

        commander.failRestore = false
        await engine.update(settings: settings(.automatic), snapshot: snapshot())
        #expect(commander.log.last == "restore")
        #expect(engine.state == .system)
    }

    @Test func `shutdown hands back after a partial failure`() async {
        let commander = FakeCommander()
        let engine = FanControlEngine(commander: commander)
        await engine.update(settings: settings(.automatic), snapshot: snapshot())

        commander.failingFans = [1]
        commander.failRestore = true
        await engine.update(settings: settings(.max), snapshot: snapshot())
        engine.shutdown()
        #expect(commander.log.last == "restore (blocking)")
    }

    /// R3: sleep arriving mid-update must win; no target may follow the hand-back.
    @Test func `suspend during an update ends with a hand-back`() async {
        let commander = FakeCommander()
        let engine = FanControlEngine(commander: commander)
        await engine.update(settings: settings(.automatic), snapshot: snapshot())

        commander.pauseFan = 0
        let update = Task { await engine.update(settings: settings(.max), snapshot: snapshot()) }
        while !commander.isPaused { await Task.yield() }

        await engine.suspend()
        commander.releasePausedTarget()
        await update.value

        #expect(commander.log.suffix(2) == ["target 0", "restore"])
        #expect(engine.state == .system)
    }

    @Test func `updates are ignored while suspended`() async {
        let commander = FakeCommander()
        let engine = FanControlEngine(commander: commander)
        await engine.suspend()
        let before = commander.log
        await engine.update(settings: settings(.max), snapshot: snapshot())
        #expect(commander.log == before)

        engine.resume()
        await engine.update(settings: settings(.max), snapshot: snapshot())
        #expect(commander.log.suffix(2) == ["target 0", "target 1"])
    }

    @Test func `fans with unknown limits are never driven`() async {
        let commander = FakeCommander()
        let engine = FanControlEngine(commander: commander)
        let unknown = FanStatus(index: 0, name: "Fan", currentRPM: 2000, minimumRPM: 0, maximumRPM: 2000,
                                targetRPM: nil, isManual: false, hasKnownLimits: false)
        await engine.update(settings: settings(.max), snapshot: Fixtures.snapshot([Fixtures.reading(60)], fans: [unknown]))
        #expect(!commander.log.contains { $0.hasPrefix("target") })
        if case .failed = engine.state {} else { Issue.record("Expected .failed, got \(engine.state)") }
    }

    @Test func `without the helper nothing is sent`() async {
        let commander = FakeCommander()
        commander.isReady = false
        let engine = FanControlEngine(commander: commander)
        await engine.update(settings: settings(.max), snapshot: snapshot())
        #expect(engine.state == .needsHelper)
        #expect(commander.log.isEmpty)
    }
}
