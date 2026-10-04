import AppKit
import MacFanCore
import SwiftUI

/// What sits in the menu bar. Tabular digits keep its width steady as values change.
struct MenuBarLabel: View {
    @Environment(AppModel.self) private var model
    @Environment(Preferences.self) private var preferences

    var body: some View {
        HStack(spacing: Theme.Spacing.xs) {
            Image(systemName: symbol)
            if let text {
                Text(text).monospacedDigit()
            }
        }
    }

    private var symbol: String {
        preferences.menuBarDisplay == .fanSpeed ? "fan" : (model.menuBarReading?.level ?? .cool).symbol
    }

    private var text: String? {
        let temperature = model.menuBarReading.map { preferences.unit.format($0.celsius) }
        let rpm = model.fastestFanRPM.map { "\(Int($0.rounded()).formatted())" }
        switch preferences.menuBarDisplay {
        case .temperature: return temperature
        case .fanSpeed: return rpm ?? temperature
        case .both: return [temperature, rpm].compactMap { $0 }.joined(separator: " · ")
        case .iconOnly: return nil
        }
    }
}

/// The quick glance: status, the parts that matter, fans, and the one control people reach for.
struct MenuBarPanel: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.l) {
            header

            VStack(spacing: Theme.Spacing.s) {
                ForEach(model.summaries.filter { $0.category.isSafetyRelevant }) { summary in
                    HStack {
                        Label(summary.category.title, systemImage: summary.category.symbol)
                        Spacer()
                        TemperatureText(celsius: summary.hottest.celsius, font: .body.weight(.medium))
                            .foregroundStyle(summary.level >= .hot ? summary.level.tint : .primary)
                    }
                }
            }

            if !model.snapshot.fans.isEmpty {
                Divider()
                fans
            }

            Divider()
            footer
        }
        .padding(Theme.Spacing.l)
        .frame(width: 300)
    }

    private var header: some View {
        let status = model.status
        return HStack(alignment: .top, spacing: Theme.Spacing.m) {
            Image(systemName: status.level.symbol)
                .font(.title2)
                .foregroundStyle(status.level.tint)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                Text(status.headline).font(.headline)
                Text(status.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var fans: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            ForEach(model.snapshot.fans) { fan in
                HStack {
                    Text(fan.name)
                    Spacer()
                    RPMText(rpm: fan.currentRPM).foregroundStyle(.secondary)
                }
            }

            Picker("Cooling", selection: Binding(
                get: { model.preferences.cooling.mode },
                set: { model.setCoolingMode($0) }
            )) {
                ForEach(CoolingMode.allCases, id: \.self) { mode in
                    Text(mode.shortTitle).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            if model.preferences.cooling.mode.requiresHelper && !model.helper.isReady {
                Button {
                    openMainWindow()
                } label: {
                    Label("Finish setup to control fans…", systemImage: "lock.shield")
                        .font(.caption)
                }
                .buttonStyle(.link)
            }
        }
    }

    private var footer: some View {
        HStack {
            Button("Open MacFan", action: openMainWindow)
            Spacer()
            SettingsLink {
                Image(systemName: "gearshape")
            }
            .help("Settings")
            Button {
                NSApp.terminate(nil)
            } label: {
                Image(systemName: "power")
            }
            .help("Quit MacFan. Fans return to macOS.")
        }
        .buttonStyle(.borderless)
    }

    private func openMainWindow() {
        NSApp.activate()
        openWindow(id: WindowID.main)
    }
}
