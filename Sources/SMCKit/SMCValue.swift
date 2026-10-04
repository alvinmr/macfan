import Foundation

/// Size and encoding of an SMC key's value.
public struct SMCKeyInfo: Hashable, Sendable {
    public let size: Int
    /// Four-character data type, e.g. `"flt "`, `"sp78"`, `"fpe2"`, `"ui8 "`.
    public let dataType: String
    public let attributes: UInt8

    public init(size: Int, dataType: String, attributes: UInt8 = 0) {
        self.size = size
        self.dataType = dataType
        self.attributes = attributes
    }
}

/// Raw bytes read from the SMC, with their encoding.
public struct SMCValue: Hashable, Sendable {
    public let key: SMCKey
    public let info: SMCKeyInfo
    public let bytes: [UInt8]

    public init(key: SMCKey, info: SMCKeyInfo, bytes: [UInt8]) {
        self.key = key
        self.info = info
        self.bytes = bytes
    }

    /// The value as a number, or `nil` when the data type is not numeric.
    public var doubleValue: Double? { SMCCodec.decode(bytes, dataType: info.dataType) }
}

/// Converts between SMC byte encodings and `Double`.
///
/// Supported types:
/// - `flt ` 32-bit little-endian float (Apple Silicon)
/// - `ui8 ` `ui16` `ui32` unsigned big-endian integers
/// - `si8 ` `si16` signed big-endian integers
/// - `fpXY` unsigned 16-bit fixed point, `Y` (hex) fractional bits — e.g. `fpe2` (Intel fan RPM)
/// - `spXY` signed 16-bit fixed point, `Y` (hex) fractional bits — e.g. `sp78` (Intel temperatures)
public enum SMCCodec {
    public static func decode(_ bytes: [UInt8], dataType: String) -> Double? {
        switch dataType {
        case "flt ":
            guard bytes.count >= 4 else { return nil }
            let bits = UInt32(bytes[0]) | UInt32(bytes[1]) << 8 | UInt32(bytes[2]) << 16 | UInt32(bytes[3]) << 24
            return Double(Float(bitPattern: bits))
        case "ui8 ", "char":
            return bytes.first.map(Double.init)
        case "si8 ":
            return bytes.first.map { Double(Int8(bitPattern: $0)) }
        case "ui16":
            return bigEndian16(bytes).map(Double.init)
        case "si16":
            return bigEndian16(bytes).map { Double(Int16(bitPattern: $0)) }
        case "ui32":
            guard bytes.count >= 4 else { return nil }
            return Double(bytes.prefix(4).reduce(UInt32(0)) { $0 << 8 | UInt32($1) })
        default:
            guard let fraction = fixedPointFractionBits(dataType), let raw = bigEndian16(bytes) else { return nil }
            let scale = Double(1 << fraction)
            return dataType.hasPrefix("sp") ? Double(Int16(bitPattern: raw)) / scale : Double(raw) / scale
        }
    }

    /// Encodes `value` for a key of the given type and size, or returns `nil` if unsupported.
    public static func encode(_ value: Double, dataType: String, size: Int) -> [UInt8]? {
        let bytes: [UInt8]
        switch dataType {
        case "flt ":
            let bits = Float(value).bitPattern
            bytes = [0, 8, 16, 24].map { UInt8(truncatingIfNeeded: bits >> $0) }
        case "ui8 ", "char":
            bytes = [UInt8(clamping: Int(value.rounded()))]
        case "ui16":
            bytes = toBigEndian(UInt16(clamping: Int(value.rounded())))
        case "ui32":
            let raw = UInt32(clamping: Int(value.rounded()))
            bytes = [24, 16, 8, 0].map { UInt8(truncatingIfNeeded: raw >> $0) }
        default:
            guard let fraction = fixedPointFractionBits(dataType) else { return nil }
            let scaled = Int((value * Double(1 << fraction)).rounded())
            if dataType.hasPrefix("sp") {
                bytes = toBigEndian(UInt16(bitPattern: Int16(clamping: scaled)))
            } else {
                bytes = toBigEndian(UInt16(clamping: scaled))
            }
        }
        return bytes.count == size ? bytes : nil
    }

    /// `fpe2` → 2, `sp78` → 8, `sp5a` → 10. `nil` for anything that isn't a 16-bit fixed-point type.
    static func fixedPointFractionBits(_ dataType: String) -> Int? {
        guard dataType.count == 4, dataType.hasPrefix("fp") || dataType.hasPrefix("sp"),
              let last = dataType.last, let bits = last.hexDigitValue
        else { return nil }
        return bits
    }

    private static func bigEndian16(_ bytes: [UInt8]) -> UInt16? {
        guard bytes.count >= 2 else { return nil }
        return UInt16(bytes[0]) << 8 | UInt16(bytes[1])
    }

    private static func toBigEndian(_ value: UInt16) -> [UInt8] {
        [UInt8(truncatingIfNeeded: value >> 8), UInt8(truncatingIfNeeded: value)]
    }
}
