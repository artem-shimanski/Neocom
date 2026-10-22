import SwiftUI

/// One row of a card of exclusive choices: a title, an optional mono line, and an accent
/// checkmark on the chosen one. The whole row is the button.
///
/// A choice that leads somewhere is `HUDLinkRowLabel`; an item picked from types is `PickerTypeRow`.
struct HUDChoiceRow: View {
    let title: Text
    var subtitle: Text?
    let isOn: Bool
    let action: () -> Void

    private static let style = HUDRowStyle(minHeight: 50, verticalPadding: 7)

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    title
                        .font(.hudBody)
                        .foregroundStyle(Color.hudInk)
                    if let subtitle {
                        subtitle
                            .font(HUDFont.mono(11, weight: .regular, relativeTo: .caption))
                            .foregroundStyle(Color.hudInkMuted)
                            .lineLimit(1)
                    }
                }
                .multilineTextAlignment(.leading)
                Spacer(minLength: 8)
                if isOn {
                    Image(systemName: "checkmark")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Color.hudAccent)
                        .accessibilityHidden(true)
                }
            }
            .hudRow(Self.style)
        }
        .hudRowButton(Self.style)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

#Preview("Choice row") {
    HUDList {
        HUDListSection {
            HUDChoiceRow(title: Text(verbatim: "None"), isOn: false) {}
            HUDChoiceRow(title: Text(verbatim: "Pulsar"),
                         subtitle: Text(verbatim: "Shield Hitpoint Bonus, Signature Penalty"),
                         isOn: true) {}
            HUDChoiceRow(title: Text(verbatim: "Wolf Rayet"), isOn: false) {}
        }
    }
}
