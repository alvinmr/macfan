import Foundation
import MacFanCore
import Observation

enum MenuBarDisplay: String, CaseIterable, Codable {
    case temperature
    case fanSpeed
    case both
    case iconOnly
}

/// User settings, persisted to `UserDefaults` on every change.
@Observable
final class Preferences {
    var unit: TemperatureUnit {
        didSet { defaults.set(unit.rawValue, forKey: Key.unit) }
    }

    /// Seconds between readings.
    var refreshInterval: Double {
        didSet { defaults.set(refreshInterval, forKey: Key.refreshInterval) }
    }

    var menuBarDisplay: MenuBarDisplay {
        didSet { defaults.set(menuBarDisplay.rawValue, forKey: Key.menuBarDisplay) }
    }

    /// Sensor shown in the menu bar; `nil` means the hottest CPU sensor.
    var menuBarSensorID: String? {
        didSet { defaults.set(menuBarSensorID, forKey: Key.menuBarSensorID) }
    }

    var showsUnidentifiedSensors: Bool {
        didSet { defaults.set(showsUnidentifiedSensors, forKey: Key.showsUnidentifiedSensors) }
    }

    var showsDockIcon: Bool {
        didSet { defaults.set(showsDockIcon, forKey: Key.showsDockIcon) }
    }

    var alertsEnabled: Bool {
        didSet { defaults.set(alertsEnabled, forKey: Key.alertsEnabled) }
    }

    /// CPU/GPU alert threshold in °C.
    var alertThreshold: Double {
        didSet { defaults.set(alertThreshold, forKey: Key.alertThreshold) }
    }

    var loggingEnabled: Bool {
        didSet { defaults.set(loggingEnabled, forKey: Key.loggingEnabled) }
    }

    /// Seconds between CSV rows.
    var loggingInterval: Double {
        didSet { defaults.set(loggingInterval, forKey: Key.loggingInterval) }
    }

    var cooling: CoolingSettings {
        didSet { defaults.set(try? JSONEncoder().encode(cooling), forKey: Key.cooling) }
    }

    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        unit = defaults.string(forKey: Key.unit).flatMap(TemperatureUnit.init) ?? Self.localeUnit
        // Numbers read from disk are only trusted if they're one of the values the UI offers.
        refreshInterval = Self.validated(defaults.object(forKey: Key.refreshInterval), allowed: [1, 2, 5], default: 2)
        menuBarDisplay = defaults.string(forKey: Key.menuBarDisplay).flatMap(MenuBarDisplay.init) ?? .temperature
        menuBarSensorID = defaults.string(forKey: Key.menuBarSensorID)
        showsUnidentifiedSensors = defaults.bool(forKey: Key.showsUnidentifiedSensors)
        showsDockIcon = defaults.object(forKey: Key.showsDockIcon) as? Bool ?? true
        alertsEnabled = defaults.bool(forKey: Key.alertsEnabled)
        alertThreshold = Self.validated(defaults.object(forKey: Key.alertThreshold), allowed: Set((70...105).map(Double.init)), default: 95)
        loggingEnabled = defaults.bool(forKey: Key.loggingEnabled)
        loggingInterval = Self.validated(defaults.object(forKey: Key.loggingInterval), allowed: [5, 10, 60], default: 10)
        cooling = defaults.data(forKey: Key.cooling)
            .flatMap { try? JSONDecoder().decode(CoolingSettings.self, from: $0) } ?? CoolingSettings()
    }

    private static func validated(_ stored: Any?, allowed: Set<Double>, default fallback: Double) -> Double {
        guard let value = stored as? Double, allowed.contains(value) else { return fallback }
        return value
    }

    private static var localeUnit: TemperatureUnit {
        Locale.current.measurementSystem == .us ? .fahrenheit : .celsius
    }

    private enum Key {
        static let unit = "unit"
        static let refreshInterval = "refreshInterval"
        static let menuBarDisplay = "menuBarDisplay"
        static let menuBarSensorID = "menuBarSensorID"
        static let showsUnidentifiedSensors = "showsUnidentifiedSensors"
        static let showsDockIcon = "showsDockIcon"
        static let alertsEnabled = "alertsEnabled"
        static let alertThreshold = "alertThreshold"
        static let loggingEnabled = "loggingEnabled"
        static let loggingInterval = "loggingInterval"
        static let cooling = "cooling"
    }
}
