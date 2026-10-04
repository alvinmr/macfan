/// A four-character SMC key such as `TC0P` (CPU proximity temperature) or `F0Ac` (fan 0 actual speed).
public struct SMCKey: Hashable, Sendable, CustomStringConvertible, ExpressibleByStringLiteral {
    public let code: UInt32

    public init(code: UInt32) {
        self.code = code
    }

    /// Returns `nil` unless `name` is exactly four bytes long.
    public init?(_ name: String) {
        guard let code = SMCFourCC.encode(name) else { return nil }
        self.code = code
    }

    public init(stringLiteral value: String) {
        guard let key = SMCKey(value) else {
            preconditionFailure("SMC keys are exactly four ASCII characters, got \"\(value)\"")
        }
        self = key
    }

    public var name: String { SMCFourCC.decode(code) }
    public var description: String { name }
}

/// The SMC identifies keys and data types with big-endian four-character codes.
public enum SMCFourCC {
    public static func encode(_ string: String) -> UInt32? {
        let bytes = Array(string.utf8)
        guard bytes.count == 4 else { return nil }
        return bytes.reduce(0) { ($0 << 8) | UInt32($1) }
    }

    public static func decode(_ code: UInt32) -> String {
        let bytes = [24, 16, 8, 0].map { UInt8(truncatingIfNeeded: code >> $0) }
        return String(decoding: bytes, as: UTF8.self)
    }
}
