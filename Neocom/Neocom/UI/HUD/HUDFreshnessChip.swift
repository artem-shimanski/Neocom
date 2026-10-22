import SwiftUI

/// How fresh a list fetched from ESI is: `● UPDATED 6 MINUTES AGO` with a green dot (amber once
/// stale), `● UPDATING` while a fetch runs, or the reason the last one failed.
///
/// Draws at `now`, the clock of the screen it sits on. It must not run a `TimelineView` of its
/// own: one inside a row of another `TimelineView` sends the AttributeGraph into an endless
/// update.
struct HUDFreshnessChip: View {
    let fetchedAt: Date?
    /// The screen's clock; the age and the dot's colour are counted against it.
    let now: Date
    var isLoading = false
    var error: (any Error)?
    /// Past this age the dot turns amber.
    var staleAfter: TimeInterval = 3600

    var body: some View {
        Group {
            if let error {
                HUDStatusChip(text: Text(error.localizedDescription), color: .hudDanger,
                              mark: .symbol("exclamationmark.triangle.fill"))
            } else if isLoading {
                HUDStatusChip(text: Text("Updating"), color: .hudInkMuted, mark: .dot, markColor: .hudAccent)
            } else if let fetchedAt {
                let isStale = now.timeIntervalSince(fetchedAt) > staleAfter
                HUDStatusChip(text: Text("Updated \(fetchedAt, format: .relative(presentation: .named))"),
                              color: .hudInkMuted, mark: .dot, markColor: isStale ? .hudWarn : .hudOk)
            }
        }
        .lineLimit(2)
        .padding(.horizontal, HUDMetrics.headerFaceInset)
    }
}

extension HUDFreshnessChip {
    /// The line for one `ESISnapshot`.
    init<Value>(_ snapshot: ESISnapshot<Value>, now: Date, staleAfter: TimeInterval = 3600) {
        self.init(fetchedAt: snapshot.fetchedAt, now: now, isLoading: snapshot.state.isLoading,
                  error: snapshot.state.error, staleAfter: staleAfter)
    }
}

#Preview("Freshness chip") {
    VStack(alignment: .leading, spacing: 12) {
        HUDFreshnessChip(fetchedAt: .now.addingTimeInterval(-360), now: .now)
        HUDFreshnessChip(fetchedAt: .now.addingTimeInterval(-7200), now: .now)
        HUDFreshnessChip(fetchedAt: nil, now: .now, isLoading: true)
    }
    .padding(HUDMetrics.gutter)
    .background(Color.hudBg)
}
