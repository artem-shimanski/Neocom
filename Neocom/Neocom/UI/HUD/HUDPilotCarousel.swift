import SwiftUI

/// The signed-in characters as a row of `HUDPilotPresetCard`s, one of which may be chosen.
///
/// With a few pilots the cards share the width equally; with more they narrow to the same width,
/// down to the widest card's ideal width, then the row scrolls. `ViewThatFits` picks between the
/// equal row and the scrolling one, both built on `HUDEqualWidthRow`.
struct HUDPilotCarousel: View {
    struct Entry: Identifiable {
        let account: Account
        /// The mono line under the name: what tapping the card does.
        let caption: Text
        let isSelected: Bool
        /// `false` for a pilot whose data has not arrived or who has nothing to copy.
        var isEnabled = true

        var id: Int64 { account.id }
    }

    let entries: [Entry]
    let onSelect: (Account) -> Void

    private let spacing: CGFloat = 6

    var body: some View {
        ViewThatFits(in: .horizontal) {
            row
            ScrollView(.horizontal) {
                row
            }
            .scrollIndicators(.hidden)
            // The cards' rims are drawn at their edges; the scroll view's clip would shave them.
            .scrollClipDisabled()
        }
    }

    private var row: some View {
        HUDEqualWidthRow(spacing: spacing) {
            ForEach(entries) { entry in
                HUDPilotPresetCard(account: entry.account,
                                   caption: entry.caption,
                                   isSelected: entry.isSelected) {
                    onSelect(entry.account)
                }
                .disabled(!entry.isEnabled)
                .opacity(entry.isEnabled ? 1 : 0.5)
            }
        }
    }
}

/// Lays its subviews out in a row, all the same width.
///
/// Offered a width, it splits it equally less the gaps. Offered none (`ViewThatFits`, a
/// horizontal `ScrollView`), every subview gets the widest one's ideal width. The height is the
/// tallest subview's.
struct HUDEqualWidthRow: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard !subviews.isEmpty else { return .zero }
        let width = cellWidth(proposal: proposal, subviews: subviews)
        let height = subviews
            .map { $0.sizeThatFits(ProposedViewSize(width: width, height: proposal.height)).height }
            .max() ?? 0
        return CGSize(width: width * CGFloat(subviews.count) + gaps(subviews), height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard !subviews.isEmpty else { return }
        let width = cellWidth(proposal: ProposedViewSize(width: bounds.width, height: bounds.height),
                              subviews: subviews)
        var x = bounds.minX
        for subview in subviews {
            subview.place(at: CGPoint(x: x, y: bounds.minY),
                          anchor: .topLeading,
                          proposal: ProposedViewSize(width: width, height: bounds.height))
            x += width + spacing
        }
    }

    private func gaps(_ subviews: Subviews) -> CGFloat {
        spacing * CGFloat(subviews.count - 1)
    }

    private func cellWidth(proposal: ProposedViewSize, subviews: Subviews) -> CGFloat {
        if let width = proposal.width, width.isFinite {
            return max(0, (width - gaps(subviews)) / CGFloat(subviews.count))
        }
        return subviews.map { $0.sizeThatFits(.unspecified).width }.max() ?? 0
    }
}
