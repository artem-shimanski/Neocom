import SwiftUI

/// Three to four key figures side by side, divided by `line`.
///
/// A figure can carry a mono unit after it (`14.1 K`, `41% STABLE`), and the strip can end in a
/// chevron when the whole of it leads somewhere. Both are off by default.
struct HUDStatStrip: View {
    struct Item: Identifiable {
        var id: Int
        var label: Text
        var value: Text
        var color: Color = .hudInk
        /// Set after the value in `micro` mono, `ink-muted` whatever the value's colour is: the
        /// unit is a caption of the figure, not a second statement about it.
        var unit: Text?
        /// A control that stands where the label would, instead of it (the stats screen's
        /// `HP | EHP` switch). The label is not drawn then; the control carries its own name.
        var control: AnyView?
    }

    /// Where a unit goes.
    enum UnitPlacement {
        /// After the figure, on its line. For a unit of a word or two (`K`, `STABLE`).
        case inline
        /// Under the figure, on a line of its own. For a unit that is itself a figure
        /// (`VOLLEY 1 214`), which beside a large value leaves neither of them room.
        case below
    }

    let items: [Item]
    var valueFont: Font = .hudFigure
    var showsChevron = false
    /// `.uppercase` for a unit that is a word (`STABLE`); `nil` for one whose case is part of
    /// what it says (`m³`, `Mbit/s`).
    var unitCase: Text.Case? = .uppercase
    var unitPlacement: UnitPlacement = .inline

    var body: some View {
        HStack(spacing: 0) {
            ForEach(items) { item in
                if item.id != items.first?.id {
                    Rectangle().fill(Color.hudLine).frame(width: 1)
                }
                VStack(alignment: .leading, spacing: 3) {
                    if let control = item.control {
                        control
                    } else {
                        item.label
                            .font(.hudMicro)
                            .tracking(1.5)
                            .textCase(.uppercase)
                            .foregroundStyle(Color.hudInkMuted)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    switch unitPlacement {
                    case .inline:
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            value(of: item)
                            unitText(of: item)?.layoutPriority(1)
                        }
                    case .below:
                        value(of: item)
                        unitText(of: item)
                    }
                }
                // 16 in from the leading rule, nothing on the trailing side: the next rule is the cell's
                // edge, and a figure too long for the cell scales.
                .padding(.leading, 16)
                .padding(.vertical, 11)
                .frame(maxWidth: .infinity, alignment: .leading)
                // Combined into one spoken line, unless the cell holds a control: its
                // buttons must stay buttons of their own, not words in somebody's sentence.
                .accessibilityElement(children: item.control == nil ? .combine : .contain)
            }
            if showsChevron {
                HUDChevron()
                    .padding(.horizontal, 14)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func value(of item: Item) -> some View {
        item.value
            .font(valueFont)
            .foregroundStyle(item.color)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
    }

    private func unitText(of item: Item) -> (some View)? {
        item.unit.map { unit in
            unit
                .font(.hudMicro)
                .textCase(unitCase)
                .foregroundStyle(Color.hudInkMuted)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }
}

#Preview("Stat strip") {
    HUDList {
        Section {
            HUDPanel {
                HUDStatStrip(items: [
                    .init(id: 0, label: Text("DPS"), value: Text(verbatim: "612.4")),
                    .init(id: 1, label: Text("EHP"), value: Text(verbatim: "14.1"), unit: Text(verbatim: "K")),
                    .init(id: 2, label: Text("Cap"), value: Text(verbatim: "41%"), color: .hudOk,
                          unit: Text(verbatim: "Stable")),
                ], showsChevron: true)
            }
            .hudBareRow()
        }
        Section {
            HUDPanel {
                HUDStatStrip(items: [
                    .init(id: 0, label: Text("DPS"), value: Text(verbatim: "1 234.5")),
                    .init(id: 1, label: Text("EHP"), value: Text(verbatim: "250 000")),
                    .init(id: 2, label: Text("Cap"), value: Text(verbatim: "1:48"), color: .hudWarn,
                          unit: Text(verbatim: "Lasts")),
                ], showsChevron: true)
            }
            .hudBareRow()
        }
        Section {
            HUDPanel {
                HUDStatStrip(items: [
                    .init(id: 0, label: Text("Skill Points"), value: Text(verbatim: "52 100 000")),
                    .init(id: 1, label: Text("Skills"), value: Text(verbatim: "412")),
                ])
            }
            .hudBareRow()
        }
    }
}
