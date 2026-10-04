import Charts
import MacFanCore
import SwiftUI

/// Something with a history worth a closer look.
enum DetailTarget: Hashable, Identifiable {
    case sensor(id: String)
    case category(SensorCategory)
    case fan(index: Int)
    case systemPower

    var id: Self { self }

    var historyKey: String {
        switch self {
        case .sensor(let id): id
        case .category(let category): HistoryStore.key(for: category)
        case .fan(let index): HistoryStore.key(forFan: index)
        case .systemPower: HistoryStore.systemPowerKey
        }
    }
}

/// Opens the history sheet for a target, from anywhere in the main window.
struct ShowDetailAction {
    let action: (DetailTarget) -> Void
    func callAsFunction(_ target: DetailTarget) { action(target) }
}

extension EnvironmentValues {
    @Entry var showDetail = ShowDetailAction { _ in }
}

/// A larger chart with the numbers people ask about: now, typical, highest.
struct HistoryDetailView: View {
    @Environment(AppModel.self) private var model
    @Environment(Preferences.self) private var preferences
    @Environment(\.dismiss) private var dismiss
    @State var target: DetailTarget
    @AppStorage("detailRange") private var range: HistoryRange = .tenMinutes

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.l) {
            header

            Picker("Range", selection: $range) {
                ForEach(HistoryRange.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 240)

            chart
                .frame(height: 220)

            stats

            if case .category(let category) = target {
                CategorySensorList(category: category) { target = .sensor(id: $0) }
            }

            HStack {
                actions
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(Theme.Spacing.xl)
        .frame(width: 560)
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: Theme.Spacing.m) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(tint)
                .frame(width: 36, height: 36)
                .background(tint.opacity(0.12), in: .circle)
            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                title.font(.title2.weight(.semibold))
                if let subtitle {
                    subtitle.font(.callout).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if let current {
                Text(format(current))
                    .font(.system(size: 32, weight: .semibold, design: .rounded))
                    .monospacedDigit()
            }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Chart

    @ViewBuilder
    private var chart: some View {
        let points = model.history.timeline(for: target.historyKey, since: Date().addingTimeInterval(-range.duration))
        if points.count < 2 {
            ContentUnavailableView("Collecting history", systemImage: "chart.xyaxis.line",
                                   description: Text("The chart fills in as MacFan keeps running."))
        } else {
            let domain = yDomain(for: points)
            Chart {
                ForEach(points, id: \.date) { point in
                    // Filled from the bottom of the visible range, so the axis needn't start at zero.
                    AreaMark(x: .value("Time", point.date),
                             yStart: .value("Floor", domain.lowerBound),
                             yEnd: .value("Value", display(point.mean)))
                        .foregroundStyle(.linearGradient(colors: [tint.opacity(0.25), tint.opacity(0)], startPoint: .top, endPoint: .bottom))
                        .interpolationMethod(.monotone)
                    LineMark(x: .value("Time", point.date), y: .value("Value", display(point.mean)))
                        .foregroundStyle(tint)
                        .interpolationMethod(.monotone)
                }
                if let thresholds {
                    RuleMark(y: .value("Hot", display(thresholds.hot)))
                        .foregroundStyle(TemperatureLevel.hot.tint.opacity(0.6))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        .annotation(position: .top, alignment: .leading) {
                            Text("Hot").font(.caption2).foregroundStyle(.secondary)
                        }
                }
            }
            .chartYScale(domain: domain)
            .chartXAxis {
                AxisMarks(values: .stride(by: .minute, count: range.labelStride)) {
                    AxisGridLine()
                    AxisValueLabel(format: .dateTime.hour().minute())
                }
            }
            .accessibilityLabel(title)
        }
    }

    /// Fits the data with some air, and always includes the "hot" line so the headroom is visible.
    private func yDomain(for points: [HistoryPoint]) -> ClosedRange<Double> {
        var values = points.map { display($0.mean) }
        if let thresholds { values.append(display(thresholds.hot)) }
        let low = values.min() ?? 0
        let high = values.max() ?? 1
        let padding = max((high - low) * 0.15, thresholds == nil ? high * 0.05 : 3)
        return max(low - padding, 0)...(high + padding)
    }

    // MARK: Stats

    private var stats: some View {
        let points = model.history.timeline(for: target.historyKey, since: Date().addingTimeInterval(-range.duration))
        let average = points.isEmpty ? nil : points.map(\.mean).reduce(0, +) / Double(points.count)
        let highest = points.map(\.max).max()

        return Grid(alignment: .leading, horizontalSpacing: Theme.Spacing.xxl, verticalSpacing: Theme.Spacing.xxs) {
            GridRow {
                Text("Average").foregroundStyle(.secondary)
                Text("Highest").foregroundStyle(.secondary)
                Text("Peak since MacFan opened").foregroundStyle(.secondary)
            }
            .font(.caption)
            GridRow {
                Text(average.map(format) ?? "—")
                Text(highest.map(format) ?? "—")
                Text(model.history.peak(for: target.historyKey).map(format) ?? "—")
            }
            .font(.title3.weight(.semibold))
            .monospacedDigit()
        }
    }

    // MARK: Actions

    @ViewBuilder
    private var actions: some View {
        if case .sensor(let id) = target {
            Button(preferences.isPinned(id) ? "Unpin from Sidebar" : "Pin to Sidebar",
                   systemImage: preferences.isPinned(id) ? "pin.slash" : "pin") {
                preferences.togglePin(id)
            }
            Menu("More") {
                Button(preferences.menuBarSensorID == id ? "Show Hottest CPU in Menu Bar" : "Show in Menu Bar") {
                    preferences.menuBarSensorID = preferences.menuBarSensorID == id ? nil : id
                }
                Button("Use for Smart Curve") {
                    preferences.cooling.source = .sensor(id: id)
                }
            }
            .fixedSize()
        }
    }

    // MARK: Describing the target

    private var reading: SensorReading? {
        if case .sensor(let id) = target { model.snapshot.reading(id: id) } else { nil }
    }

    private var summary: CategorySummary? {
        guard case .category(let category) = target else { return nil }
        return model.summaries.first { $0.category == category }
    }

    private var fan: FanStatus? {
        guard case .fan(let index) = target else { return nil }
        return model.snapshot.fans.first { $0.index == index }
    }

    private var title: Text {
        switch target {
        case .sensor(let id): Text(verbatim: reading?.sensor.name ?? id)
        case .category(let category): Text(category.title)
        case .fan: fan.map { Text(verbatim: $0.name) } ?? Text("Fan")
        case .systemPower: Text("Power Draw")
        }
    }

    private var subtitle: Text? {
        switch target {
        case .sensor: reading.map { Text($0.sensor.category.title) + Text(verbatim: " · \($0.sensor.rawKey)") }
        case .category: summary.map { Text("Hottest of \($0.count) sensors, now \($0.hottest.sensor.name)") }
        case .fan: fan.map { Text("Range \(Int($0.minimumRPM).formatted())–\(Int($0.maximumRPM).formatted()) rpm") }
        case .systemPower: Text("Everything this Mac is using, including the display")
        }
    }

    private var symbol: String {
        switch target {
        case .sensor: reading?.sensor.category.symbol ?? "thermometer.medium"
        case .category(let category): category.symbol
        case .fan: "fan"
        case .systemPower: "bolt.fill"
        }
    }

    private var current: Double? {
        switch target {
        case .sensor: reading?.celsius
        case .category: summary?.hottest.celsius
        case .fan: fan?.currentRPM
        case .systemPower: model.snapshot.systemPower
        }
    }

    private var thresholds: TemperatureThresholds? {
        switch target {
        case .sensor: reading?.sensor.category.thresholds
        case .category(let category): category.thresholds
        case .fan, .systemPower: nil
        }
    }

    private var tint: Color {
        switch target {
        case .sensor: reading?.level.tint ?? .accentColor
        case .category: summary?.level.tint ?? .accentColor
        case .fan: .accentColor
        case .systemPower: .yellow
        }
    }

    /// Chart values in the unit the user reads.
    private func display(_ value: Double) -> Double {
        thresholds == nil ? value : preferences.unit.convert(fromCelsius: value)
    }

    private func format(_ value: Double) -> String {
        switch target {
        case .sensor, .category: preferences.unit.format(value, fractionDigits: 1)
        case .fan: "\(Int(value.rounded()).formatted()) rpm"
        case .systemPower: Watts.format(value)
        }
    }
}

enum HistoryRange: String, CaseIterable {
    case tenMinutes
    case hour

    var duration: TimeInterval {
        switch self {
        case .tenMinutes: 600
        case .hour: 3600
        }
    }

    var title: LocalizedStringKey {
        switch self {
        case .tenMinutes: "10 Minutes"
        case .hour: "1 Hour"
        }
    }

    /// Minutes between time labels.
    var labelStride: Int {
        switch self {
        case .tenMinutes: 2
        case .hour: 10
        }
    }
}

/// Every sensor in a category, hottest first; picking one drills into it.
private struct CategorySensorList: View {
    @Environment(AppModel.self) private var model
    let category: SensorCategory
    let onSelect: (String) -> Void

    var body: some View {
        let readings = model.visibleReadings
            .filter { $0.sensor.category == category }
            .sorted { $0.celsius > $1.celsius }

        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: Theme.Spacing.s)], spacing: Theme.Spacing.s) {
                ForEach(readings) { reading in
                    Button { onSelect(reading.id) } label: {
                        HStack {
                            Text(reading.sensor.name).lineLimit(1)
                            Spacer(minLength: Theme.Spacing.xs)
                            TemperatureText(celsius: reading.celsius, font: .callout.weight(.medium))
                                .foregroundStyle(reading.level >= .hot ? reading.level.tint : .secondary)
                        }
                        .font(.callout)
                        .padding(.horizontal, Theme.Spacing.s)
                        .padding(.vertical, Theme.Spacing.xs)
                        .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: Theme.Radius.small))
                        .contentShape(.rect)
                    }
                    .buttonStyle(PressableButtonStyle())
                }
            }
        }
        .frame(maxHeight: 132)
    }
}

enum Watts {
    /// "13.9 W"
    static func format(_ watts: Double) -> String {
        "\(watts.formatted(.number.precision(.fractionLength(watts < 10 ? 1 : 0)))) W"
    }
}
