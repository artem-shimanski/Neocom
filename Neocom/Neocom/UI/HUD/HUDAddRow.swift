import SwiftUI

/// The last row of a card of added items: a plus and the verb, `Add Module`, `Add Drone`.
/// The row is the button, with no circle around the plus.
///
/// The plus sits in a 32 pt column, the width module rows give their state control.
struct HUDAddRow: View {
    let title: LocalizedStringKey
    /// What is left to add into, in mono capitals at the trailing edge (`3 FREE`); `nil` for
    /// no ceiling.
    var caption: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: "plus")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(width: 32)
                    .accessibilityHidden(true)
                Text(title)
                    .font(.hudBody)
                Spacer(minLength: 8)
                if let caption {
                    Text(verbatim: caption)
                        .font(HUDFont.mono(11, weight: .regular, relativeTo: .caption))
                        .tracking(1)
                        .foregroundStyle(Color.hudInkMuted)
                }
            }
            .foregroundStyle(Color.hudAccent)
            .padding(.leading, 12)
            .padding(.trailing, HUDMetrics.gutter)
            .hudRow(Self.rowStyle)
        }
        .hudRowButton(Self.rowStyle)
    }

    /// Indented 12 pt on the leading side so the plus stands in the module rows' state column.
    private static let rowStyle = HUDRowStyle(horizontalPadding: 0, minHeight: 50, verticalPadding: 0)
}
