import SwiftUI

/// An opaque block on `surface` with a 1 pt border, for content that is one piece rather than a
/// card of rows: the pilot card, the setup hint, the skill in training, the fit's resources
/// header, the load warnings, a description. In a `HUDList` it is the one row of a plain
/// `Section`, marked `hudBareRow()`; a card of rows is a `HUDListSection` instead.
struct HUDPanel<Content: View>: View {
    var tone: HUDTone = .normal
    @ViewBuilder var content: Content

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: HUDMetrics.panelRadius, style: .continuous)
        VStack(alignment: .leading, spacing: 0) {
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.hudSurface, in: shape)
        .clipShape(shape)
        .overlay {
            shape.strokeBorder(tone.border, lineWidth: 1)
        }
    }
}

#Preview("Panel") {
    HUDList {
        Section {
            HUDPanel {
                HUDPanelHeader(title: Text("Slot 01"))
                Text(verbatim: "One block of content under its strip.")
                    .padding(HUDMetrics.gutter)
            }
            .hudBareRow()
        }
    }
}
