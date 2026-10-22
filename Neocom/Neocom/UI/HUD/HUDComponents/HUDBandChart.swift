import Charts
import SwiftUI

/// A series over time drawn the way a price history reads: the value as a line inside the
/// band of its low and high, and under it a strip of bars for how much happened in each
/// period. The selected period is a white rule across the line and a white bar below it;
/// tapping or scrubbing either part picks one (`selection`).
///
/// The value axis is fitted to the bulk of the band — the 3rd to the 97th percentile, plus a
/// margin — rather than to its extremes, so one absurd trade does not flatten a month of prices
/// into a line along the bottom. What reaches past it is drawn at the edge. Its three labels
/// (top, middle, bottom) and the bar strip's top label are the caller's, through `valueLabel`
/// and `barLabel`; so is the time axis under the strip, which the caller knows the dates of.
struct HUDBandChart: View {
    struct Point: Identifiable {
        var id: Int
        var value: Double
        var low: Double
        var high: Double
        var bar: Double
        /// What VoiceOver says for the period's bar: its date and figure.
        var accessibilityLabel: Text
    }

    let points: [Point]
    @Binding var selection: Int?
    var valueLabel: (Double) -> String
    var barLabel: (Double) -> String
    var color: Color = .hudAccent
    var height: CGFloat = 130
    var barsHeight: CGFloat = 34
    /// What the band chart is, for VoiceOver.
    var accessibilityLabel: Text = Text("Average with low to high band")

    /// The width of the label column on the leading side, shared by both parts so their plots
    /// line up. The caller indents the time axis by `labelWidth + labelSpacing`.
    static let labelWidth: CGFloat = 36
    static let labelSpacing: CGFloat = 6

    @State private var rawSelection: Double?

    var body: some View {
        let domain = Self.valueDomain(points)
        VStack(spacing: 6) {
            bandChart(domain: domain)
            barChart
        }
        .onChange(of: rawSelection) { _, value in
            guard let value, !points.isEmpty else { return }
            selection = min(max(Int(value.rounded()), 0), points.count - 1)
        }
    }

    private var xDomain: ClosedRange<Double> { -0.5...(Double(max(points.count, 1)) - 0.5) }

