import Foundation
import IOKit.ps

/// A cooling mode for each power source, applied when the Mac is plugged in or unplugged.
/// Picking a mode by hand still works; it holds until the power source next changes.
public struct PowerProfiles: Hashable, Codable, Sendable {
    public var isEnabled = false
    public var onBattery: CoolingMode = .automatic
    public var onAdapter: CoolingMode = .curve

    public init() {}

    public func mode(onBattery: Bool) -> CoolingMode {
        onBattery ? self.onBattery : onAdapter
    }
}

public enum PowerSource {
    /// `nil` when macOS can't say. Desktops report wall power, never battery.
    public static func isOnBattery() -> Bool? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let type = IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() as String?
        else { return nil }
        return type == kIOPSBatteryPowerValue
    }
}
