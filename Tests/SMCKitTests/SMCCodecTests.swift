import Testing
@testable import SMCKit

@Suite("SMCKey")
struct SMCKeyTests {
    @Test func `round trips four character names`() {
        let key: SMCKey = "TC0P"
        #expect(key.code == 0x5443_3050)
        #expect(key.name == "TC0P")
    }

    // Variables, not literals: a literal would pick the non-failable `ExpressibleByStringLiteral` init.
    @Test func `rejects wrong length`() {
        let short = "TC0", long = "TC0PX"
        #expect(SMCKey(short) == nil)
        #expect(SMCKey(long) == nil)
    }

    @Test func `keeps trailing spaces`() {
        let name = "FS! "
        #expect(SMCKey(name)?.name == "FS! ")
    }
}

@Suite("SMCCodec")
struct SMCCodecTests {
    @Test func `decodes little endian float`() {
        // 42.5 as IEEE-754 single, little-endian.
        #expect(SMCCodec.decode([0x00, 0x00, 0x2A, 0x42], dataType: "flt ") == 42.5)
    }

    @Test func `decodes intel fan speed`() {
        // fpe2: 14 integer bits, 2 fraction bits. 0x1F40 >> 2 = 2000 rpm.
        #expect(SMCCodec.decode([0x1F, 0x40], dataType: "fpe2") == 2000)
    }

    @Test func `decodes intel temperature`() {
        // sp78: signed, 8 fraction bits. 0x3280 = 50.5 °C.
        #expect(SMCCodec.decode([0x32, 0x80], dataType: "sp78") == 50.5)
    }

    @Test func `decodes negative signed fixed point`() {
        #expect(SMCCodec.decode([0xFF, 0x00], dataType: "sp78") == -1)
    }

    @Test func `decodes integers`() {
        #expect(SMCCodec.decode([2], dataType: "ui8 ") == 2)
        #expect(SMCCodec.decode([0x01, 0x00], dataType: "ui16") == 256)
        #expect(SMCCodec.decode([0x00, 0x00, 0x01, 0x00], dataType: "ui32") == 256)
        #expect(SMCCodec.decode([0xFF, 0xFE], dataType: "si16") == -2)
    }

    @Test func `returns nil for unknown types and short data`() {
        #expect(SMCCodec.decode([1, 2, 3, 4], dataType: "{fds") == nil)
        #expect(SMCCodec.decode([1], dataType: "flt ") == nil)
        #expect(SMCCodec.decode([], dataType: "ui8 ") == nil)
    }

    @Test(arguments: [
        ("flt ", 4, 3150.0),
        ("fpe2", 2, 2000.0),
        ("sp78", 2, -12.5),
        ("ui8 ", 1, 1.0),
        ("ui16", 2, 1234.0),
        ("ui32", 4, 70000.0),
    ])
    func `encode decode round trip`(dataType: String, size: Int, value: Double) throws {
        let bytes = try #require(SMCCodec.encode(value, dataType: dataType, size: size))
        #expect(bytes.count == size)
        #expect(SMCCodec.decode(bytes, dataType: dataType) == value)
    }

    @Test func `refuses to encode when size does not match`() {
        #expect(SMCCodec.encode(1, dataType: "flt ", size: 2) == nil)
    }

    @Test func `clamps out of range integers`() {
        #expect(SMCCodec.encode(300, dataType: "ui8 ", size: 1) == [255])
        #expect(SMCCodec.encode(-5, dataType: "ui8 ", size: 1) == [0])
    }
}
