import Foundation

/// Maps raw SMC keys and HID product names to human names and categories.
///
/// This file is the main place to contribute support for new Macs. Rules are checked
/// top to bottom; the first match wins, so put exact keys before wildcard families.
/// In a pattern, `?` matches any single character. In a name, `#` becomes an ordinal
/// ("CPU 1", "CPU 2"…) and is dropped when only one sensor shares the name.
///
/// Run `swift run macfan keys` to list every temperature key on your Mac.
public enum SensorCatalog {
    public struct Rule: Sendable {
        public let pattern: String
        public let category: SensorCategory
        public let name: String

        public init(_ pattern: String, _ category: SensorCategory, _ name: String) {
            self.pattern = pattern
            self.category = category
            self.name = name
        }
    }

    public struct Classification: Hashable, Sendable {
        public let category: SensorCategory
        public let nameTemplate: String
        public let isIdentified: Bool
    }

    public static let smcRules: [Rule] = [
        // CPU — Intel
        Rule("TC0P", .cpu, "CPU Proximity"),
        Rule("TC0D", .cpu, "CPU Die"),
        Rule("TC0E", .cpu, "CPU Die (Virtual)"),
        Rule("TC0F", .cpu, "CPU Die (Filtered)"),
        Rule("TC0H", .cpu, "CPU Heatsink"),
        Rule("TCXC", .cpu, "CPU PECI"),
        Rule("TCSA", .cpu, "CPU System Agent"),
        Rule("TCGC", .gpu, "Integrated GPU"),
        Rule("TC?C", .cpu, "CPU Core #"),
        // CPU — Apple Silicon. Key families differ between chip generations, so these
        // are numbered rather than labelled as performance/efficiency cores.
        Rule("Te??", .cpu, "CPU Efficiency #"),
        Rule("Tp??", .cpu, "CPU #"),
        Rule("Tf??", .cpu, "CPU #"),

        // GPU
        Rule("TG0P", .gpu, "GPU Proximity"),
        Rule("TG0D", .gpu, "GPU Die"),
        Rule("TG0H", .gpu, "GPU Heatsink"),
        Rule("TG??", .gpu, "GPU #"),
        Rule("Tg??", .gpu, "GPU #"),

        // Memory
        Rule("TM0P", .memory, "Memory Proximity"),
        Rule("TM?S", .memory, "Memory Slot #"),
        Rule("Tm??", .memory, "Memory #"),
        Rule("TM??", .memory, "Memory #"),

        // Storage
        Rule("TH0?", .storage, "SSD #"),

        // Battery
        Rule("TB0T", .battery, "Battery"),
        Rule("TB?T", .battery, "Battery Cell #"),

        // Power
        Rule("TPCD", .power, "Platform Controller Hub"),
        Rule("TV??", .power, "Voltage Regulator #"),

        // Wireless
        Rule("TW0P", .wireless, "Wi-Fi Module"),
        Rule("TW??", .wireless, "Wireless #"),

        // Enclosure
        Rule("TA?P", .enclosure, "Ambient #"),
        // `Ta0?` keys on Apple Silicon read well below room temperature; they aren't airflow.
        Rule("TaL?", .enclosure, "Airflow Left #"),
        Rule("TaR?", .enclosure, "Airflow Right #"),
        Rule("TaT?", .enclosure, "Airflow Top #"),
        Rule("Ts?P", .enclosure, "Palm Rest #"),
        Rule("Th?H", .enclosure, "Heat Pipe #"),
        Rule("TI?P", .enclosure, "Thunderbolt #"),
        Rule("TL0P", .enclosure, "Display"),
        Rule("TZ?C", .enclosure, "Thermal Zone #"),
    ]

    /// Fallback when key enumeration is unavailable.
    public static let wellKnownSMCKeys: [String] = smcRules
        .map(\.pattern)
        .filter { !$0.contains("?") }

    public static func classify(smcKey key: String) -> Classification {
        if let rule = smcRules.first(where: { matches(key, pattern: $0.pattern) }) {
            return Classification(category: rule.category, nameTemplate: rule.name, isIdentified: true)
        }
        return Classification(category: .other, nameTemplate: "Sensor \(key)", isIdentified: false)
    }

    /// Classifies a HID temperature service by its `Product` name.
    /// Returns `nil` for services that never carry a useful temperature.
    public static func classify(hidProduct product: String) -> Classification? {
        let name = product.lowercased()
        if name.contains("tcal") { return nil } // calibration constant
        if name.contains("nand") {
            return Classification(category: .storage, nameTemplate: "SSD #", isIdentified: true)
        }
        if name.contains("battery") {
            return Classification(category: .battery, nameTemplate: "Battery #", isIdentified: true)
        }
        if name.contains("tdie") {
            return Classification(category: .cpu, nameTemplate: "SoC Die #", isIdentified: true)
        }
        if name.contains("tdev") {
            return Classification(category: .enclosure, nameTemplate: "Logic Board #", isIdentified: true)
        }
        return Classification(category: .other, nameTemplate: product, isIdentified: false)
    }

    /// SMC data types that can hold a temperature.
    public static func isTemperatureType(_ dataType: String) -> Bool {
        dataType == "flt " || dataType.hasPrefix("sp") || dataType.hasPrefix("fp")
    }

    /// Filters out disconnected sensors (0, negative) and garbage readings.
    public static func isPlausible(celsius: Double) -> Bool {
        celsius.isFinite && celsius > 5 && celsius < 130
    }

    static func matches(_ key: String, pattern: String) -> Bool {
        guard key.count == pattern.count else { return false }
        return zip(key, pattern).allSatisfy { $1 == "?" || $0 == $1 }
    }
}

/// Turns name templates into final names: "CPU #" ×3 → "CPU 1", "CPU 2", "CPU 3"; "GPU #" ×1 → "GPU".
public enum SensorNaming {
    public static func resolve(_ templates: [String]) -> [String] {
        let totals = Dictionary(templates.map { ($0, 1) }, uniquingKeysWith: +)
        var seen: [String: Int] = [:]
        return templates.map { template in
            guard template.contains("#") else { return template }
            if totals[template] == 1 {
                return template
                    .replacingOccurrences(of: " #", with: "")
                    .replacingOccurrences(of: "#", with: "")
            }
            let ordinal = (seen[template] ?? 0) + 1
            seen[template] = ordinal
            return template.replacingOccurrences(of: "#", with: String(ordinal))
        }
    }
}
