import Foundation
import MacFanCore
import SwiftUI

/// Turns readings into one sentence a person can act on.
///
/// The headline answers "is my Mac OK?"; the detail answers "what, if anything, should I do?".
struct ThermalStatus: Equatable {
    let level: TemperatureLevel
    let headline: LocalizedStringKey
    let detail: LocalizedStringKey
    let pressure: LocalizedStringKey

    init(snapshot: HardwareSnapshot, thermalState: ProcessInfo.ThermalState, hasStarted: Bool) {
        pressure = switch thermalState {
        case .nominal: "Nominal"
        case .fair: "Fair"
        case .serious: "Serious"
        case .critical: "Critical"
        @unknown default: "Unknown"
        }

        guard hasStarted else {
            level = .cool
            headline = "Checking your Mac…"
            detail = "Reading sensors."
            return
        }
        guard !snapshot.readings.isEmpty else {
            level = .cool
            headline = "No sensors found"
            detail = "MacFan can't read this Mac's sensors. In a virtual machine, that's expected."
            return
        }

        let throttling = thermalState == .serious || thermalState == .critical
        let level = throttling ? max(snapshot.worstLevel, .hot) : snapshot.worstLevel
        let hasFans = !snapshot.fans.isEmpty
        self.level = level

        switch (level, throttling) {
        case (_, true):
            headline = "Your Mac is slowing down to cool off"
            detail = "macOS is limiting performance because of heat. Pause heavy work and give it some air."
        case (.cool, _):
            headline = "Running cool"
            detail = "Everything is in a comfortable range."
        case (.warm, _):
            headline = "Warm, and that's normal"
            detail = "Temperatures are up because your Mac is busy. Nothing to do."
        case (.hot, _):
            headline = "Running hot"
            detail = hasFans
                ? "The fans are working hard. Quit heavy apps you aren't using, and keep the vents clear."
                : "This Mac has no fans. Quit heavy apps you aren't using, and keep it on a hard, flat surface."
        case (.critical, _):
            headline = "Too hot"
            detail = "Something is close to its limit. Save your work and let your Mac rest."
        }
    }
}
