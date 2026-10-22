import SwiftUI

/// Swipe-left-to-remove for a row using `.swipeActions`, with the same action in a context menu
/// (`hudRowActions`) so it is reachable with a mouse.
///
/// The remove action is the system's destructive swipe button; the system keeps one row open at
/// a time. `allowsFullSwipe` is off by default, so the swipe only reveals the button.
struct HUDSwipeRow<Content: View>: View {
    /// The button's label: "Remove" for a row taken out of something, "Delete" for a record.
    var title: LocalizedStringKey = "Remove"
    /// Immediate and final; callers that need confirmation ask in their own handler.
    var onRemove: () -> Void
    /// False when the row's own `.contextMenu` already carries the same action.
    var inContextMenu = true
    var allowsFullSwipe = false
    @ViewBuilder var content: Content

    var body: some View {
        content
            .hudRowActions(inContextMenu: inContextMenu, allowsFullSwipe: allowsFullSwipe) {
                Button(role: .destructive) {
                    onRemove()
                } label: {
                    Label(title, systemImage: "trash")
                }
            }
    }
}

#Preview {
    HUDSwipeRowPreview()
}

/// Rows wrapped inside a `HUDList`, the container the swipe has to work in.
///
/// Uses the data form of `HUDListSection`: in a preview, views whose bodies are compiled in the
/// previewed file come back from `Group(subviews:)` empty inside a `ForEach`.
private struct HUDSwipeRowPreview: View {
    @State private var modules = [0, 1, 2]

    var body: some View {
        HUDList {
            HUDListSection(modules, id: \.self, row: { row in
                HUDSwipeRow(onRemove: { modules.removeAll { $0 == row } }) {
                    moduleRow(row)
                }
            }, header: {
                HUDSectionHeader("Modules")
            }, footer: {
                HUDFootnote("Swipe a row left to reveal Remove; the tap on it is what removes.")
            })
        }
    }

    private func moduleRow(_ row: Int) -> some View {
        HStack(spacing: 12) {
            Button {} label: {
                Image(systemName: "bolt.fill")
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.hudRow)
            Button {} label: {
                HStack(spacing: 12) {
                    HUDRowTitle(title: Text(verbatim: "Heavy Electron Blaster II"),
                                subtitle: Text(verbatim: "Antimatter Charge M"))
                    Spacer(minLength: 4)
                    HUDChevron()
                }
                .frame(minHeight: 56)
                .contentShape(Rectangle())
            }
            .buttonStyle(.hudRow)
        }
        .hudRow(HUDRowStyle(minHeight: 56, verticalPadding: 0))
    }
}
