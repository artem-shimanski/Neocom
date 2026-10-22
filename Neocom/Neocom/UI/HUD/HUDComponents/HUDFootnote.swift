import SwiftUI

/// A footnote under a panel: what a gesture does, or how fresh the data is.
struct HUDFootnote: View {
    let text: Text
    /// `ink-muted`; `warn-note-ink` for a note that says what to do about a problem.
    var color: Color = .hudInkMuted
    /// `.leading` under a card; `.center` for a closing line under a centred block.
    var alignment: HorizontalAlignment = .leading

    init(_ text: Text, color: Color = .hudInkMuted, alignment: HorizontalAlignment = .leading) {
        self.text = text
        self.color = color
        self.alignment = alignment
    }

    init(_ text: LocalizedStringKey, alignment: HorizontalAlignment = .leading) {
        self.text = Text(text)
        self.alignment = alignment
    }

    var body: some View {
        text
            .font(HUDFont.mono(11, weight: .regular, relativeTo: .caption))
            .lineSpacing(3)
            .foregroundStyle(color)
            .multilineTextAlignment(alignment == .center ? .center : .leading)
            .padding(.horizontal, HUDMetrics.headerFaceInset)
            .frame(maxWidth: .infinity, alignment: Alignment(horizontal: alignment, vertical: .center))
    }
}

#Preview("Footnote") {
    HUDList {
        Section {
            Text(verbatim: "12 400 ISK").hudRow()
        } header: {
            HUDSectionHeader("Wallet").hudListHeader()
        } footer: {
            HUDFootnote("Updated a minute ago.").hudListFooter()
        }
    }
}
