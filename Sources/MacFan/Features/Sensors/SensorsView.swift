import AppKit
import MacFanCore
import SwiftUI

struct SensorsView: View {
    @Environment(AppModel.self) private var model
    @Environment(Preferences.self) private var preferences
    @State private var searchText = ""

    var body: some View {
        @Bindable var preferences = preferences

        List {
            ForEach(groups, id: \.category) { group in
                Section {
                    ForEach(group.readings) { reading in
                        SensorRow(reading: reading, history: model.history.values(for: reading.id))
                    }
                } header: {
                    Label(group.category.title, systemImage: group.category.symbol)
                }
            }
        }
        .overlay {
            if groups.isEmpty {
                if searchText.isEmpty {
                    ContentUnavailableView("No Sensors", systemImage: "thermometer.medium.slash",
                                           description: Text("MacFan couldn't find any temperature sensors on this Mac."))
                } else {
                    ContentUnavailableView.search(text: searchText)
                }
            }
        }
        .searchable(text: $searchText, placement: .toolbar, prompt: "Filter sensors")
        .toolbar {
            Toggle(isOn: $preferences.showsUnidentifiedSensors) {
                Label("Show Unidentified Sensors", systemImage: "line.3.horizontal.decrease.circle")
            }
            .help("Show sensors MacFan found but doesn't have a name for yet")
        }
        .navigationTitle("Sensors")
        .navigationSubtitle(Text("\(model.visibleReadings.count) sensors"))
    }

    private var groups: [(category: SensorCategory, readings: [SensorReading])] {
        let filtered = model.visibleReadings.filter { reading in
            searchText.isEmpty
                || reading.sensor.name.localizedCaseInsensitiveContains(searchText)
                || reading.sensor.rawKey.localizedCaseInsensitiveContains(searchText)
        }
        return Dictionary(grouping: filtered, by: \.sensor.category)
            .sorted { $0.key < $1.key }
            .map { ($0.key, $0.value) }
    }
}

private struct SensorRow: View {
    @Environment(Preferences.self) private var preferences
    let reading: SensorReading
    let history: [Double]

    var body: some View {
        HStack(spacing: Theme.Spacing.m) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                HStack(spacing: Theme.Spacing.xs) {
                    Text(reading.sensor.name)
                    if isInMenuBar {
                        Image(systemName: "menubar.rectangle")
                            .foregroundStyle(.secondary)
                            .help("Shown in the menu bar")
                    }
                }
                Text(reading.sensor.rawKey)
                    .font(.caption.monospaced())
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            Sparkline(values: history, tint: reading.level.tint)
                .frame(width: 96, height: 22)

            TemperatureText(celsius: reading.celsius, font: .body.weight(.medium), fractionDigits: 1)
                .foregroundStyle(reading.level >= .hot ? reading.level.tint : .primary)
                .frame(minWidth: 56, alignment: .trailing)
        }
        .padding(.vertical, Theme.Spacing.xxs)
        .contentShape(Rectangle())
        .contextMenu {
            Button(isInMenuBar ? "Show Hottest CPU in Menu Bar" : "Show in Menu Bar") {
                preferences.menuBarSensorID = isInMenuBar ? nil : reading.id
            }
            Button("Use for Smart Curve") {
                preferences.cooling.source = .sensor(id: reading.id)
            }
            Divider()
            Button("Copy Key") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(reading.sensor.rawKey, forType: .string)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(reading.sensor.name))
        .accessibilityValue(Text("\(preferences.unit.format(reading.celsius, fractionDigits: 1)), \(Text(reading.level.label))"))
    }

    private var isInMenuBar: Bool { preferences.menuBarSensorID == reading.id }
}
