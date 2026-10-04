import Testing
@testable import MacFanCore

@Suite("SensorCatalog")
struct SensorCatalogTests {
    @Test func `exact keys win over wildcards`() {
        let proximity = SensorCatalog.classify(smcKey: "TC0P")
        #expect(proximity.nameTemplate == "CPU Proximity")
        #expect(proximity.category == .cpu)

        let core = SensorCatalog.classify(smcKey: "TC3C")
        #expect(core.nameTemplate == "CPU Core #")
    }

    @Test func `integrated GPU is not a CPU core`() {
        #expect(SensorCatalog.classify(smcKey: "TCGC").category == .gpu)
    }

    @Test(arguments: [
        ("Tp01", SensorCategory.cpu),
        ("Te05", .cpu),
        ("Tg0D", .gpu),
        ("TH0a", .storage),
        ("TB1T", .battery),
        ("TW0P", .wireless),
        ("TaLP", .enclosure),
    ])
    func `classifies apple silicon and intel families`(key: String, category: SensorCategory) {
        let result = SensorCatalog.classify(smcKey: key)
        #expect(result.category == category)
        #expect(result.isIdentified)
    }

    @Test func `unknown keys are unidentified`() {
        let result = SensorCatalog.classify(smcKey: "TZZZ")
        #expect(result.category == .other)
        #expect(!result.isIdentified)
        #expect(result.nameTemplate == "Sensor TZZZ")
    }

    @Test func `airflow keys below room temperature are not airflow`() {
        #expect(!SensorCatalog.classify(smcKey: "Ta05").isIdentified)
    }

    @Test func `classifies HID products`() {
        #expect(SensorCatalog.classify(hidProduct: "NAND CH0 temp")?.category == .storage)
        #expect(SensorCatalog.classify(hidProduct: "gas gauge battery")?.category == .battery)
        #expect(SensorCatalog.classify(hidProduct: "PMU tdie3")?.category == .cpu)
        #expect(SensorCatalog.classify(hidProduct: "PMU tcal") == nil)
        #expect(SensorCatalog.classify(hidProduct: "Mystery")?.isIdentified == false)
    }

    @Test func `plausibility rejects disconnected sensors`() {
        #expect(!SensorCatalog.isPlausible(celsius: 0))
        #expect(!SensorCatalog.isPlausible(celsius: -40))
        #expect(!SensorCatalog.isPlausible(celsius: .nan))
        #expect(!SensorCatalog.isPlausible(celsius: 200))
        #expect(SensorCatalog.isPlausible(celsius: 45))
    }

    @Test func `temperature types`() {
        #expect(SensorCatalog.isTemperatureType("flt "))
        #expect(SensorCatalog.isTemperatureType("sp78"))
        #expect(!SensorCatalog.isTemperatureType("ui8 "))
    }
}

@Suite("SensorNaming")
struct SensorNamingTests {
    @Test func `numbers repeated templates in order`() {
        #expect(SensorNaming.resolve(["CPU #", "CPU #", "CPU #"]) == ["CPU 1", "CPU 2", "CPU 3"])
    }

    @Test func `drops the number when there is only one`() {
        #expect(SensorNaming.resolve(["GPU #", "Battery"]) == ["GPU", "Battery"])
    }

    @Test func `counts each template separately`() {
        #expect(SensorNaming.resolve(["SSD #", "CPU #", "SSD #"]) == ["SSD 1", "CPU", "SSD 2"])
    }
}

@Suite("Temperature")
struct TemperatureTests {
    @Test func `levels follow category thresholds`() {
        #expect(SensorCategory.cpu.thresholds.level(for: 85) == .warm)
        #expect(SensorCategory.cpu.thresholds.level(for: 95) == .hot)
        // The same temperature is alarming for a battery.
        #expect(SensorCategory.battery.thresholds.level(for: 56) == .critical)
    }

    @Test func `converts to fahrenheit`() {
        #expect(TemperatureUnit.fahrenheit.convert(fromCelsius: 100) == 212)
        #expect(TemperatureUnit.fahrenheit.convertDelta(fromCelsius: 10) == 18)
        #expect(TemperatureUnit.celsius.convert(fromCelsius: 42) == 42)
    }

    @Test func `display order is natural`() {
        let names = ["CPU 10", "CPU 2", "CPU 1"].map { Fixtures.reading(50, id: $0) }
        #expect(names.sorted(by: SensorReading.displayOrder).map(\.sensor.name) == ["CPU 1", "CPU 2", "CPU 10"])
    }
}
