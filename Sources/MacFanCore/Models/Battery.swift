import Foundation

public struct BatteryInfo: Hashable, Sendable {
    public enum Condition: String, Sendable {
        case normal
        case serviceRecommended
    }

    /// Apple rates every modern MacBook battery for 1,000 cycles.
    public static let defaultRatedCycles = 1000
    /// Below this share of the original capacity Apple recommends service.
    public static let serviceThreshold = 0.8

    public let cycleCount: Int
    public let ratedCycles: Int
    public let designCapacity: Int
    public let fullChargeCapacity: Int
    /// 0…1
    public let charge: Double
    public let isCharging: Bool
    public let isPluggedIn: Bool
    public let celsius: Double?
    public let hasPermanentFailure: Bool
    /// Volts.
    public let voltage: Double?
    /// Amps; negative while discharging.
    public let amperage: Double?
    /// The connected power adapter's rating, when macOS knows it.
    public let adapterWatts: Int?
    /// Minutes until empty (on battery) or full (charging), once macOS has an estimate.
    public let minutesRemaining: Int?

    /// Remaining capacity relative to new, 0…1 (can exceed 1 slightly on brand-new batteries).
    public var health: Double {
        guard designCapacity > 0 else { return 0 }
        return Double(fullChargeCapacity) / Double(designCapacity)
    }

    /// Watts flowing into (positive) or out of (negative) the battery.
    public var power: Double? {
        guard let voltage, let amperage else { return nil }
        return voltage * amperage
    }

    public var condition: Condition {
        hasPermanentFailure || health < Self.serviceThreshold ? .serviceRecommended : .normal
    }

    /// Parses the `AppleSmartBattery` IORegistry properties.
    ///
    /// The layout has changed across releases: Intel reports mAh in the plain keys, Apple
    /// Silicon reports `MaxCapacity`/`CurrentCapacity` as percentages with mAh under
    /// `AppleRaw…`, and newer macOS versions move capacities into a nested `BatteryData`
    /// dictionary. Each value is looked up at the top level first, then in `BatteryData`.
    public init?(properties: [String: Any]) {
        let nested = properties["BatteryData"] as? [String: Any] ?? [:]
        func int(_ key: String) -> Int? { properties[key] as? Int ?? nested[key] as? Int }
        // Signed values such as `Amperage` are published as their unsigned 64-bit bit pattern.
        func signed(_ key: String) -> Int? {
            (properties[key] as? NSNumber ?? nested[key] as? NSNumber).map { Int(truncatingIfNeeded: $0.int64Value) }
        }

        if let installed = properties["BatteryInstalled"] as? Bool, !installed { return nil }
        guard let design = int("DesignCapacity"), design > 0 else { return nil }

        let rawMax = int("AppleRawMaxCapacity")
        let rawCurrent = int("AppleRawCurrentCapacity")
        let maxCapacity = int("MaxCapacity")
        let currentCapacity = int("CurrentCapacity")

        let fullCharge = rawMax ?? int("NominalChargeCapacity") ?? int("FullChargeCapacity") ?? maxCapacity ?? design
        let charge: Double = if let rawCurrent, let rawMax, rawMax > 0 {
            Double(rawCurrent) / Double(rawMax)
        } else if let currentCapacity, let maxCapacity, maxCapacity > 0 {
            Double(currentCapacity) / Double(maxCapacity)
        } else {
            0
        }

        self.designCapacity = design
        self.fullChargeCapacity = fullCharge
        self.charge = min(max(charge, 0), 1)
        self.cycleCount = int("CycleCount") ?? 0
        self.ratedCycles = int("DesignCycleCount9C") ?? Self.defaultRatedCycles
        self.isCharging = properties["IsCharging"] as? Bool ?? false
        self.isPluggedIn = properties["ExternalConnected"] as? Bool ?? false
        // Hundredths of a degree Celsius. Absent on recent macOS; the UI then uses the SMC battery sensor.
        self.celsius = int("Temperature").map { Double($0) / 100 }
        self.hasPermanentFailure = (int("PermanentFailureStatus") ?? 0) != 0

        self.voltage = int("Voltage").flatMap { $0 > 0 ? Double($0) / 1000 : nil }
        self.amperage = (signed("InstantAmperage") ?? signed("Amperage")).map { Double($0) / 1000 }
        let adapter = properties["AdapterDetails"] as? [String: Any]
        self.adapterWatts = (adapter?["Watts"] as? Int).flatMap { $0 > 0 ? $0 : nil }
        // 65535 means "still estimating".
        let minutes = isCharging ? int("AvgTimeToFull") : (isPluggedIn ? nil : int("TimeRemaining") ?? int("AvgTimeToEmpty"))
        self.minutesRemaining = minutes.flatMap { $0 > 0 && $0 < 65535 ? $0 : nil }
    }
}
