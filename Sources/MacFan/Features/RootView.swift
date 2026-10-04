import MacFanCore
import SwiftUI

/// Sidebar items are named for what they contain, so it's obvious where everything lives.
enum Destination: String, CaseIterable, Identifiable, Hashable {
    case overview
    case sensors
    case fans
    case battery

    var id: Self { self }

    var title: LocalizedStringKey {
        switch self {
        case .overview: "Overview"
        case .sensors: "Sensors"
        case .fans: "Fans"
        case .battery: "Battery"
        }
    }

    var symbol: String {
        switch self {
        case .overview: "gauge.with.dots.needle.67percent"
        case .sensors: "thermometer.medium"
        case .fans: "fan"
        case .battery: "battery.75percent"
        }
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(Preferences.self) private var preferences
    // Single-window app: reopen where the user left off.
    @AppStorage("destination") private var destination: Destination = .overview
    @State private var detail: DetailTarget?

    var body: some View {
        NavigationSplitView {
            List(selection: selection) {
                Section {
                    ForEach(availableDestinations) { item in
                        Label(item.title, systemImage: item.symbol)
                            .badge(badge(for: item))
                            .tag(item)
                    }
                }

                Section("Pinned") {
                    ForEach(pinnedReadings) { reading in
                        PinnedSensorRow(reading: reading)
                    }
                    if pinnedReadings.isEmpty {
                        Text("Right-click a sensor to keep it here.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .selectionDisabled()
                    }
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                SidebarStatus { destination = .overview }
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 220)
        } detail: {
            switch destination {
            case .overview: OverviewView(destination: $destination)
            case .sensors: SensorsView()
            case .fans: FansView()
            case .battery: BatteryView()
            }
        }
        .environment(\.showDetail, ShowDetailAction { detail = $0 })
        .sheet(item: $detail) { target in
            HistoryDetailView(target: target)
        }
    }

    private var availableDestinations: [Destination] {
        Destination.allCases.filter { $0 != .battery || model.snapshot.battery != nil }
    }

    private var pinnedReadings: [SensorReading] {
        preferences.pinnedSensorIDs.compactMap(model.snapshot.reading(id:))
    }

    /// The one number each section is about, so the sidebar answers questions on its own.
    private func badge(for item: Destination) -> Text? {
        switch item {
        case .overview:
            return nil
        case .sensors:
            return model.snapshot.hottest().map { Text(preferences.unit.format($0.celsius)) }
        case .fans:
            return model.fastestFanRPM.map { Text("\(Int($0.rounded()).formatted()) rpm") }
        case .battery:
            return model.snapshot.battery.map { Text("\(Int(($0.charge * 100).rounded()))%") }
        }
    }

    /// `List` selection is optional; the destination never is.
    private var selection: Binding<Destination?> {
        Binding { destination } set: { if let new = $0 { destination = new } }
    }
}

private struct PinnedSensorRow: View {
    @Environment(Preferences.self) private var preferences
    @Environment(\.showDetail) private var showDetail
    let reading: SensorReading

    var body: some View {
        Button {
            showDetail(.sensor(id: reading.id))
        } label: {
            HStack(spacing: Theme.Spacing.s) {
                Image(systemName: reading.sensor.category.symbol)
                    .foregroundStyle(.secondary)
                    .frame(width: 18)
                Text(reading.sensor.name).lineLimit(1)
                Spacer(minLength: Theme.Spacing.xs)
                TemperatureText(celsius: reading.celsius)
                    .foregroundStyle(reading.level >= .hot ? reading.level.tint : .secondary)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Unpin") { preferences.togglePin(reading.id) }
        }
        .help("Show history")
    }
}

/// How the Mac is doing and who runs the fans, visible from every page.
private struct SidebarStatus: View {
    @Environment(AppModel.self) private var model
    let onOpen: () -> Void

    var body: some View {
        let status = model.status
        Button(action: onOpen) {
            HStack(alignment: .top, spacing: Theme.Spacing.s) {
                Image(systemName: status.level.symbol)
                    .foregroundStyle(status.level.tint)
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                    Text(status.headline)
                        .font(.callout.weight(.semibold))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
            }
            .padding(Theme.Spacing.m)
            .background(status.level.tint.opacity(0.1), in: .rect(cornerRadius: Theme.Radius.card, style: .continuous))
            .contentShape(.rect)
        }
        .buttonStyle(PressableButtonStyle())
        .padding(Theme.Spacing.m)
        .accessibilityElement(children: .combine)
    }

    private var detail: String {
        var parts: [String] = []
        if !model.snapshot.fans.isEmpty {
            parts.append(String(localized: CoolingModeTag.text(for: model.cooling.state, mode: model.preferences.cooling.mode)))
        }
        if let watts = model.snapshot.systemPower {
            parts.append(Watts.format(watts))
        }
        return parts.joined(separator: " · ")
    }
}

/// ⌘1…⌘4 jump between sections, as in Finder and Mail.
struct NavigationCommands: Commands {
    @AppStorage("destination") private var destination: Destination = .overview

    var body: some Commands {
        CommandGroup(before: .sidebar) {
            ForEach(Array(Destination.allCases.enumerated()), id: \.element) { index, item in
                Button(item.title) { destination = item }
                    .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
            }
            Divider()
        }
    }
}
