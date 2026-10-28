import Charts
import SwiftUI

/// A balance over time as a step line: each value holds until the next one. A faint area under
/// the line, dashed rules at the lowest and the highest value with their figures, a dot at the
/// last point, and an optional shaded window (the period the screen sums up). The caller writes
/// the figures (`valueLabel`) and the dates under the ends.
struct HUDBalanceChart: View {
    struct Point: Hashable {
        var date: Date
        var value: Double
    }

    /// Oldest first.
    let points: [Point]
    var window: ClosedRange<Date>?
    var valueLabel: (Double) -> String
    var startLabel: Text?
    var endLabel: Text?
    var color: Color = .hudAccent
    var height: CGFloat = 96
    /// What the chart is, for VoiceOver.
    var accessibilityLabel: Text = Text("Balance over time")

    var body: some View {
        VStack(spacing: 4) {
            if let low = points.map(\.value).min(), let high = points.map(\.value).max(),
               let start = points.first?.date, let last = points.last {
                chart(low: low, high: high, start: start, last: last)
            } else {
                Color.clear.frame(height: height)
            }
            if startLabel != nil || endLabel != nil {
                HStack {
                    startLabel
                    Spacer(minLength: 8)
                    endLabel
                }
                .font(HUDFont.mono(9, weight: .regular, relativeTo: .caption2))
                .tracking(0.5)
                .textCase(.uppercase)
                .foregroundStyle(Color.hudInkMuted)
                .lineLimit(1)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(accessibilityValue)
    }

    /// `Now 30.27M, low 21.10M, high 31.02M`.
    private var accessibilityValue: Text {
        guard let low = points.map(\.value).min(), let high = points.map(\.value).max(),
              let last = points.last?.value else { return Text(verbatim: "") }
        return Text("Now \(valueLabel(last)), low \(valueLabel(low)), high \(valueLabel(high))")
    }

    private func chart(low: Double, high: Double, start: Date, last: Point) -> some View {
        let span = max(high - low, abs(high) * 0.01, 1)
        let floor = low - span * 0.12
        let ceiling = high + span * 0.25
        let end = max(last.date, start.addingTimeInterval(60))
        return Chart {
            if let window {
                RectangleMark(xStart: .value("From", max(window.lowerBound, start)),
                              xEnd: .value("To", min(window.upperBound, end)),
                              yStart: .value("Floor", floor), yEnd: .value("Ceiling", ceiling))
                    .foregroundStyle(color.opacity(0.06))
            }
            RuleMark(y: .value("Low", low))
                .foregroundStyle(Color.hudLineSubtle)
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 4]))
                .annotation(position: .top, alignment: .leading, spacing: 2) { caption(valueLabel(low)) }
            if high > low {
                RuleMark(y: .value("High", high))
                    .foregroundStyle(Color.hudLineSubtle)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 4]))
                    .annotation(position: .top, alignment: .leading, spacing: 2) { caption(valueLabel(high)) }
            }
            ForEach(points, id: \.self) { point in
                AreaMark(x: .value("Time", point.date),
                         yStart: .value("Floor", floor), yEnd: .value("Balance", point.value))
                    .foregroundStyle(color.opacity(0.12))
                    .interpolationMethod(.stepEnd)
            }
            ForEach(points, id: \.self) { point in
                LineMark(x: .value("Time", point.date), y: .value("Balance", point.value))
                    .foregroundStyle(color)
                    .lineStyle(StrokeStyle(lineWidth: 1.6, lineJoin: .round))
                    .interpolationMethod(.stepEnd)
            }
            PointMark(x: .value("Time", last.date), y: .value("Balance", last.value))
                .foregroundStyle(color)
                .symbolSize(28)
        }
        .chartXScale(domain: start...end)
        .chartYScale(domain: floor...ceiling)
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartLegend(.hidden)
        .frame(height: height)
    }

    private func caption(_ text: String) -> some View {
        Text(verbatim: text)
            .font(HUDFont.mono(9, weight: .regular, relativeTo: .caption2))
            .foregroundStyle(Color.hudInkMuted)
            .lineLimit(1)
            .fixedSize()
    }
}

#Preview("Balance chart") {
    let start = Date(timeIntervalSince1970: 1_791_000_000)
    let day: TimeInterval = 86_400
    let points = (0...40).map { index in
        HUDBalanceChart.Point(date: start.addingTimeInterval(Double(index) * 0.75 * day),
                              value: 24e6 + 6e6 * sin(Double(index) / 6) + Double(index) * 1e5)
    }
    HUDList {
        Section {
            HUDPanel {
                HUDBalanceChart(points: points,
                                window: start.addingTimeInterval(23 * day)...start.addingTimeInterval(30 * day),
                                valueLabel: { ISK.compact($0) },
                                startLabel: Text(verbatim: "Sep 28"), endLabel: Text(verbatim: "Today"))
                    .padding(HUDMetrics.gutter)
            }
            .hudBareRow()
        }
    }
}
