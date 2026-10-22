import SwiftUI

/// A figure the fit has changed: the base value small and struck through, then the new one in
/// the accent. For the value slot of a `HUDReadoutRow`.
///
/// VoiceOver reads it as one value with the old one named.
struct HUDChangedValue: View {
    let value: String
    let base: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(verbatim: base)
                .font(HUDFont.mono(11, weight: .regular, relativeTo: .caption))
                .strikethrough()
                .foregroundStyle(Color.hudInkFaint)
            Text(verbatim: value)
                .foregroundStyle(Color.hudAccent)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(value), base \(base)"))
    }
}

#Preview {
    HUDList {
        HUDListSection {
            HUDReadoutRow(Text("Rate of Fire")) {
                HUDChangedValue(value: "2.25 s", base: "3.00 s")
            }
            HUDReadoutRow(Text("Optimal Range"), value: "2.40 km")
        }
    }
}
