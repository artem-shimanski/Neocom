import SwiftUI

/// A row's title, optionally with a mono subtitle under it.
struct HUDRowTitle: View {
    let title: Text
    var subtitle: Text?
    var font: Font = .hudBody
    /// `.uppercase` for a caption (a charge name). A subtitle that is a figure with a unit —
    /// `50 m³ · 50 Mbit/s` — passes `nil`: upper-casing a unit changes what it says (`M³` is
    /// not a cubic metre, `MBIT/S` is not a megabit).
    var subtitleCase: Text.Case? = .uppercase

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            title
                .font(font)
                .foregroundStyle(Color.hudInk)
            if let subtitle {
                subtitle
                    .font(HUDFont.mono(11, weight: .regular, relativeTo: .caption))
                    .textCase(subtitleCase)
                    .foregroundStyle(Color.hudInkMuted)
            }
        }
        .multilineTextAlignment(.leading)
    }
}

#Preview("Row title") {
    HUDList {
        HUDListSection {
            HUDRowTitle(title: Text(verbatim: "Rifter"))
                .hudRow(HUDRowStyle(minHeight: 0, verticalPadding: 10))
            HUDRowTitle(title: Text(verbatim: "Heavy Electron Blaster II"),
                        subtitle: Text(verbatim: "High Slot · Active"))
                .hudRow(HUDRowStyle(minHeight: 0, verticalPadding: 10))
            HUDRowTitle(title: Text(verbatim: "Cargo Hold"),
                        subtitle: Text(verbatim: "50 m³ · 50 Mbit/s"),
                        subtitleCase: nil)
                .hudRow(HUDRowStyle(minHeight: 0, verticalPadding: 10))
        }
    }
}
