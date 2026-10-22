import SwiftUI

/// A tile that is one of a set of choices: icon on top (and a check mark when chosen), the name
/// and a mono value at the bottom. Chosen, its border turns `accent` and doubles.
///
/// The label of a `Button` (`.buttonStyle(.hudTile)`) or of a `Menu`; a menu tile passes
/// `showsMenuIndicator`. While `isPlaceholder`, the name is redacted and the tile dimmed.
/// `isCompact` is for three tiles across a phone: tighter padding, a smaller value line, and a
/// name that shrinks before it truncates.
struct HUDChoiceTile: View {
    let systemImage: String
    let title: Text
    let value: Text
    var isSelected = false
    var isPlaceholder = false
    var showsMenuIndicator = false
    var isCompact = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: HUDMetrics.tileRadius, style: .continuous)
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                Image(systemName: systemImage)
                    .font(.title3)
                    .foregroundStyle(Color.hudAccent)
                    .accessibilityHidden(true)
                Spacer(minLength: 4)
                if isSelected {
                    HUDCheckCircle(isOn: true)
                }
            }
            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    title
                        .font(.hudTileTitle)
                        .tracking(0.3)
                        .foregroundStyle(Color.hudInk)
                        .lineLimit(1)
                        .minimumScaleFactor(isCompact ? 0.75 : 1)
                        .redacted(reason: isPlaceholder ? .placeholder : [])
                    if showsMenuIndicator {
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Color.hudInkMuted)
                            .accessibilityHidden(true)
                    }
                }
                value
                    .font(HUDFont.mono(isCompact ? 11 : 13, weight: .semibold, relativeTo: .subheadline))
                    .textCase(isPlaceholder ? .uppercase : nil)
                    .foregroundStyle(isPlaceholder ? Color.hudInkMuted : isSelected ? Color.hudAccent : Color.hudInk)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .padding(isCompact ? 12 : 14)
        .frame(maxWidth: .infinity, minHeight: 104, alignment: .leading)
        .background(Color.hudSurface, in: shape)
        .overlay {
            shape.strokeBorder(isSelected ? Color.hudAccent : Color.hudLine, lineWidth: isSelected ? 2 : 1)
        }
        .opacity(isPlaceholder ? 0.6 : 1)
        .contentShape(shape)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

#Preview("Choice tile") {
    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: HUDMetrics.headerSpacing) {
        HUDChoiceTile(systemImage: "cup.and.saucer", title: Text(verbatim: "Coffee"), value: Text(verbatim: "$1.99"))
        HUDChoiceTile(systemImage: "bag", title: Text(verbatim: "Lunch"), value: Text(verbatim: "$4.99"), isSelected: true)
        HUDChoiceTile(systemImage: "fork.knife", title: Text(verbatim: "Dinner"), value: Text(verbatim: "LOADING…"),
                      isPlaceholder: true)
        HUDChoiceTile(systemImage: "gift", title: Text(verbatim: "More"), value: Text(verbatim: "from $19.99"),
                      showsMenuIndicator: true)
    }
    .padding(.horizontal, HUDMetrics.gutter)
    .frame(maxHeight: .infinity)
    .background(Color.hudBg.ignoresSafeArea())
}
