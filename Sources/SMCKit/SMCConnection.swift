import CPrivateIOKit
import Foundation
import IOKit

/// A connection to the System Management Controller.
///
/// Reads work for any user. Writes need root and are only performed by the privileged helper.
/// All calls are serialized by an internal lock, so one connection can be shared across
/// threads; that lock is what makes the `@unchecked Sendable` promise true.
public final class SMCConnection: @unchecked Sendable {
    private enum Command: UInt8 {
        case readKey = 5
        case writeKey = 6
        case keyAtIndex = 8
        case keyInfo = 9
    }

    private static let userClientSelector: UInt32 = 2
    private static let resultKeyNotFound: UInt8 = 0x84

    private let connection: io_connect_t
    private let lock = NSLock()
    private var infoCache: [SMCKey: SMCKeyInfo] = [:]

    public init() throws {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != IO_OBJECT_NULL else { throw SMCError.serviceNotFound }
        defer { IOObjectRelease(service) }

        var connection: io_connect_t = 0
        let result = IOServiceOpen(service, CPKTaskSelf(), 0, &connection)
        guard result == kIOReturnSuccess else { throw SMCError.openFailed(result) }
        self.connection = connection
    }

    deinit {
        IOServiceClose(connection)
    }

    // MARK: Reading

    public func info(for key: SMCKey) throws -> SMCKeyInfo {
        try lock.withLock { try infoLocked(key) }
    }

    public func contains(_ key: SMCKey) -> Bool {
        (try? info(for: key)) != nil
    }

    public func read(_ key: SMCKey) throws -> SMCValue {
        try lock.withLock {
            let info = try infoLocked(key)
            var input = SMCParamStruct()
            input.key = key.code
            input.keyInfo.dataSize = UInt32(info.size)
            input.data8 = Command.readKey.rawValue

            let output = try call(&input, key: key)
            let count = min(info.size, 32)
            let bytes = withUnsafeBytes(of: output.bytes) { Array($0.prefix(count)) }
            return SMCValue(key: key, info: info, bytes: bytes)
        }
    }

    /// Convenience: the key's numeric value, or `nil` if it is missing or not numeric.
    public func double(_ key: SMCKey) -> Double? {
        try? read(key).doubleValue
    }

    // MARK: Writing (root only)

    public func write(_ key: SMCKey, bytes: [UInt8]) throws {
        try lock.withLock {
            let info = try infoLocked(key)
            guard bytes.count == info.size, bytes.count <= 32 else {
                throw SMCError.invalidSize(key: key.name, expected: info.size, actual: bytes.count)
            }
            var input = SMCParamStruct()
            input.key = key.code
            input.keyInfo.dataSize = UInt32(info.size)
            input.data8 = Command.writeKey.rawValue
            withUnsafeMutableBytes(of: &input.bytes) { buffer in
                buffer.copyBytes(from: bytes)
            }
            _ = try call(&input, key: key)
        }
    }

    /// Encodes `value` using the key's own data type, then writes it.
    public func write(_ key: SMCKey, value: Double) throws {
        let info = try info(for: key)
        guard let bytes = SMCCodec.encode(value, dataType: info.dataType, size: info.size) else {
            throw SMCError.unsupportedType(key: key.name, dataType: info.dataType)
        }
        try write(key, bytes: bytes)
    }

    // MARK: Enumeration

    public func keyCount() throws -> Int {
        guard let count = try read("#KEY").doubleValue else { return 0 }
        return Int(count)
    }

    public func key(at index: Int) throws -> SMCKey {
        try lock.withLock {
            var input = SMCParamStruct()
            input.data8 = Command.keyAtIndex.rawValue
            input.data32 = UInt32(index)
            let output = try call(&input, key: nil)
            return SMCKey(code: output.key)
        }
    }

    /// Every key the firmware exposes. Takes tens of milliseconds; call once and cache.
    public func allKeys() throws -> [SMCKey] {
        let count = try keyCount()
        return (0..<count).compactMap { try? key(at: $0) }
    }

    // MARK: Private

    /// Call with `lock` held.
    private func infoLocked(_ key: SMCKey) throws(SMCError) -> SMCKeyInfo {
        if let cached = infoCache[key] { return cached }

        var input = SMCParamStruct()
        input.key = key.code
        input.data8 = Command.keyInfo.rawValue

        let output = try call(&input, key: key)
        let info = SMCKeyInfo(
            size: Int(output.keyInfo.dataSize),
            dataType: SMCFourCC.decode(output.keyInfo.dataType),
            attributes: output.keyInfo.dataAttributes
        )
        infoCache[key] = info
        return info
    }

    private func call(_ input: inout SMCParamStruct, key: SMCKey?) throws(SMCError) -> SMCParamStruct {
        var output = SMCParamStruct()
        var outputSize = MemoryLayout<SMCParamStruct>.stride

        let result = IOConnectCallStructMethod(
            connection,
            Self.userClientSelector,
            &input,
            MemoryLayout<SMCParamStruct>.stride,
            &output,
            &outputSize
        )
        guard result == kIOReturnSuccess else {
            throw result == kIOReturnNotPrivileged ? SMCError.notPrivileged : SMCError.callFailed(result)
        }
        switch output.result {
        case 0:
            return output
        case Self.resultKeyNotFound:
            throw SMCError.keyNotFound(key?.name ?? "?")
        default:
            throw SMCError.firmware(code: output.result, key: key?.name ?? "?")
        }
    }
}

/// The few SMC operations fan control needs. `SMCConnection` provides them for real;
/// tests substitute an in-memory SMC so failure paths can be exercised without hardware.
public protocol SMCKeyAccess {
    func double(_ key: SMCKey) -> Double?
    func contains(_ key: SMCKey) -> Bool
    func write(_ key: SMCKey, value: Double) throws
}

extension SMCConnection: SMCKeyAccess {}
