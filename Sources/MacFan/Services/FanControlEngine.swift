import Foundation
import MacFanCore
import Observation

/// Applies `CoolingPlanner` decisions to the hardware through the helper.
///
/// Fans are handed back to macOS when the user picks Automatic, during an emergency,
/// before sleep, and on quit. The helper independently does the same if the app vanishes.
@Observable
final class FanControlEngine {
    enum State: Equatable {
        /// macOS is in charge.
        case system
        /// A part got critically hot; macOS is in charge until it cools down.
        case emergency
        /// The curve has no temperature to follow.
        case noData
        /// MacFan is driving the fans at this 0…1 speed.
        case controlling(speed: Double)
        /// The chosen mode needs the helper, which isn't ready.
        case needsHelper
        case failed(String)
    }

    private(set) var state: State = .system
    /// The temperature the curve is reacting to right now.
    private(set) var curveTemperature: Double?

    @ObservationIgnored private var planner = CoolingPlanner()
    /// Starts `true` so a leftover manual state from a crash is cleared on the first tick.
    @ObservationIgnored private var mayBeControlling = true
    @ObservationIgnored private var isSuspended = false
    private let helper: HelperManager

    init(helper: HelperManager) {
        self.helper = helper
    }

    func update(settings: CoolingSettings, snapshot: HardwareSnapshot) async {
        guard !isSuspended, !snapshot.fans.isEmpty else { return }

        switch planner.decide(settings: settings, snapshot: snapshot) {
        case .system(let reason):
            curveTemperature = nil
            await returnToSystem()
            state = switch reason {
            case .userChoice: .system
            case .emergency: .emergency
            case .noData: .noData
            }

        case .manual(let speed, let temperature):
            curveTemperature = temperature
            guard helper.isReady else {
                state = .needsHelper
                return
            }
            do {
                // Sent every tick even when unchanged: it doubles as the helper's heartbeat.
                for fan in snapshot.fans {
                    try await helper.setTarget(rpm: fan.rpm(forSpeed: speed), fanIndex: fan.index)
                }
                mayBeControlling = true
                state = .controlling(speed: speed)
            } catch {
                state = .failed(error.localizedDescription)
            }
        }
    }

    /// Before sleep: give the fans back and stop until `resume()`.
    func suspend() async {
        isSuspended = true
        await returnToSystem()
        state = .system
    }

    func resume() {
        isSuspended = false
    }

    /// On quit. Synchronous because the process is about to exit.
    func shutdown() {
        isSuspended = true
        if mayBeControlling {
            helper.restoreSystemControlBlocking()
        }
    }

    private func returnToSystem() async {
        guard mayBeControlling, helper.isReady else { return }
        do {
            try await helper.restoreSystemControl()
            mayBeControlling = false
        } catch {
            state = .failed(error.localizedDescription)
        }
    }
}
