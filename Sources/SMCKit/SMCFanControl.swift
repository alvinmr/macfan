import Foundation

/// A fan as reported by the SMC.
public struct SMCFanReading: Hashable, Sendable {
    public let index: Int
    public let actualRPM: Double
    public let minimumRPM: Double
    public let maximumRPM: Double
    public let targetRPM: Double?
    /// `true` when something other than macOS is setting the speed.
    public let isManual: Bool
}

/// Reads fan state and, when running as root, takes or returns manual control.
///
/// Two firmware families exist:
/// - **Apple Silicon** (and recent Intel): per-fan mode key `F<n>Md`. On Apple Silicon the
///   `Ftst` key must be set first, otherwise the firmware's thermal manager immediately
///   reclaims the fan.
/// - **Older Intel**: one bitmask key `FS! ` where bit `n` puts fan `n` in forced mode.
///
/// A value type: it holds no state of its own, only the shared, thread-safe connection.
public struct SMCFanControl: Sendable {
    private let smc: SMCConnection

    public init(smc: SMCConnection) {
        self.smc = smc
    }

    public func fanCount() -> Int {
        Int(smc.double("FNum") ?? 0)
    }

    public func reading(fan index: Int) -> SMCFanReading? {
        guard let actual = smc.double(key("F%dAc", index)) else { return nil }
        let minimum = smc.double(key("F%dMn", index)) ?? 0
        let maximum = smc.double(key("F%dMx", index)) ?? max(actual, minimum)
        return SMCFanReading(
            index: index,
            actualRPM: max(0, actual),
            minimumRPM: minimum,
            maximumRPM: maximum,
            targetRPM: smc.double(key("F%dTg", index)),
            isManual: isManual(fan: index)
        )
    }

    public func readings() -> [SMCFanReading] {
        (0..<fanCount()).compactMap { reading(fan: $0) }
    }

    public func isManual(fan index: Int) -> Bool {
        if let mode = smc.double(key("F%dMd", index)) {
            return mode == 1
        }
        if let mask = smc.double("FS! ") {
            return Int(mask) & (1 << index) != 0
        }
        return false
    }

    // MARK: Control (root only)

    /// Sets the target speed, clamped to the fan's supported range, taking manual control if needed.
    public func setTarget(rpm: Double, fan index: Int) throws {
        guard let reading = reading(fan: index) else {
            throw SMCError.keyNotFound(key("F%dAc", index).name)
        }
        if !reading.isManual {
            try setManual(true, fan: index)
        }
        let clamped = min(max(rpm, reading.minimumRPM), reading.maximumRPM)
        try smc.write(key("F%dTg", index), value: clamped)
    }

    public func setManual(_ manual: Bool, fan index: Int) throws {
        let modeKey = key("F%dMd", index)
        if smc.contains(modeKey) {
            try setModeKey(modeKey, manual: manual, fan: index)
        } else if smc.contains("FS! ") {
            try setForcedBit(manual, fan: index)
        } else {
            throw SMCError.keyNotFound(modeKey.name)
        }
    }

    /// Hands every fan back to macOS. Safe to call at any time.
    public func restoreAutomatic() throws {
        var lastError: Error?
        for index in 0..<fanCount() {
            do { try setManual(false, fan: index) } catch { lastError = error }
        }
        if let lastError { throw lastError }
    }

    // MARK: Private

    private func setModeKey(_ modeKey: SMCKey, manual: Bool, fan index: Int) throws {
        let hasTestMode = smc.contains("Ftst")
        if manual, hasTestMode {
            try smc.write("Ftst", value: 1)
        }

        // The thermal manager can take a moment to release the fan after `Ftst`.
        let wanted: Double = manual ? 1 : 0
        var applied = false
        for _ in 0..<20 {
            try? smc.write(modeKey, value: wanted)
            if smc.double(modeKey) == wanted {
                applied = true
                break
            }
            Thread.sleep(forTimeInterval: 0.05)
        }
        guard applied else { throw SMCError.writeNotApplied(key: modeKey.name) }

        if !manual, hasTestMode, !(0..<fanCount()).contains(where: isManual(fan:)) {
            try smc.write("Ftst", value: 0)
        }
    }

    private func setForcedBit(_ manual: Bool, fan index: Int) throws {
        let current = Int(smc.double("FS! ") ?? 0)
        let updated = manual ? current | (1 << index) : current & ~(1 << index)
        try smc.write("FS! ", value: Double(updated))
    }

    /// `key("F%dAc", 1)` → `F1Ac`. Fan indices come from `FNum`, so an index that doesn't
    /// fit a four-character key is a programming error, not a runtime condition.
    private func key(_ format: String, _ index: Int) -> SMCKey {
        let name = String(format: format, index)
        guard let key = SMCKey(name) else {
            preconditionFailure("Fan index \(index) does not form a valid SMC key (\(name))")
        }
        return key
    }
}
