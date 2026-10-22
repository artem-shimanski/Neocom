import Charts
import SwiftUI

/// How full something is over time, against its capacity: the simulated past as a solid line over
/// a faint area, the forecast after now as a dashed line, capacity as a dashed `ink-muted` rule,
/// and a white rule at now. A `limit` — the moment it first fills up — gets a dashed rule of its
/// own in the state colour, its caption, a caption for what happens after it, and the line from
/// then on drawn heavier along the capacity.
struct HUDFillChart: View {
    struct Point: Hashable {
        var date: Date
        var value: Double
        /// `false` — simulated up to now; `true` — forecast after now.
        var isForecast: Bool
    }

    let points: [Point]
    let capacity: Double
    let now: Date
    var limit: Date?
    var limitLabel: Text?
    var beyondLimitLabel: Text?
    /// On the capacity rule, top right. Leave it out when the legend names the rule instead.
    var capacityLabel: Text?
    var color: Color = .hudAccent
    var nowLabel: Text = Text("Now")
    var height: CGFloat = 130

    var body: some View {
        let past = points.filter { !$0.isForecast }
        var forecast = points.filter(\.isForecast)
        if let last = past.last { forecast.insert(last, at: 0) }
        let (beforeFull, atFull) = split(forecast)
        let start = points.first?.date ?? now
        let end = max(points.last?.date ?? now, start.addingTimeInterval(60))

        return Chart {
            ForEach(past, id: \.self) { point in
                AreaMark(x: .value("Time", point.date), y: .value("Volume", point.value))
                    .foregroundStyle(color.opacity(0.16))
                    .interpolationMethod(.linear)
            }
            ForEach(past, id: \.self) { point in
                LineMark(x: .value("Time", point.date), y: .value("Volume", point.value),
                         series: .value("Series", "past"))
                    .foregroundStyle(color)
                    .lineStyle(StrokeStyle(lineWidth: 2))
                    .interpolationMethod(.linear)
            }
            ForEach(beforeFull, id: \.self) { point in
                LineMark(x: .value("Time", point.date), y: .value("Volume", point.value),
                         series: .value("Series", "forecast"))
                    .foregroundStyle(color)
                    .lineStyle(StrokeStyle(lineWidth: 2, dash: [4, 3]))
                    .interpolationMethod(.linear)
            }
            ForEach(atFull, id: \.self) { point in
                LineMark(x: .value("Time", point.date), y: .value("Volume", point.value),
                         series: .value("Series", "full"))
                    .foregroundStyle(color)
                    .lineStyle(StrokeStyle(lineWidth: 3))
                    .interpolationMethod(.linear)
            }

            RuleMark(y: .value("Capacity", capacity))
                .foregroundStyle(Color.hudInkMuted)
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 2]))
                .annotation(position: .bottom, alignment: .trailing, spacing: 3) {
                    if let capacityLabel { caption(capacityLabel, color: .hudInkMuted) }
                }

            if now > start && now < end {
                RuleMark(x: .value("Now", now))
                    .foregroundStyle(Color.hudInk)
                    .lineStyle(StrokeStyle(lineWidth: 1))
                    .annotation(position: .trailing, alignment: .bottom, spacing: 4) {
                        caption(nowLabel, color: .hudInk)
                    }
            }

            if let limit, limit >= start, limit <= end {
                RuleMark(x: .value("Full", limit))
                    .foregroundStyle(color)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .annotation(position: .trailing, alignment: .center, spacing: 4) {
                        VStack(alignment: .leading, spacing: 8) {
                            if let limitLabel { caption(limitLabel, color: color) }
                            if let beyondLimitLabel { caption(beyondLimitLabel, color: .hudWarnNoteInk) }
                        }
                    }
            }
        }
        .chartXScale(domain: start...end)
        .chartYScale(domain: 0...max(capacity, points.map(\.value).max() ?? 0, 1))
        .chartXAxis(.hidden)
        .chartYAxis {
            AxisMarks(position: .leading, values: [0, capacity / 2, capacity]) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 1))
                    .foregroundStyle(value.index == 0 ? Color.hudLineLeader : Color.hudLineSubtle)
                AxisValueLabel {
                    if let figure = value.as(Double.self) {
                        Text(verbatim: figure.formatted(.number.notation(.compactName)))
                            .font(HUDFont.mono(9, weight: .regular, relativeTo: .caption2))
                            .foregroundStyle(Color.hudInkFaint)
                    }
                }
            }
        }
        .frame(height: height)
    }

    /// The forecast up to the moment it reaches capacity, and from that moment on.
    private func split(_ forecast: [Point]) -> ([Point], [Point]) {
        guard let limit, let index = forecast.firstIndex(where: { $0.date >= limit }) else { return (forecast, []) }
        let atLimit = Point(date: max(limit, forecast.first?.date ?? limit), value: capacity, isForecast: true)
        let before = Array(forecast[..<index]) + [atLimit]
        let after = [atLimit] + forecast[index...].filter { $0.date > limit }
        return (before, after.count > 1 ? after : [])
    }

    private func caption(_ text: Text, color: Color) -> some View {
        text
            .font(HUDFont.mono(9, weight: .medium, relativeTo: .caption2))
            .tracking(1)
            .textCase(.uppercase)
            .foregroundStyle(color)
            .lineLimit(1)
            .fixedSize()
    }
}

#Preview("Fill chart") {
    let start = Date(timeIntervalSince1970: 1_791_000_000)
    let hour: TimeInterval = 3600
    let calm = (0...20).map { index in
        HUDFillChart.Point(date: start.addingTimeInterval(Double(index) * 6 * hour),
                           value: 1_300 + 200 * sin(Double(index) / 3), isForecast: index > 9)
    }
    let filling = (0...12).map { index in
        HUDFillChart.Point(date: start.addingTimeInterval(Double(index) * 6 * hour),
                           value: min(10_000, 6_700 + Double(index) * 600), isForecast: index > 3)
    }
    HUDList {
        Section {
            HUDPanel {
                HUDFillChart(points: calm, capacity: 12_000, now: start.addingTimeInterval(57 * hour),
                             capacityLabel: Text(verbatim: "Capacity"))
                    .padding(HUDMetrics.gutter)
            }
            .hudBareRow()
        }
        Section {
            HUDPanel {
                HUDFillChart(points: filling, capacity: 10_000, now: start.addingTimeInterval(20 * hour),
                             limit: start.addingTimeInterval(33 * hour),
                             limitLabel: Text(verbatim: "Full 10.18 05:50"),
                             beyondLimitLabel: Text(verbatim: "Output lost"), color: .hudWarn)
                    .padding(HUDMetrics.gutter)
            }
            .hudBareRow()
        }
    }
}
