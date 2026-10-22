import SwiftUI

/// The actions at the end of a sheet, one list section per group.
///
/// An empty group draws nothing.
struct HUDActionList: View {
    let groups: [[HUDAction]]

    var body: some View {
        ForEach(Array(groups.filter { !$0.isEmpty }.enumerated()), id: \.offset) { _, group in
            HUDListSection(Array(group.enumerated()), id: \.offset, row: { item in
                HUDActionRow(action: item.element)
            })
        }
    }
}

/// One action as a row: the label, then the glyph at the trailing edge, both in the role's ink.
private struct HUDActionRow: View {
    let action: HUDAction

    var body: some View {
        Button(action: action.action) {
            HStack(spacing: 12) {
                action.title
                    .font(.hudSheetBody)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: action.systemImage)
                    .font(.system(size: 19))
                    .accessibilityHidden(true)
            }
            .foregroundStyle(action.role.ink)
            .hudRow(.sheet)
        }
        .hudRowButton(.sheet)
    }
}
