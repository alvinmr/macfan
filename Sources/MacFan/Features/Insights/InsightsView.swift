import MacFanCore
import SwiftUI

/// What MacFan has learned over days and weeks: how well this Mac cools, and when it ran hot.
struct InsightsView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                CoolingHealthCard()
                HotMomentsCard()
                Label("Insights are kept only on this Mac.", systemImage: "lock")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(Theme.Spacing.xl)
            .frame(maxWidth: 900)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("Insights")
    }
}

// MARK: - Cooling health

/// Learns how this Mac normally cools, so it can later say when that gets worse.
private struct CoolingHealthCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let days = model.insights.cooling.daysCollected()
        let needed = CoolingLog.learningDays

        Card {
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                HStack {
                    Label("Cooling Health", systemImage: "wind")
                        .font(.headline)
                    Spacer()
                    Text(days >= needed ? "Ready" : "Learning")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, Theme.Spacing.s)
                        .padding(.vertical, Theme.Spacing.xxs + 1)
                        .background(.quaternary, in: .capsule)
                }

                if days >= needed {
                    Text("MacFan knows how your Mac normally cools. The comparison arrives in an upcoming update.")
                        .font(.title3.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("Learning how your Mac normally cools")
                        .font(.title3.weight(.semibold))
                    ProgressView(value: Double(days), total: Double(needed)) {
                        EmptyView()
                    } currentValueLabel: {
                        Text("\(days) of \(needed) days")
                            .monospacedDigit()
                    }
                }

                Text("MacFan quietly notes how warm your Mac gets for the work it's doing. Once it knows what's normal, it can tell you when cooling gets worse than it used to be — usually a sign of dust in the vents or a tired fan.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - Hot moments

/// When the Mac ran hot or slowed itself down, and which apps were busy.
private struct HotMomentsCard: View {
    @Environment(AppModel.self) private var model
    @State private var showsAll = false
    @State private var confirmsClear = false

    var body: some View {
        let all = model.insights.moments
        let week = Date().addingTimeInterval(-7 * 24 * 3600)
        let recent = all.filter { $0.end >= week }
        let shown = showsAll ? all : recent

        Card {
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                HStack {
                    Label("Hot Moments", systemImage: "flame")
                        .font(.headline)
                    Spacer()
                    if !all.isEmpty {
                        Menu {
                            Button("Clear History…", role: .destructive) { confirmsClear = true }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                        .menuStyle(.borderlessButton)
                        .menuIndicator(.hidden)
                        .fixedSize()
                        .accessibilityLabel("More")
                    }
                }

                Text("Times your Mac ran hot or slowed itself down for at least 30 seconds, and the apps that were busy.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let now = model.hotMomentInProgress {
                    HotMomentRow(moment: now, isOngoing: true)
                }

                if shown.isEmpty && model.hotMomentInProgress == nil {
                    Label(all.isEmpty ? "None yet. Your Mac has kept its cool." : "None in the last 7 days.",
                          systemImage: "checkmark.circle")
                        .foregroundStyle(.secondary)
                        .padding(.vertical, Theme.Spacing.s)
                } else {
                    ForEach(shown) { moment in
                        Divider()
                        HotMomentRow(moment: moment, isOngoing: false)
                    }
                }

                if all.count > recent.count {
                    Button(showsAll ? "Show Last 7 Days" : "Show All \(all.count)") { showsAll.toggle() }
                        .buttonStyle(.link)
                }
            }
        }
        .confirmationDialog("Clear all hot moments?", isPresented: $confirmsClear) {
            Button("Clear History", role: .destructive) { model.clearHotMoments() }
        } message: {
            Text("Cooling Health keeps what it has learned.")
        }
    }
}

private struct HotMomentRow: View {
    @Environment(Preferences.self) private var preferences
    let moment: HotMoment
    let isOngoing: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            HStack(alignment: .firstTextBaseline) {
                if isOngoing {
                    Text("Now")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, Theme.Spacing.s)
                        .padding(.vertical, Theme.Spacing.xxs)
                        .background(TemperatureLevel.hot.tint, in: .capsule)
                }
                Text(moment.start, format: .relative(presentation: .named, unitsStyle: .wide))
                    .font(.headline)
                Text(moment.start, format: .dateTime.hour().minute())
                    .foregroundStyle(.secondary)
                Spacer()
                Text(summary)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            if !moment.culprits.isEmpty {
                HStack(spacing: Theme.Spacing.l) {
                    ForEach(moment.culprits, id: \.id) { culprit in
                        Label {
                            Text("\(culprit.name) \(CPUPercent.format(culprit.share))")
                        } icon: {
                            AppIcon(culprit: culprit, size: 16)
                        }
                        .font(.callout)
                    }
                }
            }
        }
        .padding(.vertical, Theme.Spacing.xxs)
        .accessibilityElement(children: .combine)
    }

    /// "97° CPU 3 · 4 min · slowed down 2 min"
    private var summary: String {
        var parts = ["\(preferences.unit.format(moment.peakCelsius)) \(moment.peakSensor)", minutes(moment.duration)]
        if moment.throttledSeconds >= 30 {
            parts.append(String(localized: "slowed down \(minutes(moment.throttledSeconds))"))
        }
        return parts.joined(separator: " · ")
    }

    private func minutes(_ seconds: TimeInterval) -> String {
        Duration.seconds(max(seconds, 60)).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated))
    }
}
