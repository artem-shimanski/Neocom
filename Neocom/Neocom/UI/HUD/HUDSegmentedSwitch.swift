import SwiftUI

/// A small pill of mutually exclusive readings: a 22 pt capsule with a hairline border, the
/// chosen segment washed in `accent`.
///
/// The one place the content layer redraws a system control, because a system
/// `Picker(.segmented)` is 32 pt of chrome and does not fit a summary cell's caption slot.
///
/// The pair is an accessibility group with the caller's label, and each segment says whether it
/// is selected. A segment is 16 pt tall as drawn, with a taller touch target
/// (`HUDSegmentedSwitchSegment`).
struct HUDSegmentedSwitch<Value: Hashable>: View {
    struct Option: Identifiable {
        var value: Value
        /// Written as is (`HP`, `EHP`): not localised and not re-cased.
        var title: String

        var id: Value { value }
    }

    let options: [Option]
    @Binding var selection: Value
    /// What the pair is, for VoiceOver ("Hit points"). Not drawn.
    let label: LocalizedStringKey

    var body: some View {
        HStack(spacing: 1) {
            ForEach(options) { option in
                HUDSegmentedSwitchSegment(title: option.title, isSelected: option.value == selection) {
                    selection = option.value
                }
            }
        }
        .padding(2)
        .frame(height: 22)
        .background(Color.hudBg, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.hudLine, lineWidth: 1))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(label)
    }
}

/// One segment of the switch above, outside the generic type because a static stored property
/// cannot live inside one.
private struct HUDSegmentedSwitchSegment: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    /// How far the touch target reaches above and below the drawn segment: 14 pt each side makes
    /// 44 in all. Vertical only, as segments are 1 pt apart.
    private static let reach: CGFloat = 14

    var body: some View {
        Button(action: action) {
            Text(verbatim: title)
                .font(HUDFont.mono(9, weight: .regular, relativeTo: .caption2))
                .tracking(0.5)
                .lineLimit(1)
                .padding(.horizontal, 6)
                .frame(minWidth: 26, minHeight: 16, maxHeight: 16)
                .foregroundStyle(isSelected ? Color.hudAccent : Color.hudInkMuted)
                .background(isSelected ? Color.hudAccent.opacity(0.14) : .clear, in: Capsule())
                .padding(.vertical, Self.reach)
                .contentShape(Rectangle())
                .padding(.vertical, -Self.reach)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

#Preview {
    @Previewable @State var mode = "ehp"
    HUDList {
        HUDListSection {
            HUDSegmentedSwitch(
                options: [.init(value: "hp", title: "HP"), .init(value: "ehp", title: "EHP")],
                selection: $mode, label: "Hit Points")
                .hudRow()
        }
    }
}
