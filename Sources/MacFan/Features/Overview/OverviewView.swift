import MacFanCore
import SwiftUI

struct OverviewView: View {
    @Environment(AppModel.self) private var model
    @Binding var destination: Destination

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                StatusHero(status: model.status, thermalState: model.thermalState)

                if !model.snapshot.fans.isEmpty {
                    FansOverviewCard(onManage: { destination = .fans })
                }

                // Only parts whose temperature is worth acting on. Everything else is in Sensors.
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 200), spacing: Theme.Spacing.l)],
                    spacing: Theme.Spacing.l
                ) {
                    ForEach(model.summaries.filter(\.category.isSafetyRelevant)) { summary in
                        CategoryCard(
                            summary: summary,
                            history: model.history.values(for: HistoryStore.key(for: summary.category))
                        )
                    }
                }

                Button {
                    destination = .sensors
                } label: {
                    Label("All \(model.visibleReadings.count) sensors", systemImage: "arrow.right")
                        .labelStyle(TrailingIconLabelStyle())
                }
                .buttonStyle(.link)
            }
            .padding(Theme.Spacing.xl)
            .frame(maxWidth: 1100)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("Overview")
    }
}

/// The answer to "is my Mac OK?", big and first.
private struct StatusHero: View {
    let status: ThermalStatus
    let thermalState: ProcessInfo.ThermalState

    var body: some View {
        HStack(alignment: .center, spacing: Theme.Spacing.l) {
            Image(systemName: status.level.symbol)
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(status.level.tint)
                .frame(width: 60, height: 60)
                .background(status.level.tint.opacity(0.12), in: .circle)
                .contentTransition(.symbolEffect(.replace))

            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text(status.headline)
                    .font(.largeTitle.weight(.bold))
                Text(status.detail)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: Theme.Spacing.l)

            VStack(alignment: .trailing, spacing: Theme.Spacing.xxs) {
                Text("Thermal pressure")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(status.pressure)
                    .font(.headline)
            }
            .help("How much macOS is limiting performance to manage heat. Nominal means not at all.")
        }
        .fluidAnimation(value: status)
        .accessibilityElement(children: .combine)
    }
}

private struct CategoryCard: View {
    let summary: CategorySummary
    let history: [Double]

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                HStack {
                    Label(summary.category.title, systemImage: summary.category.symbol)
                        .font(.headline)
                    Spacer()
                    LevelBadge(level: summary.level)
                }

                TemperatureText(celsius: summary.hottest.celsius, font: .system(size: 40, weight: .semibold, design: .rounded))

                Sparkline(values: history, tint: summary.level.tint)
                    .frame(height: 32)

                Text(caption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var caption: String {
        summary.count == 1
            ? summary.hottest.sensor.name
            : String(localized: "Hottest: \(summary.hottest.sensor.name) · \(summary.count) sensors")
    }
}

private struct FansOverviewCard: View {
    @Environment(AppModel.self) private var model
    let onManage: () -> Void

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                HStack {
                    Label("Fans", systemImage: "fan")
                        .font(.headline)
                    Spacer()
                    CoolingModeTag()
                    Button("Change…", action: onManage)
                }

                HStack(spacing: Theme.Spacing.xxl) {
                    ForEach(model.snapshot.fans) { fan in
                        HStack(spacing: Theme.Spacing.m) {
                            FanGauge(load: fan.load)
                                .frame(width: 44, height: 44)
                            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                                Text(fan.name).font(.subheadline).foregroundStyle(.secondary)
                                RPMText(rpm: fan.currentRPM, font: .title3.weight(.semibold))
                            }
                        }
                        .accessibilityElement(children: .combine)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }
}

/// Who is in charge of the fans right now, in a word.
struct CoolingModeTag: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Text(text)
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, Theme.Spacing.s)
            .padding(.vertical, Theme.Spacing.xxs + 1)
            .background(.quaternary, in: .capsule)
    }

    private var text: LocalizedStringKey {
        switch model.cooling.state {
        case .system: "Managed by macOS"
        case .emergency: "macOS (safety)"
        case .noData: "macOS (no data)"
        case .controlling: model.preferences.cooling.mode.title
        case .needsHelper: "Needs setup"
        case .failed: "Error"
        }
    }
}

private struct TrailingIconLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: Theme.Spacing.xs) {
            configuration.title
            configuration.icon
        }
    }
}
