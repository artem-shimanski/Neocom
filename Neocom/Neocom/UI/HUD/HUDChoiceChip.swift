import SwiftUI

/// One of a set of named choices as a 32 pt outlined capsule. The chosen one has accent ink,
/// an accent wash and a check mark; the others carry no mark.
///
/// Wrap several in a `HUDWrapLayout`. A chip that is a value, not a choice, is `HUDTokenChip`.
struct HUDChoiceChip: View {
    let title: Text
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                title
                    .font(HUDFont.mono(11, weight: .regular, relativeTo: .caption))
                    .tracking(0.5)
                    .lineLimit(1)
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .accessibilityHidden(true)
                }
            }
            .foregroundStyle(isSelected ? Color.hudAccent : Color.hudInkBodyMuted)
            .padding(.horizontal, 12)
            .frame(height: 32)
            .background(isSelected ? Color.hudAccent.opacity(0.10) : Color.clear, in: Capsule())
            .overlay {
                Capsule().strokeBorder(isSelected ? Color.hudAccent.opacity(0.4) : Color.hudLineLeader,
                                       lineWidth: 1)
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

#Preview("Choice chip") {
    HUDWrapLayout(spacing: 6) {
        HUDChoiceChip(title: Text(verbatim: "Uniform"), isSelected: false) {}
        HUDChoiceChip(title: Text(verbatim: "EM"), isSelected: false) {}
        HUDChoiceChip(title: Text(verbatim: "Thermal"), isSelected: false) {}
        HUDChoiceChip(title: Text(verbatim: "≈ Guristas"), isSelected: true) {}
        HUDChoiceChip(title: Text(verbatim: "≈ Serpentis"), isSelected: false) {}
    }
    .padding(HUDMetrics.gutter)
    .background(Color.hudBg)
}
