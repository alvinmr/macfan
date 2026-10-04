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
    // Single-window app: reopen where the user left off.
    @AppStorage("destination") private var destination: Destination = .overview

    var body: some View {
        NavigationSplitView {
            List(availableDestinations, selection: selection) { item in
                Label(item.title, systemImage: item.symbol)
                    .tag(item)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200)
        } detail: {
            switch destination {
            case .overview: OverviewView(destination: $destination)
            case .sensors: SensorsView()
            case .fans: FansView()
            case .battery: BatteryView()
            }
        }
    }

    private var availableDestinations: [Destination] {
        Destination.allCases.filter { $0 != .battery || model.snapshot.battery != nil }
    }

    /// `List` selection is optional; the destination never is.
    private var selection: Binding<Destination?> {
        Binding { destination } set: { if let new = $0 { destination = new } }
    }
}
