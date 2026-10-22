import SwiftUI

/// One entry of a forecast or a schedule: when it happens on the left — `in 2d 16h` over
/// `10.20 08:20`, or a word for a span (`to end`, `idle`) — and what happens on the right, a
/// title and the sentence that explains it.
///
/// Content only, like `HUDRowTitle`: in a `HUDList` card the caller puts `hudRow` on it (and,
/// for an entry that leads somewhere, wraps it in a link with `hudRowButton`); inside a panel it
/// takes its own padding.
///
/// The time takes its colour from the caller and nothing else does: `warn` for what needs
/// attention, `ok` for an all-clear, `ink-muted` for a plain fact.
struct HUDEventRow: View {
    let when: Text
    /// A second line under `when`, in `micro`: the absolute moment of a relative time.
    var whenDetail: Text?
    var whenColor: Color = .hudInkMuted
    let title: Text
    var detail: Text?
    /// Width of the time column. Wide enough for `in 21h 50m` at 12 pt.
    var whenWidth: CGFloat = 64
    var titleFont: Font = HUDFont.display(15, weight: .semibold, relativeTo: .body)
    var showsChevron = false

    var body: some View {
        HStack(alignment: showsChevron ? .center : .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                when
                    .font(HUDFont.mono(12, weight: .regular, relativeTo: .caption))
                    .foregroundStyle(whenColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if let whenDetail {
                    whenDetail
                        .font(.hudMicro)
                        .foregroundStyle(Color.hudInkMuted)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
            .frame(width: whenWidth, alignment: .leading)
            VStack(alignment: .leading, spacing: 3) {
                title
                    .font(titleFont)
                    .foregroundStyle(Color.hudInk)
                if let detail {
                    detail
                        .font(HUDFont.mono(11, weight: .regular, relativeTo: .caption))
                        .lineSpacing(3)
                        .foregroundStyle(Color.hudInkMuted)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .multilineTextAlignment(.leading)
            if showsChevron {
                HUDChevron()
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
    }
}

#Preview("Event row") {
    let style = HUDRowStyle(minHeight: 0, verticalPadding: 12)
    NavigationStack {
        HUDList {
            HUDListSection("Forecast") {
                HUDEventRow(when: Text(verbatim: "in 2d 16h"), whenDetail: Text(verbatim: "10.20 08:20"),
                            whenColor: .hudWarn, title: Text(verbatim: "Extractors finish"),
                            detail: Text(verbatim: "All 3 programs end together. Restart them in game before then."))
                    .hudRow(style)
                NavigationLink {
                    Text(verbatim: "Chain")
                } label: {
                    HUDEventRow(when: Text(verbatim: "to end"), whenColor: .hudWarn,
                                title: Text(verbatim: "Biocells wait for Precious Metals"),
                                detail: Text(verbatim: "The Biocells factory is starved 64% of the remaining time."),
                                showsChevron: true)
                        .hudRow(style)
                }
                .hudRowButton(style)
                HUDEventRow(when: Text(verbatim: "to end"), whenColor: .hudOk, title: Text(verbatim: "Nothing wasted"),
                            detail: Text(verbatim: "Every storage stays under 15% until program end."))
                    .hudRow(style)
            }
        }
    }
}
