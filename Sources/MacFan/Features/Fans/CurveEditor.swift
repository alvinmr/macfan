import Charts
import MacFanCore
import SwiftUI

/// Drag the points to shape the curve.
///
/// Interaction details:
/// - A point is grabbed where the pointer touched it — it doesn't jump to center on the cursor.
/// - The curve updates on every pointer move, not when the drag ends.
/// - Dragging past a limit meets increasing resistance (rubber-banding) instead of a hard
///   stop, then springs back to the limit on release.
/// - Raising a point lifts the points after it, so hotter never means slower.
struct CurveEditor: View {
    @Binding var curve: FanCurve
    var liveTemperature: Double?
    /// Called once when the user starts changing a preset curve.
    var onBeginEditing: () -> Void = {}

    @Environment(Preferences.self) private var preferences
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var drag: DragState?
    @State private var hoveredIndex: Int?

    private struct DragState {
        var index: Int
        /// Pointer offset from the point's center at grab time.
        var grabOffset: CGSize
        /// Where the point is drawn — may sit beyond its limits while rubber-banding.
        var displayed: CurvePoint
    }

    private static let domain = FanCurve.temperatureRange
    private static let hitRadius: CGFloat = 22

    var body: some View {
        Chart {
            ForEach(Array(lineSamples.enumerated()), id: \.offset) { _, point in
                AreaMark(
                    x: .value("Temperature", point.temperature),
                    y: .value("Fan speed", point.speed * 100)
                )
                .foregroundStyle(.linearGradient(
                    colors: [Color.accentColor.opacity(0.22), Color.accentColor.opacity(0.02)],
                    startPoint: .top, endPoint: .bottom
                ))

                LineMark(
                    x: .value("Temperature", point.temperature),
                    y: .value("Fan speed", point.speed * 100)
                )
                .foregroundStyle(Color.accentColor)
                .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
            }

            ForEach(Array(displayedPoints.enumerated()), id: \.offset) { index, point in
                PointMark(
                    x: .value("Temperature", point.temperature),
                    y: .value("Fan speed", point.speed * 100)
                )
                .symbolSize(symbolSize(for: index))
                .foregroundStyle(Color.accentColor)
                .accessibilityLabel(Text("Point \(index + 1)"))
                .accessibilityValue(Text("\(preferences.unit.format(point.temperature)), \(Int((point.speed * 100).rounded())) percent"))
            }

            if let liveTemperature {
                let clamped = liveTemperature.clamped(to: Self.domain)
                RuleMark(x: .value("Now", clamped))
                    .foregroundStyle(.secondary)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .annotation(position: .top, alignment: .center, spacing: Theme.Spacing.xs) {
                        Text("Now \(preferences.unit.format(liveTemperature))")
                            .font(.caption2.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                // A hollow ring: clearly "where you are", not another draggable point.
                PointMark(
                    x: .value("Now", clamped),
                    y: .value("Fan speed", curve.speed(at: liveTemperature) * 100)
                )
                .symbol {
                    Circle()
                        .strokeBorder(Color.primary, lineWidth: 2.5)
                        .background(Circle().fill(.background))
                        .frame(width: 14, height: 14)
                }
                .accessibilityLabel(Text("Current temperature"))
            }
        }
        .chartXScale(domain: Self.domain)
        .chartYScale(domain: 0...100)
        .chartXAxis {
            AxisMarks(values: .stride(by: 10)) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let celsius = value.as(Double.self) {
                        Text(preferences.unit.format(celsius))
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: [0, 25, 50, 75, 100]) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let percent = value.as(Double.self) {
                        Text("\(Int(percent))%")
                    }
                }
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geometry in
                Rectangle()
                    .fill(.clear)
                    .contentShape(Rectangle())
                    .gesture(dragGesture(proxy: proxy, geometry: geometry))
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let location):
                            hoveredIndex = nearestPoint(to: location, proxy: proxy, geometry: geometry)?.index
                        case .ended:
                            hoveredIndex = nil
                        }
                    }
            }
        }
        .animation(reduceMotion ? nil : Theme.Motion.press, value: hoveredIndex)
    }

    // MARK: Drawing

    private var displayedPoints: [CurvePoint] {
        var points = curve.points
        if let drag { points[drag.index] = drag.displayed }
        return points
    }

    /// The curve extended flat to both edges of the chart, as the controller treats it.
    private var lineSamples: [CurvePoint] {
        let points = displayedPoints
        guard let first = points.first, let last = points.last else { return [] }
        return [CurvePoint(temperature: Self.domain.lowerBound, speed: first.speed)]
            + points
            + [CurvePoint(temperature: Self.domain.upperBound, speed: last.speed)]
    }

    private func symbolSize(for index: Int) -> CGFloat {
        if drag?.index == index { return 280 }
        if hoveredIndex == index { return 200 }
        return 120
    }

    // MARK: Gesture

    private func dragGesture(proxy: ChartProxy, geometry: GeometryProxy) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if drag == nil {
                    guard let hit = nearestPoint(to: value.startLocation, proxy: proxy, geometry: geometry) else { return }
                    onBeginEditing()
                    drag = DragState(
                        index: hit.index,
                        grabOffset: CGSize(width: hit.center.x - value.startLocation.x,
                                           height: hit.center.y - value.startLocation.y),
                        displayed: curve.points[hit.index]
                    )
                }
                guard var state = drag else { return }

                let target = CGPoint(x: value.location.x + state.grabOffset.width,
                                     y: value.location.y + state.grabOffset.height)
                guard let raw = curvePoint(at: target, proxy: proxy, geometry: geometry) else { return }

                let temperatureBounds = curve.temperatureBounds(forPointAt: state.index)
                let committed = CurvePoint(
                    temperature: raw.temperature.clamped(to: temperatureBounds).rounded(),
                    speed: (raw.speed.clamped(to: 0...1) * 100).rounded() / 100
                )
                curve.move(pointAt: state.index, to: committed)

                state.displayed = CurvePoint(
                    temperature: Self.rubberBand(raw.temperature, within: temperatureBounds, dimension: 12),
                    speed: Self.rubberBand(raw.speed, within: 0...1, dimension: 0.15)
                )
                drag = state
            }
            .onEnded { _ in
                // Settle from wherever the point is now back to its committed position.
                withAnimation(reduceMotion ? nil : Theme.Motion.release) {
                    drag = nil
                }
            }
    }

    private func nearestPoint(to location: CGPoint, proxy: ChartProxy, geometry: GeometryProxy) -> (index: Int, center: CGPoint)? {
        guard let plotFrame = proxy.plotFrame.map({ geometry[$0] }) else { return nil }
        return curve.points.enumerated()
            .compactMap { index, point -> (index: Int, center: CGPoint, distance: CGFloat)? in
                guard let x = proxy.position(forX: point.temperature),
                      let y = proxy.position(forY: point.speed * 100)
                else { return nil }
                let center = CGPoint(x: x + plotFrame.minX, y: y + plotFrame.minY)
                return (index, center, hypot(center.x - location.x, center.y - location.y))
            }
            .filter { $0.distance <= Self.hitRadius }
            .min { $0.distance < $1.distance }
            .map { ($0.index, $0.center) }
    }

    private func curvePoint(at location: CGPoint, proxy: ChartProxy, geometry: GeometryProxy) -> CurvePoint? {
        guard let plotFrame = proxy.plotFrame.map({ geometry[$0] }),
              let temperature = proxy.value(atX: location.x - plotFrame.minX, as: Double.self),
              let percent = proxy.value(atY: location.y - plotFrame.minY, as: Double.self)
        else { return nil }
        return CurvePoint(temperature: temperature, speed: percent / 100)
    }

    /// Past a bound, movement is progressively damped: the further you pull, the less it follows.
    static func rubberBand(_ value: Double, within bounds: ClosedRange<Double>, dimension: Double, constant: Double = 0.55) -> Double {
        let clamped = value.clamped(to: bounds)
        let overshoot = value - clamped
        guard overshoot != 0 else { return value }
        let resisted = (abs(overshoot) * dimension * constant) / (dimension + constant * abs(overshoot))
        return clamped + (overshoot > 0 ? resisted : -resisted)
    }
}
