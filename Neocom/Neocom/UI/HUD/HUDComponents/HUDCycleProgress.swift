import SwiftUI

/// A cycle under way: elapsed over its length (`01:30:06 / 02:00:00`), what it ends in on the
/// right (`ENDS 16:20`, `+5 BIOCELLS AT 16:20`), and a bar under both. The elapsed time ticks by
/// the second on its own; nothing else on the screen has to redraw for it.
struct HUDCycleProgress: View {
    let start: Date
    let end: Date
    var trailing: Text?
    var figureFont: Font = HUDFont.mono(13, weight: .regular, relativeTo: .subheadline)
    var color: Color = .hudAccent

    var body: some View {
        TimelineView(.periodic(from: start, by: 1)) { context in
            let total = max(1, end.timeIntervalSince(start))
            let elapsed = min(max(0, context.date.timeIntervalSince(start)), total)
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    let totalText = Text(verbatim: " / \(Self.clock(total))").foregroundStyle(Color.hudInkMuted)
                    Text("\(Text(verbatim: Self.clock(elapsed)))\(totalText)")
                        .font(figureFont)
                        .monospacedDigit()
                    Spacer(minLength: 8)
                    if let trailing {
                        trailing
                            .font(.hudCaption)
                            .textCase(.uppercase)
                            .foregroundStyle(Color.hudInkBodyMuted)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                }
                HUDResourceBar(fraction: elapsed / total, color: color, height: 6)
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// `01:30:06`.
    static func clock(_ interval: TimeInterval) -> String {
        let seconds = Int(max(0, interval))
        return String(format: "%02d:%02d:%02d", seconds / 3600, seconds % 3600 / 60, seconds % 60)
    }
}

#Preview("Cycle progress") {
    let start = Date.now.addingTimeInterval(-5406)
    HUDList {
        Section {
            HUDPanel {
                VStack(spacing: 16) {
                    HUDCycleProgress(start: start, end: start.addingTimeInterval(7200),
                                     trailing: Text(verbatim: "Ends 16:20"),
                                     figureFont: HUDFont.mono(18, weight: .semibold, relativeTo: .headline))
                    HUDCycleProgress(start: start.addingTimeInterval(3600), end: start.addingTimeInterval(7200),
                                     trailing: Text(verbatim: "+5 Biocells at 16:20"))
                }
                .padding(HUDMetrics.gutter)
            }
            .hudBareRow()
        }
    }
}
