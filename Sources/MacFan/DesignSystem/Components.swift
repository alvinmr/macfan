import MacFanCore
import SwiftUI

/// A grouped surface. Solid, not translucent: cards sit on the window background, and
/// stacking translucent layers would hurt legibility.
struct Card<Content: View>: View {
    var padding: CGFloat = Theme.Spacing.l
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.background.secondary, in: .rect(cornerRadius: Theme.Radius.card, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                    .strokeBorder(.separator.opacity(0.6), lineWidth: 0.5)
            }
    }
}

/// A temperature with tabular digits, so the layout never jitters as numbers change.
///
/// Live values change every refresh and are deliberately not animated: a rolling-digit
/// transition is a blur rendered on the CPU, and dozens of them every two seconds made
/// MacFan itself a noticeable source of heat.
struct TemperatureText: View {
    @Environment(Preferences.self) private var preferences
    let celsius: Double
    var font: Font = .body
    var fractionDigits = 0

    var body: some View {
        Text(preferences.unit.format(celsius, fractionDigits: fractionDigits))
            .font(font)
            .monospacedDigit()
    }
}

struct LevelBadge: View {
    let level: TemperatureLevel

    var body: some View {
        Label(level.label, systemImage: level.symbol)
            .font(.caption.weight(.semibold))
            .foregroundStyle(level.tint)
            .padding(.horizontal, Theme.Spacing.s)
            .padding(.vertical, Theme.Spacing.xxs + 1)
            .background(level.tint.opacity(0.12), in: .capsule)
    }
}

/// Recent history as a line with a soft fill. Decorative; values are always shown as text too.
struct Sparkline: View {
    /// More points than this can't be told apart at sparkline size, but still cost drawing time.
    private static let maximumPoints = 48

    var tint: Color = .accentColor
    /// Smallest vertical span, so sensor noise isn't magnified into drama.
    var minimumSpan: Double = 6
    private let values: [Double]

    init(values: [Double], tint: Color = .accentColor, minimumSpan: Double = 6) {
        self.values = Self.downsample(values)
        self.tint = tint
        self.minimumSpan = minimumSpan
    }

    var body: some View {
        Canvas { context, size in
            guard values.count > 1, let low = values.min(), let high = values.max() else { return }
            let span = max(high - low, minimumSpan)
            let floor = (high + low) / 2 - span / 2
            let step = size.width / CGFloat(values.count - 1)

            var line = Path()
            for (index, value) in values.enumerated() {
                let point = CGPoint(
                    x: CGFloat(index) * step,
                    y: size.height - CGFloat((value - floor) / span) * size.height
                )
                index == 0 ? line.move(to: point) : line.addLine(to: point)
            }

            var area = line
            area.addLine(to: CGPoint(x: size.width, y: size.height))
            area.addLine(to: CGPoint(x: 0, y: size.height))
            area.closeSubpath()

            context.fill(area, with: .linearGradient(
                Gradient(colors: [tint.opacity(0.25), tint.opacity(0)]),
                startPoint: .zero,
                endPoint: CGPoint(x: 0, y: size.height)
            ))
            context.stroke(line, with: .color(tint), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
        }
        .accessibilityHidden(true)
    }

    /// Averages neighbouring samples down to `maximumPoints`, keeping the newest value exact.
    private static func downsample(_ values: [Double]) -> [Double] {
        guard values.count > maximumPoints else { return values }
        let size = Double(values.count) / Double(maximumPoints)
        var result = (0..<maximumPoints - 1).map { bucket in
            let slice = values[Int(Double(bucket) * size)..<Int(Double(bucket + 1) * size)]
            return slice.reduce(0, +) / Double(slice.count)
        }
        result.append(values[values.count - 1])
        return result
    }
}

/// How hard a fan is working, as a ring.
struct FanGauge: View {
    let load: Double
    var tint: Color = .accentColor
    var lineWidth: CGFloat = 6

    var body: some View {
        ZStack {
            Circle().stroke(tint.opacity(0.15), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(load, 0.001))
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        // Not animated: it changes every refresh, so an animation would never stop running.
        .accessibilityHidden(true)
    }
}

/// Buttons that look like cards: they respond the instant they're pressed, not on release.
struct PressableButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(Theme.Motion.press, value: configuration.isPressed)
    }
}

/// "12,345 rpm" with tabular digits. Not animated, like `TemperatureText`.
struct RPMText: View {
    let rpm: Double
    var font: Font = .body

    var body: some View {
        Text("\(Int(rpm.rounded()).formatted()) rpm")
            .font(font)
            .monospacedDigit()
    }
}

struct SectionTitle: View {
    let title: LocalizedStringKey
    var subtitle: LocalizedStringKey?

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
            Text(title).font(.title3.weight(.semibold))
            if let subtitle {
                Text(subtitle).font(.callout).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
