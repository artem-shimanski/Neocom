import SwiftUI

/// A small mark and a count after it in mono: how many of a list's items are in one state — the
/// skills of a group at V, queued, in the plan.
///
/// The mark says the state on its own (a `HUDSkillStateIcon`, a `HUDLevelSwatch`, a bookmark),
/// so the chip has no label; `accessibilityLabel` speaks for both.
struct HUDCountChip<Mark: View>: View {
    let count: Int
    let accessibilityLabel: Text
    @ViewBuilder var mark: Mark

    var body: some View {
        HStack(spacing: 4) {
            mark
            Text(count, format: .number)
                .font(.hudLabel)
                .foregroundStyle(Color.hudInkBodyMuted)
                .lineLimit(1)
        }
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(count) \(accessibilityLabel)"))
    }
}

#Preview("Count chip") {
    HUDList {
        HUDListSection {
            HStack(spacing: 10) {
                Text(verbatim: "21 / 32 · 15.89M SP")
                    .font(.hudLabel)
                    .foregroundStyle(Color.hudInkMuted)
                Spacer()
                HUDCountChip(count: 18, accessibilityLabel: Text(verbatim: "trained to V")) {
                    HUDSkillStateIcon(state: .trainedToV, size: 14)
                }
                HUDCountChip(count: 1, accessibilityLabel: Text(verbatim: "in the game queue")) {
                    HUDLevelSwatch(segment: .paused, width: 10)
                }
                HUDCountChip(count: 5, accessibilityLabel: Text(verbatim: "in the training plan")) {
                    Image(systemName: "bookmark.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.hudAccent)
                }
            }
            .hudRow(HUDRowStyle(minHeight: 0, verticalPadding: 12))
        }
    }
}
