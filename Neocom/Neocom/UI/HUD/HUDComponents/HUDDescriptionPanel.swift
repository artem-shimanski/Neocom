import SwiftUI

/// A titled group of bonus lines under a description: a ship's traits.
struct HUDTraitSection: Identifiable {
    struct Line: Identifiable {
        var id: String
        var figure: String?
        var text: AttributedString
    }

    var id: String
    var title: Text
    var lines: [Line]
}

/// A panel of running text: an item's or a certificate's description, optionally followed by
/// titled bonus lines.
struct HUDDescriptionPanel: View {
    let text: AttributedString?
    var traits: [HUDTraitSection] = []

    private let font = HUDFont.display(15, weight: .regular, relativeTo: .body)

    var body: some View {
        HUDPanel {
            VStack(alignment: .leading, spacing: 14) {
                if let text {
                    Text(text)
                        .font(font)
                        .foregroundStyle(Color.hudInkBodyMuted)
                }
                ForEach(traits) { section in
                    VStack(alignment: .leading, spacing: 6) {
                        section.title
                            .font(HUDFont.display(15, weight: .semibold, relativeTo: .body))
                            .foregroundStyle(Color.hudInkBodyMuted)
                        ForEach(section.lines) { line in
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                if let figure = line.figure {
                                    Text(verbatim: figure)
                                        .font(HUDFont.mono(14, weight: .semibold, relativeTo: .body))
                                        .foregroundStyle(Color.hudAccent)
                                }
                                Text(line.text)
                                    .font(font)
                                    .foregroundStyle(Color.hudInkBodyMuted)
                            }
                        }
                    }
                }
            }
            .lineSpacing(4)
            .padding(.horizontal, HUDMetrics.gutter)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            // A long panel can be offered less than its height as a List row; the text would then
            // truncate instead of the row growing.
            .fixedSize(horizontal: false, vertical: true)
            .textSelection(.enabled)
        }
    }
}

#Preview("Description panel") {
    HUDList {
        Section {
            HUDDescriptionPanel(text: AttributedString(
                "A heavy electron blaster that fires a single high-damage shot at long range. Its capacitor makes it slow to fire, but each hit lands hard."))
                .hudBareRow()
        }
    }
}
