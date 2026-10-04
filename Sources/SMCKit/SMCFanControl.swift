import Foundation

/// A fan as reported by the SMC.
public struct SMCFanReading: Hashable, Sendable {
    public let index: Int
    public let actualRPM: Double
    /// `nil` when the firmware didn't report it. Never invented.
    public let minimumRPM: Double?
    /// `nil` when the firmware didn't report it. Never invented.
    public let maximumRPM: Double?
    public let targetRPM: Double?
    /// `true` when something other than macOS is setting the speed.
    public let isManual: Bool

    /// The range a target may be written in, or `nil` if the reported limits are missing
    /// or nonsensical. Without it MacFan must not take manual control of this fan.
    public var validLimits: ClosedRange<Double>? {
        guard let minimumRPM, let maximumRPM,
              minimumRPM.isFinite, maximumRPM.isFinite,
              minimumRPM >= 0, maximumRPM > minimumRPM
        else { return nil }
        return minimumRPM...maximumRPM
    }
}

/// Reads fan state and, when running as root, takes or returns manual control.
///
/// Two firmware families exist:
/// - **Apple Silicon** (and recent Intel): per-fan mode key `F<n>Md`. On Apple Silicon the
///   `Ftst` key must be set first, otherwise the firmware's thermal manager immediately
///   reclaims the fan.
/// - **Older Intel**: one bitmask key `FS! ` where bit `n` puts fan `n` in forced mode.
///
/// Fails closed: when the data needed to control a fan safely is missing, it throws rather
/// than guessing.
public struct SMCFanControl<SMC: SMCKeyAccess> {
    /// Fan keys are `F<digit>…`, so the SMC can't describe more fans than this.
    public static var maximumFanCount: Int { 10 }

    private let smc: SMC
    private let modeSwitchAttempts: Int
    private let modeSwitchInterval: TimeInterval

    /// `modeSwitchAttempts` × `modeSwitchInterval` is how long to wait for the firmware to
    /// accept a mode change.
    public init(smc: SMC, modeSwitchAttempts: Int = 20, modeSwitchInterval: TimeInterval = 0.05) {
        self.smc = smc
        self.modeSwitchAttempts = max(1, modeSwitchAttempts)
        self.modeSwitchInterval = modeSwitchInterval
    }

    /// Throws when `FNum` is missing or unusable: "can't tell" is not the same as "no fans".
    public func fanCount() throws -> Int {
        guard let raw = smc.double("FNum") else { throw SMCError.keyNotFound("FNum") }
        guard raw.isFinite, raw >= 0, raw <= Double(Self.maximumFanCount), raw == raw.rounded() else {
            throw SMCError.invalidFanData("FNum is \(raw)")
        }
        return Int(raw)
    }

    public func reading(fan index: Int) -> SMCFanReading? {
        guard let actual = smc.double(key("F%dAc", index)), actual.isFinite else { return nil }
        return SMCFanReading(
            index: index,
            actualRPM: max(0, actual),
            minimumRPM: smc.double(key("F%dMn", index)),
            maximumRPM: smc.double(key("F%dMx", index)),
            targetRPM: smc.double(key("F%dTg", index)),
            isManual: isManual(fan: index)
        )
    }

    public func readings() throws -> [SMCFanReading] {
        try (0..<fanCount()).compactMap { reading(fan: $0) }
    }

    public func isManual(fan index: Int) -> Bool {
        if let mode = smc.double(key("F%dMd", index)) {
            return mode == 1
        }
        if let mask = forcedMask() {
            return mask & (1 << index) != 0
        }
        return false
    }

    // MARK: Control (root only)

    /// Sets the target speed, clamped to the fan's firmware range, taking manual control if
    /// needed. Throws without writing anything if that range isn't known.
    public func setTarget(rpm: Double, fan index: Int) throws {
        guard rpm.isFinite else { throw SMCError.invalidFanData("target \(rpm) rpm") }
        guard let reading = reading(fan: index) else {
            throw SMCError.keyNotFound(key("F%dAc", index).name)
        }
        guard let limits = reading.validLimits else {
            throw SMCError.invalidFanData(
                "fan \(index) limits \(reading.minimumRPM.map { "\($0)" } ?? "?")–\(reading.maximumRPM.map { "\($0)" } ?? "?")"
            )
        }
        if !reading.isManual {
            try setManual(true, fan: index)
        }
        try smc.write(key("F%dTg", index), value: rpm.clamped(to: limits))
    }

    public func setManual(_ manual: Bool, fan index: Int) throws {
        let modeKey = key("F%dMd", index)
        if smc.contains(modeKey) {
            try setModeKey(modeKey, manual: manual)
        } else if smc.contains("FS! ") {
            try setForcedBit(manual, fan: index)
        } else {
            throw SMCError.keyNotFound(modeKey.name)
        }
    }

    /// Hands every fan back to macOS. Throws if any fan may still be manual.
    public func restoreAutomatic() throws {
        var lastError: Error?
        for index in 0..<(try fanCount()) {
            do { try setManual(false, fan: index) } catch { lastError = error }
        }
        if let lastError { throw lastError }
    }

    // MARK: Private

    private func setModeKey(_ modeKey: SMCKey, manual: Bool) throws {
        let hasTestMode = smc.contains("Ftst")
        if manual, hasTestMode {
            try smc.write("Ftst", value: 1)
        }

        // The thermal manager can take a moment to release the fan after `Ftst`.
        let wanted: Double = manual ? 1 : 0
        var applied = false
        for attempt in 0..<modeSwitchAttempts {
            try? smc.write(modeKey, value: wanted)
            if smc.double(modeKey) == wanted {
                applied = true
                break
            }
            if attempt < modeSwitchAttempts - 1, modeSwitchInterval > 0 {
                Thread.sleep(forTimeInterval: modeSwitchInterval)
            }
        }
        guard applied else { throw SMCError.writeNotApplied(key: modeKey.name) }

        if !manual, hasTestMode, !(0..<(try fanCount())).contains(where: isManual(fan:)) {
            try smc.write("Ftst", value: 0)
        }
    }

    private func setForcedBit(_ manual: Bool, fan index: Int) throws {
        guard let current = forcedMask() else { throw SMCError.invalidFanData("FS! is unreadable") }
        let updated = manual ? current | (1 << index) : current & ~(1 << index)
        try smc.write("FS! ", value: Double(updated))
    }

    private func forcedMask() -> Int? {
        guard let mask = smc.double("FS! "), mask.isFinite, mask >= 0, mask <= Double(UInt16.max) else { return nil }
        return Int(mask)
    }

    /// `key("F%dAc", 1)` → `F1Ac`. Indices come from a validated `fanCount()`, so an index
    /// that doesn't fit a four-character key is a programming error, not a runtime condition.
    private func key(_ format: String, _ index: Int) -> SMCKey {
        let name = String(format: format, index)
        guard let key = SMCKey(name) else {
            preconditionFailure("Fan index \(index) does not form a valid SMC key (\(name))")
        }
        return key
    }
}

extension SMCFanControl: Sendable where SMC: Sendable {}

extension Comparable {
    fileprivate func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
