import MacFanCore
import SwiftUI

extension CoolingMode {
    var title: LocalizedStringResource {
        switch self {
        case .automatic: "Automatic"
        case .curve: "Smart Curve"
        case .fixed: "Fixed Speed"
        case .max: "Full Speed"
        }
    }

    var shortTitle: LocalizedStringKey {
        switch self {
        case .automatic: "Auto"
        case .curve: "Curve"
        case .fixed: "Fixed"
        case .max: "Max"
        }
    }

    var subtitle: LocalizedStringKey {
        switch self {
        case .automatic: "macOS decides. Quiet and safe."
        case .curve: "Speed follows temperature."
        case .fixed: "One steady speed."
        case .max: "Most cooling, most noise."
        }
    }

    var symbol: String {
        switch self {
        case .automatic: "leaf"
        case .curve: "chart.line.uptrend.xyaxis"
        case .fixed: "dial.medium"
        case .max: "wind"
        }
    }
}

extension CurvePreset {
    var title: LocalizedStringKey {
        switch self {
        case .quiet: "Quiet"
        case .balanced: "Balanced"
        case .performance: "Strong"
        case .custom: "Custom"
        }
    }
}

extension TemperatureSource {
    var title: LocalizedStringKey {
        switch self {
        case .hottestCPU: "Hottest CPU sensor"
        case .hottestGPU: "Hottest GPU sensor"
        case .hottestOverall: "Hottest sensor"
        case .sensor: "A specific sensor"
        }
    }
}
