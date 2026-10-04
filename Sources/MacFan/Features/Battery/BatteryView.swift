import MacFanCore
import SwiftUI

struct BatteryView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            if let battery = model.snapshot.battery {
                VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                    HealthHero(battery: battery)
                    BatteryFacts(battery: battery, temperature: temperature(of: battery), systemPower: model.snapshot.systemPower)
                }
                .padding(Theme.Spacing.xl)
                .frame(maxWidth: 900)
                .frame(maxWidth: .infinity)
            } else {
                ContentUnavailableView("No Battery", systemImage: "battery.0percent",
                                       description: Text("This Mac runs on wall power."))
                    .padding(.top, Theme.Spacing.xxl)
            }
        }
        .navigationTitle("Battery")
    }

    /// Recent macOS no longer publishes battery temperature in IORegistry; the SMC sensor has it.
    private func temperature(of battery: BatteryInfo) -> Double? {
        battery.celsius ?? model.snapshot.hottest(in: [.battery])?.celsius
    }
}

private struct HealthHero: View {
    let battery: BatteryInfo

    var body: some View {
        HStack(spacing: Theme.Spacing.xl) {
            ZStack {
                FanGauge(load: min(battery.health, 1), tint: tint, lineWidth: 10)
                VStack(spacing: 0) {
                    Text("\(Int((battery.health * 100).rounded()))%")
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    Text("capacity").font(.caption).foregroundStyle(.secondary)
                }
            }
            .frame(width: 120, height: 120)

            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text(headline).font(.largeTitle.weight(.bold))
                Text(detail)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var tint: Color {
        battery.condition == .normal ? .green : .orange
    }

    private var headline: LocalizedStringKey {
        battery.condition == .normal ? "Battery is healthy" : "Service recommended"
    }

    private var detail: LocalizedStringKey {
        if battery.condition == .normal {
            return "It holds \(Int((battery.health * 100).rounded()))% of its original charge. Apple considers anything above 80% normal."
        }
        return "It holds noticeably less charge than when new. An Apple Store or authorized provider can replace it."
    }
}

private struct BatteryFacts: View {
    @Environment(Preferences.self) private var preferences
    let battery: BatteryInfo
    let temperature: Double?
    let systemPower: Double?

    /// Small currents are measurement noise around "full and idle".
    private var batteryFlow: (title: LocalizedStringKey, value: String)? {
        guard let watts = battery.power, abs(watts) >= 0.5 else { return nil }
        return watts > 0 ? ("Charging at", Watts.format(watts)) : ("Draining at", Watts.format(-watts))
    }

    var body: some View {
        Card {
            Grid(alignment: .leading, horizontalSpacing: Theme.Spacing.xl, verticalSpacing: Theme.Spacing.m) {
                row("Charge") {
                    HStack(spacing: Theme.Spacing.s) {
                        ProgressView(value: battery.charge)
                            .frame(width: 120)
                        Text("\(Int((battery.charge * 100).rounded()))%").monospacedDigit()
                    }
                }
                Divider()
                row("Power source") {
                    if battery.isPluggedIn, let watts = battery.adapterWatts {
                        Text(battery.isCharging ? "\(watts) W adapter · charging" : "\(watts) W adapter")
                    } else {
                        Text(battery.isPluggedIn ? (battery.isCharging ? "Power adapter · charging" : "Power adapter") : "Battery")
                    }
                }
                if let flow = batteryFlow {
                    Divider()
                    row(flow.title) {
                        Text(flow.value).monospacedDigit()
                    }
                }
                if let minutes = battery.minutesRemaining {
                    Divider()
                    row(battery.isCharging ? "Until full" : "Time left") {
                        Text(Duration.seconds(minutes * 60).formatted(.units(allowed: [.hours, .minutes], width: .wide)))
                    }
                }
                if let systemPower {
                    Divider()
                    row("Mac is using") {
                        Text(Watts.format(systemPower)).monospacedDigit()
                    }
                }
                Divider()
                row("Cycle count") {
                    Text("\(battery.cycleCount.formatted()) of \(battery.ratedCycles.formatted()) rated")
                        .monospacedDigit()
                }
                Divider()
                row("Full charge") {
                    Text("\(battery.fullChargeCapacity.formatted()) mAh (new: \(battery.designCapacity.formatted()) mAh)")
                        .monospacedDigit()
                }
                if let temperature {
                    Divider()
                    row("Temperature") {
                        let level = SensorCategory.battery.thresholds.level(for: temperature)
                        HStack(spacing: Theme.Spacing.s) {
                            TemperatureText(celsius: temperature, fractionDigits: 1)
                            if level > .cool { LevelBadge(level: level) }
                        }
                    }
                }
            }
        }
    }

    private func row<Content: View>(_ title: LocalizedStringKey, @ViewBuilder value: () -> Content) -> some View {
        GridRow {
            Text(title).foregroundStyle(.secondary)
            value()
        }
    }
}
