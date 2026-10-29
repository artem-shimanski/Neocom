import SwiftUI

/// "Load Older": the row at the end of a paged list that asks for the next page — an accent
/// arrow (a spinner while loading), the title, and the paging state (`PAGE 2 OF 4`) on the right.
/// Disabled while loading. `systemImage` replaces the arrow for rows that start something else.
/// `detailColor` tints the detail, e.g. a warning when the action failed.
struct HUDLoadMoreRow: View {
    var title: Text = Text("Load Older")
    var detail: Text?
    var detailColor: Color = .hudInkMuted
    var systemImage = "arrow.down"
    let isLoading: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Group {
                    if isLoading {
                        ProgressView()
                    } else {
                        Image(systemName: systemImage)
                            .font(.system(size: 16, weight: .semibold))
                            .accessibilityHidden(true)
                    }
                }
                .foregroundStyle(Color.hudAccent)
                title
                    .font(HUDFont.display(15, weight: .semibold, relativeTo: .body))
                    .foregroundStyle(Color.hudAccent)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let detail {
                    detail
                        .font(.hudLabel)
                        .tracking(1)
                        .textCase(.uppercase)
                        .foregroundStyle(detailColor)
                }
            }
            .hudRow()
        }
        .hudRowButton()
        .disabled(isLoading)
    }
}

#Preview("Load more row") {
    HUDList {
        Section {
            HUDLoadMoreRow(detail: Text(verbatim: "Page 2 of 4"), isLoading: false) {}
        }
        Section {
            HUDLoadMoreRow(detail: Text(verbatim: "Page 2"), isLoading: true) {}
        }
    }
}
