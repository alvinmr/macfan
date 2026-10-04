import Foundation
import MacFanCore
import SMCKit

// `macfanctl` — inspect what MacFan sees. Useful for bug reports and for adding
// sensor names for new Macs (see docs/ADDING_SENSORS.md).

let usage = """
    usage: macfanctl <command>

      sensors [--all]   Temperatures MacFan recognises (--all includes unidentified ones)
      fans              Fan speeds and limits
      battery           Battery health
      keys              Every SMC temperature key with its type and value (for contributors)
    """

let arguments = CommandLine.arguments.dropFirst()
let monitor = HardwareMonitor()

switch arguments.first {
case "sensors":
    let showAll = arguments.contains("--all")
    let snapshot = await monitor.snapshot()
    let readings = snapshot.readings
        .filter { showAll || $0.sensor.isIdentified }
        .sorted(by: SensorReading.displayOrder)
    if readings.isEmpty { print("No sensors found.") }
    for reading in readings {
        let category = reading.sensor.category.rawValue.padding(toLength: 10, withPad: " ", startingAt: 0)
        let name = reading.sensor.name.padding(toLength: 26, withPad: " ", startingAt: 0)
        let key = reading.sensor.rawKey.padding(toLength: 18, withPad: " ", startingAt: 0)
        print("\(category) \(name) \(key) \(String(format: "%6.1f °C", reading.celsius))")
    }

case "fans":
    let snapshot = await monitor.snapshot()
    if snapshot.fans.isEmpty { print("This Mac has no fans.") }
    for fan in snapshot.fans {
        let mode = fan.isManual ? "manual" : "auto"
        print("\(fan.name): \(Int(fan.currentRPM)) rpm (min \(Int(fan.minimumRPM)), max \(Int(fan.maximumRPM)), \(mode))")
    }

case "battery":
    guard let battery = BatteryReader.read() else {
        print("No battery.")
        exit(0)
    }
    print("Health:     \(Int((battery.health * 100).rounded()))% (\(battery.condition.rawValue))")
    print("Cycles:     \(battery.cycleCount) of \(battery.ratedCycles)")
    print("Capacity:   \(battery.fullChargeCapacity) / \(battery.designCapacity) mAh")
    print("Charge:     \(Int((battery.charge * 100).rounded()))%\(battery.isCharging ? " (charging)" : "")")
    if let celsius = battery.celsius { print(String(format: "Temperature: %.1f °C", celsius)) }

case "keys":
    do {
        let smc = try SMCConnection()
        for key in try smc.allKeys() where key.name.hasPrefix("T") {
            guard let info = try? smc.info(for: key), SensorCatalog.isTemperatureType(info.dataType) else { continue }
            let value = smc.double(key).map { String(format: "%7.2f", $0) } ?? "      ?"
            let classification = SensorCatalog.classify(smcKey: key.name)
            let label = classification.isIdentified ? classification.nameTemplate : "—"
            print("\(key.name)  \(info.dataType)  \(value)  \(label)")
        }
    } catch {
        print("Could not read the SMC: \(error)")
        exit(1)
    }

default:
    print(usage)
    exit(arguments.isEmpty ? 0 : 64)
}
