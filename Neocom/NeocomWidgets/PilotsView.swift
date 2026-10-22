import SwiftUI
import TrainingTimeline
import WidgetKit

/// The multi-pilot widget: a row per pilot — who, what they train, and how long their queue
/// has left, or the state that matters more.
struct PilotsWidgetView: View {
    let entry: PilotsEntry

    var body: some View {
        Group {
            if entry.pilots.isEmpty {
                NoPilotMedium()
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(entry.pilots.enumerated()), id: \.element.id) { index, pilot in
                        PilotRow(pilot: pilot, now: entry.date, isFirst: index == 0)
                    }
                }
            }
        }
        .containerBackground(Color.hudSurface, for: .widget)
    }
}

private struct PilotRow: View {
    let pilot: WidgetSnapshot.Pilot
    let now: Date
    let isFirst: Bool
    @Environment(\.widgetRenderingMode) private var renderingMode

    var body: some View {
        let ink = HUDInk(renderingMode)
        let status = QueueStatus(pilot: pilot, now: now)
        HStack(spacing: 10) {
            PilotAvatar(pilot: pilot, size: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: pilot.name)
                    .font(.widgetPilot)
                    .tracking(0.5)
                    .textCase(.uppercase)
                    .foregroundStyle(ink.ink)
                    .lineLimit(1)
                skill(status, ink: ink)
                    .font(.widgetNote)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .trailing, spacing: 2) {
                figure(status, ink: ink)
                    .font(.hudFigure)
                    .lineLimit(1)
                trailingChip(status, ink: ink)
            }
            .multilineTextAlignment(.trailing)
            .fixedSize()
        }
        .frame(maxHeight: .infinity)
        .overlay(alignment: .top) {
            if !isFirst {
                ink.lineSubtle.frame(height: 1)
            }
        }
    }

    @ViewBuilder
    private func skill(_ status: QueueStatus, ink: HUDInk) -> some View {
        if let current = status.current {
            Text(verbatim: "\(current.name) \(SkillLevelNumeral.roman(current.level))")
                .foregroundStyle(ink.muted)
        } else if status.phase == .idle {
            Text("Nothing in training")
                .foregroundStyle(ink.warn)
        } else {
            Text("Open Neocom to load the queue.")
                .foregroundStyle(ink.muted)
        }
    }

    @ViewBuilder
    private func figure(_ status: QueueStatus, ink: HUDInk) -> some View {
        switch status.phase {
        case .training, .endingSoon:
            QueueFigure(status: status, now: now, font: .hudFigure)
        case .paused:
            Text("Paused")
                .textCase(.uppercase)
                .foregroundStyle(ink.warn)
        case .idle:
            if let since = status.idleSince, since < now {
                Text(verbatim: TrainingTime.string(now.timeIntervalSince(since)))
                    .foregroundStyle(ink.warn)
            }
        case .noData:
            EmptyView()
        }
    }

    /// The word under the figure; alert states carry their symbol too, as on the small widget.
    @ViewBuilder
    private func trailingChip(_ status: QueueStatus, ink: HUDInk) -> some View {
        switch status.phase {
        case .training where status.isStale:
            HUDStatusChip(text: Text("\(status.staleDays(now: now)) days ago"),
                          color: ink.muted, mark: .dot, markColor: ink.warn)
        case .training:
            HUDStatusChip(text: Text("Queue"), color: ink.muted)
        case .endingSoon:
            HUDStatusChip(text: Text("Ends soon"), color: ink.warn, mark: .symbol("hourglass"))
        case .paused:
            HUDStatusChip(text: Text("Resume in EVE"), color: ink.muted, mark: .symbol("pause.fill"))
        case .idle:
            HUDStatusChip(text: Text("Idle"), color: ink.warn, mark: .symbol("exclamationmark.triangle.fill"))
        case .noData:
            EmptyView()
        }
    }
}
