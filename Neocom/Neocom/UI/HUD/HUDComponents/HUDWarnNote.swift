import SwiftUI

/// The note strip a warn panel can end with: what went wrong and what to do about it, in
/// `warn-note-ink` on `warn-note-bg`, under a full-width rule. It goes last inside a
/// `HUDPanel(tone: .warn)` — the paused training queue, a colony that is about to lose output.
struct HUDWarnNote: View {
    let text: Text
    /// The strip is `warn` by default; a note that states something else — a job that is ready,
    /// one the server rolled back — sets its own ink and wash.
    var ink: Color = .hudWarnNoteInk
    var background: Color = .hudWarnNoteBg

    init(_ text: Text) { self.text = text }
    init(_ text: LocalizedStringKey) { self.text = Text(text) }
    init(verbatim text: String) { self.text = Text(verbatim: text) }

    func colors(ink: Color, background: Color) -> Self {
        var copy = self
        copy.ink = ink
        copy.background = background
        return copy
    }

    var body: some View {
        text
            .font(HUDFont.mono(11, weight: .regular, relativeTo: .caption))
            .lineSpacing(3)
            .foregroundStyle(ink)
            .multilineTextAlignment(.leading)
            .padding(.horizontal, HUDMetrics.gutter)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(background)
            .overlay(alignment: .top) { HUDPanelRule() }
    }
}

#Preview("Warn note") {
    HUDList {
        Section {
            HUDPanel(tone: .warn) {
                Text(verbatim: "Launchpad full").font(.hudBody).padding(HUDMetrics.gutter)
                HUDWarnNote(verbatim: "After 2026.10.18 05:50 new output has nowhere to go and is lost. Empty the Launchpad in game.")
            }
            .hudBareRow()
        }
    }
}
