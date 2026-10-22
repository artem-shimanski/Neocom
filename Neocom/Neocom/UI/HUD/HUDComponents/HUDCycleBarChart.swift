import Charts
import SwiftUI

/// One bar per cycle, split at now: cycles done in the state colour, the one under way a shade
/// fainter, the forecast fainter still, and the selected cycle in `ink`. A white rule marks now.
/// Tapping or scrubbing picks a cycle (`selection`).
///
/// The figures go on a leading axis of compact values (`15K`) over `line-subtle` grid lines; the
/// time axis is left to the caller, which knows what the first and last bar stand for.
struct HUDCycleBarChart: View {
    let values: [Double]
    /// Now, in cycles from the start: 27.75 is three quarters into the 28th cycle. At or past
    /// `values.count`, every bar is done.
    let nowPosition: Double
    @Binding var selection: Int?
    var color: Color = .hudAccent
    var nowLabel: Text = Text("Now")
    var height: CGFloat = 150

    @State private var rawSelection: Double?

    private struct Bar: Identifiable {
        var id: Int
        var value: Double
    }

    var body: some View {
        let bars = values.enumerated().map { Bar(id: $0.offset, value: $0.element) }
        Chart {
            ForEach(bars) { bar in
                RectangleMark(xStart: .value("Cycle", Double(bar.id) + 0.08),
                              xEnd: .value("Cycle", Double(bar.id) + 0.92),
                              yStart: .value("Yield", 0),
                              yEnd: .value("Yield", bar.value))
                    .foregroundStyle(fill(bar.id))
                    .clipShape(UnevenRoundedRectangle(topLeadingRadius: 1, topTrailingRadius: 1))
            }
            if nowPosition < Double(values.count) {
                RuleMark(x: .value("Now", nowPosition))
                    .foregroundStyle(Color.hudInk)
                    .lineStyle(StrokeStyle(lineWidth: 1))
                    .annotation(position: .top, alignment: .leading, spacing: 0) {
                        nowLabel
                            .font(HUDFont.mono(9, weight: .medium, relativeTo: .caption2))
                            .tracking(1)
                            .textCase(.uppercase)
                            .foregroundStyle(Color.hudInk)
                            .padding(.leading, 4)
                    }
            }
        }
        .chartXScale(domain: 0...Double(max(values.count, 1)))
        .chartXAxis(.hidden)
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
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
        .chartXSelection(value: $rawSelection)
        .onChange(of: rawSelection) { _, value in
            guard let value, !values.isEmpty else { return }
            selection = min(max(Int(value.rounded(.down)), 0), values.count - 1)
        }
        .frame(height: height)
    }

    private func fill(_ index: Int) -> Color {
        if index == selection { return .hudInk }
        let current = Int(nowPosition.rounded(.down))
        if index < current { return color }
        if index == current { return color.opacity(0.6) }
        return color.opacity(0.28)
    }
}

#Preview("Cycle bar chart") {
    @Previewable @State var selection: Int? = 26
    let values = (0..<60).map { 14_000 * exp(-Double($0) / 25) + 1_500 }
    HUDList {
        Section {
            HUDPanel {
                HUDCycleBarChart(values: values, nowPosition: 27.75, selection: $selection)
                    .padding(HUDMetrics.gutter)
            }
            .hudBareRow()
        }
    }
}