    private func bandChart(domain: ClosedRange<Double>) -> some View {
        let clamp = { (value: Double) in min(max(value, domain.lowerBound), domain.upperBound) }
        let middle = (domain.lowerBound + domain.upperBound) / 2
        return Chart {
            ForEach(points) { point in
                AreaMark(x: .value("Period", Double(point.id)),
                         yStart: .value(String(localized: "chart.band.low", defaultValue: "Low", comment: "Chart value: the band's lower edge"), clamp(point.low)),
                         yEnd: .value(String(localized: "chart.band.high", defaultValue: "High", comment: "Chart value: the band's upper edge"), clamp(point.high)),
                         series: .value("Series", "Band"))
                    .foregroundStyle(color.opacity(0.16))
            }
            ForEach(points) { point in
                LineMark(x: .value("Period", Double(point.id)), y: .value("Value", clamp(point.value)),
                         series: .value("Series", "Value"))
                    .foregroundStyle(color)
                    .lineStyle(StrokeStyle(lineWidth: 1.6, lineJoin: .round))
            }
            if let selection, points.indices.contains(selection) {
                RuleMark(x: .value("Period", Double(selection)))
                    .foregroundStyle(Color.hudInk)
                    .lineStyle(StrokeStyle(lineWidth: 1))
            }
        }
        .chartXScale(domain: xDomain)
        .chartYScale(domain: domain)
        .chartXAxis(.hidden)
        .chartYAxis {
            AxisMarks(position: .leading, values: [domain.lowerBound, middle, domain.upperBound]) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 1))
                    .foregroundStyle(value.index == 0 ? Color.hudLineLeader : Color.hudLineSubtle)
                // The bottom label sits above its line, clear of the bar strip's top label.
                AxisValueLabel(anchor: value.index == 0 ? .bottomTrailing : .trailing,
                               horizontalSpacing: Self.labelSpacing) {
                    if let figure = value.as(Double.self) {
                        axisLabel(valueLabel(figure))
                    }
                }
            }
        }
        .chartXSelection(value: $rawSelection)
        .frame(height: height)
        .accessibilityLabel(accessibilityLabel)
    }

    private var barChart: some View {
        let top = max(points.map(\.bar).max() ?? 0, 1)
        return Chart {
            ForEach(points) { point in
                RectangleMark(xStart: .value("Period", Double(point.id) - barHalfWidth),
                              xEnd: .value("Period", Double(point.id) + barHalfWidth),
                              yStart: .value("Bar", 0),
                              // A period with nothing in it still shows a sliver, not a gap in the axis.
                              yEnd: .value("Bar", max(point.bar, top * 0.02)))
                    .foregroundStyle(point.id == selection ? Color.hudInk : color.opacity(0.35))
                    .clipShape(UnevenRoundedRectangle(topLeadingRadius: 1, topTrailingRadius: 1))
                    .accessibilityLabel(point.accessibilityLabel)
            }
        }
        .chartXScale(domain: xDomain)
        .chartYScale(domain: 0...top)
        .chartXAxis(.hidden)
        .chartYAxis {
            AxisMarks(position: .leading, values: [0, top]) { value in
                if value.index == 0 {
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 1)).foregroundStyle(Color.hudLineLeader)
                }
                // The top label hangs below its line, clear of the band chart's bottom label.
                AxisValueLabel(anchor: value.index == 0 ? .bottomTrailing : .topTrailing,
                               horizontalSpacing: Self.labelSpacing) {
                    if let figure = value.as(Double.self) {
                        axisLabel(figure == 0 ? "0" : barLabel(figure))
                    }
                }
            }
        }
        .chartXSelection(value: $rawSelection)
        .frame(height: barsHeight)
    }

    /// Bars a hair apart while they are wide enough to tell apart, touching once they are not.
    private var barHalfWidth: Double { points.count > 100 ? 0.5 : 0.4 }

    private func axisLabel(_ text: String) -> some View {
        Text(verbatim: text)
            .font(HUDFont.mono(9, weight: .regular, relativeTo: .caption2))
            .foregroundStyle(Color.hudInkFaint)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .frame(width: Self.labelWidth, alignment: .trailing)
    }

    /// The bulk of the band with 8 % of its height to spare on either side. Never empty: a
    /// series that is one flat price gets a margin of its own.
    static func valueDomain(_ points: [Point]) -> ClosedRange<Double> {
        guard !points.isEmpty else { return 0...1 }
        let lows = points.map(\.low).sorted()
        let highs = points.map(\.high).sorted()
        let count = points.count
        var low = min(lows[Int(Double(count) * 0.03)], points.map(\.value).min() ?? lows[0])
        var high = max(highs[min(count - 1, Int((Double(count) * 0.97).rounded(.up)))], points.map(\.value).max() ?? highs[0])
        if high <= low {
            let margin = max(abs(low) * 0.05, 1)
            return (low - margin)...(high + margin)
        }
        let pad = (high - low) * 0.08
        low -= pad
        high += pad
        return low...high
    }
}

#Preview("Band chart") {
    @Previewable @State var selection: Int? = 29
    let points = (0..<30).map { index -> HUDBandChart.Point in
        let value = 9_200_000 + sin(Double(index) / 4) * 400_000
        return HUDBandChart.Point(id: index, value: value, low: value * 0.93, high: value * 1.06,
                                  bar: Double(4 + index % 7), accessibilityLabel: Text(verbatim: "Day \(index)"))
    }
    HUDList {
        Section {
            HUDPanel {
                HUDBandChart(points: points, selection: $selection,
                             valueLabel: { ISK.compact($0) },
                             barLabel: { $0.formatted(.number.precision(.fractionLength(0))) })
                    .padding(HUDMetrics.gutter)
            }
            .hudBareRow()
        }
    }
}
