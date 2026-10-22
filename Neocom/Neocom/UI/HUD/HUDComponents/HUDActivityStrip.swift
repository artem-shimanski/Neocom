import SwiftUI

/// A span of time cut into running and waiting stretches: running in a solid colour, waiting in
/// the `warn` hatch, on one 12 pt strip — a factory from now to program end. Marks under it name
/// moments along the way (`NOW`, `10.18`, `END`), each at its place on the strip.
struct HUDActivityStrip: View {
    struct Span: Hashable {
        var start: Date
        var end: Date
        var isActive: Bool
    }

    struct Mark {
        var date: Date
        var label: Text
    }

    let spans: [Span]
    let start: Date
    let end: Date
    var marks: [Mark] = []
    var activeColor: Color = .hudAccent
    var height: CGFloat = 12

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            strip
            if !marks.isEmpty {
                markRow
            }
        }
        .accessibilityHidden(true)
    }

    private var total: TimeInterval { max(1, end.timeIntervalSince(start)) }

    private func fraction(_ date: Date) -> Double {
        min(max(date.timeIntervalSince(start) / total, 0), 1)
    }

    private var strip: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Color.hudSurfaceRaised
                ForEach(spans, id: \.self) { span in
                    let from = fraction(span.start), to = fraction(span.end)
                    Group {
                        if span.isActive {
                            activeColor
                        } else {
                            HUDHatch()
                        }
                    }
                    .frame(width: max(0, (to - from) * proxy.size.width))
                    .offset(x: from * proxy.size.width)
                }
            }
        }
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
    }

    /// The labels under the strip: the first flush left, the last flush right, the others from
    /// their moment on; one that would run into the next is left out.
    private var markRow: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            ZStack(alignment: .topLeading) {
                ForEach(marks.indices, id: \.self) { index in
                    let mark = marks[index]
                    let x = fraction(mark.date) * width
                    if index == marks.count - 1 && index > 0 {
                        mark.label
                            .frame(width: width, alignment: .trailing)
                    } else if index == 0 || (x > 30 && x < width - 70) {
                        mark.label
                            .offset(x: index == 0 ? 0 : x)
                    }
                }
            }
        }
        .frame(height: 14)
        .font(.hudMicro)
        .foregroundStyle(Color.hudInkMuted)
        .lineLimit(1)
    }
}

#Preview("Activity strip") {
    let now = Date(timeIntervalSince1970: 1_791_000_000)
    let pattern: [Bool] = [true, false, true, true, false, false, true, false, false, false, true, true, false]
    let spans = pattern.enumerated().map { index, running in
        HUDActivityStrip.Span(start: now.addingTimeInterval(Double(index) * 5 * 3600),
                              end: now.addingTimeInterval(Double(index + 1) * 5 * 3600), isActive: running)
    }
    let end = now.addingTimeInterval(Double(pattern.count) * 5 * 3600)
    return HUDList {
        Section {
            HUDPanel {
                HUDActivityStrip(spans: spans, start: now, end: end, marks: [
                    .init(date: now, label: Text(verbatim: "NOW")),
                    .init(date: now.addingTimeInterval(9 * 3600), label: Text(verbatim: "10.18")),
                    .init(date: now.addingTimeInterval(33 * 3600), label: Text(verbatim: "10.19")),
                    .init(date: end, label: Text(verbatim: "END")),
                ])
                .padding(HUDMetrics.gutter)
            }
            .hudBareRow()
        }
    }
}
