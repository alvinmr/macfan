import IOKit

public enum SMCError: Error, Equatable, Sendable, CustomStringConvertible {
    /// No `AppleSMC` service — typically a virtual machine.
    case serviceNotFound
    case openFailed(kern_return_t)
    case callFailed(kern_return_t)
    /// Writing requires root. Only the privileged helper may write.
    case notPrivileged
    case keyNotFound(String)
    case firmware(code: UInt8, key: String)
    case unsupportedType(key: String, dataType: String)
    case invalidSize(key: String, expected: Int, actual: Int)
    /// A write was accepted but the value did not stick (e.g. macOS reclaimed fan control).
    case writeNotApplied(key: String)

    public var description: String {
        switch self {
        case .serviceNotFound: "AppleSMC service not found"
        case .openFailed(let code): "Could not open AppleSMC (\(hex(code)))"
        case .callFailed(let code): "SMC call failed (\(hex(code)))"
        case .notPrivileged: "Writing to the SMC requires root privileges"
        case .keyNotFound(let key): "SMC key \(key) does not exist on this Mac"
        case .firmware(let code, let key): "SMC rejected \(key) with code \(code)"
        case .unsupportedType(let key, let type): "SMC key \(key) has unsupported type \"\(type)\""
        case .invalidSize(let key, let expected, let actual): "SMC key \(key) expects \(expected) bytes, got \(actual)"
        case .writeNotApplied(let key): "SMC did not apply the write to \(key)"
        }
    }

    private func hex(_ code: kern_return_t) -> String {
        "0x" + String(UInt32(bitPattern: code), radix: 16)
    }
}
