import SwiftUI

/// The key under a HUD chart: a swatch and an uppercase mono caption per series, in a line.
///
/// The swatch says how the series is drawn — a filled block for bars, a line or a dashed line for
/// a curve, the `warn` hatch for a span that waits — so the chart and its key read alike. A
/// caption can take a colour of its own when it is itself a statement (`NOT FULL BEFORE END` in
/// `ok`); otherwise it is `ink-muted`.
struct HUDChartLegend: View {
    enum Swatch {
        case block(Color)
        case line(Color)
        case dashedLine(Color)
        case hatch
        /// No swatch: the caption alone, a verdict rather than a series.
        case none
    }

    struct Item: Identifiable {
        var id: Int
        var swatch: Swatch
        var text: Text
        var color: Color = .hudInkMuted
    }

    let items: [Item]

    var body: some View {
        HStack(spacing: 14) {
            ForEach(items) { item in
                HStack(spacing: 6) {
                    swatch(item.swatch)
                    item.text
                        .foregroundStyle(item.color)
                        .lineLimit(1)
                }
            }
        }
        .font(.hudMicro)
        .tracking(1)
        .textCase(.uppercase)
        .minimumScaleFactor(0.75)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func swatch(_ swatch: Swatch) -> some View {
        switch swatch {
        case let .block(color):
            RoundedRectangle(cornerRadius: 1).fill(color).frame(width: 8, height: 8)
        case let .line(color):
            Rectangle().fill(color).frame(width: 12, height: 2)
        case let .dashedLine(color):
            DashedLine()
                .stroke(color, style: StrokeStyle(lineWidth: 2, dash: [3, 2]))
                .frame(width: 12, height: 2)
        case .hatch:
            HUDHatch()
                .frame(width: 8, height: 8)
                .clipShape(RoundedRectangle(cornerRadius: 1))
        case .none:
            EmptyView()
        }
    }

    nonisolated private struct DashedLine: Shape {
        func path(in rect: CGRect) -> Path {
            Path { path in
                path.move(to: CGPoint(x: rect.minX, y: rect.midY))
                path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
            }
        }
    }
}

#Preview("Chart legend") {
    HUDList {
        Section {
            HUDPanel {
                VStack(alignment: .leading, spacing: 12) {
                    HUDChartLegend(items: [
                        .init(id: 0, swatch: .block(.hudAccent), text: Text(verbatim: "Extracted")),
                        .init(id: 1, swatch: .block(.hudAccent.opacity(0.28)), text: Text(verbatim: "Forecast")),
                        .init(id: 2, swatch: .block(.hudInk), text: Text(verbatim: "Selected")),
                    ])
                    HUDChartLegend(items: [
                        .init(id: 0, swatch: .line(.hudAccent), text: Text(verbatim: "Simulated")),
                        .init(id: 1, swatch: .dashedLine(.hudAccent), text: Text(verbatim: "Forecast")),
                        .init(id: 2, swatch: .none, text: Text(verbatim: "Not full before end"), color: .hudOk),
                    ])
                    HUDChartLegend(items: [
                        .init(id: 0, swatch: .block(.hudAccent), text: Text(verbatim: "Running 36%")),
                        .init(id: 1, swatch: .hatch, text: Text(verbatim: "Waiting for input 64%")),
                    ])
                }
                .padding(HUDMetrics.gutter)
            }
            .hudBareRow()
        }
    }
}
