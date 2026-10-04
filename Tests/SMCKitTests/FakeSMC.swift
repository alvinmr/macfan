@testable import SMCKit

/// An in-memory SMC. Writes stick unless the key is listed in `rejecting` (throws) or
/// `ignoring` (accepted but the value doesn't change, like firmware reclaiming a fan).
final class FakeSMC: SMCKeyAccess {
    var values: [SMCKey: Double]
    var rejecting: Set<SMCKey> = []
    var ignoring: Set<SMCKey> = []
    private(set) var writes: [(key: SMCKey, value: Double)] = []

    init(_ values: [SMCKey: Double] = [:]) {
        self.values = values
    }

    /// Two Apple Silicon fans in automatic mode, 1200–6000 rpm.
    static func appleSilicon() -> FakeSMC {
        FakeSMC([
            "FNum": 2, "Ftst": 0,
            "F0Ac": 2000, "F0Mn": 1200, "F0Mx": 6000, "F0Tg": 2000, "F0Md": 0,
            "F1Ac": 2100, "F1Mn": 1200, "F1Mx": 6000, "F1Tg": 2100, "F1Md": 0,
        ])
    }

    func double(_ key: SMCKey) -> Double? { values[key] }

    func contains(_ key: SMCKey) -> Bool { values[key] != nil }

    func write(_ key: SMCKey, value: Double) throws {
        guard values[key] != nil else { throw SMCError.keyNotFound(key.name) }
        guard !rejecting.contains(key) else { throw SMCError.firmware(code: 1, key: key.name) }
        writes.append((key, value))
        if !ignoring.contains(key) { values[key] = value }
    }

    func wrote(_ key: SMCKey) -> Bool { writes.contains { $0.key == key } }
}
