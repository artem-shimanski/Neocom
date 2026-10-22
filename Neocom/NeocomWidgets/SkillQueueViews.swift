import SwiftUI
import TrainingTimeline
import WidgetKit

/// The single-pilot widget, by family. Every view draws at the entry's date — the widget's one
/// clock; only the system timer of a queue ending soon runs between entries.
struct SkillQueueWidgetView: View {
    let entry: SkillQueueEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .accessoryCircular:
            CircularAccessoryView(pilot: entry.pilot, now: entry.date)
        case .accessoryRectangular:
            RectangularAccessoryView(pilot: entry.pilot, now: entry.date)
        case .systemMedium:
            Group {
                if let pilot = entry.pilot {
                    MediumQueueView(pilot: pilot, now: entry.date)
                } else {
                    NoPilotMedium()
                }
            }
            .containerBackground(Color.hudSurface, for: .widget)
        default:
            SmallQueueView(pilot: entry.pilot, now: entry.date)
                .containerBackground(Color.hudSurface, for: .widget)
        }
    }
}

// MARK: - Small

/// The small widget: the pilot and the state on top, the current skill and the queue figure at
/// the bottom. Also the left column of the medium one.
struct SmallQueueView: View {
    let pilot: WidgetSnapshot.Pilot?
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let pilot {
                let status = QueueStatus(pilot: pilot, now: now)
                // One gap, not one each side of the spacer: on a 155 pt widget "ENDS SOON" needs
                // every point of the row.
                HStack(spacing: 0) {
                    PilotAvatar(pilot: pilot)
                    Spacer(minLength: 8)
                    WidgetStatusChip(status: status, now: now)
                        .layoutPriority(1)
                }
                .frame(height: 28)
                // The summary is laid out first: a long skill name takes its second line from
                // the gap, not from itself.
                Spacer(minLength: 0)
                QueueSummary(status: status, now: now)
                    .layoutPriority(1)
            } else {
                NoPilotMark()
                Spacer(minLength: 8)
                NoPilotSummary()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

/// The bottom of the small widget for one pilot's queue.
struct QueueSummary: View {
    let status: QueueStatus
    let now: Date
    @Environment(\.widgetRenderingMode) private var renderingMode

    var body: some View {
        let ink = HUDInk(renderingMode)
        VStack(alignment: .leading, spacing: 0) {
            if let current = status.current {
                HStack(alignment: .lastTextBaseline, spacing: 6) {
                    Text(verbatim: current.name)
                        .font(.widgetSkill)
                        .foregroundStyle(ink.ink)
                        .lineLimit(2)
                        .minimumScaleFactor(0.85)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(verbatim: SkillLevelNumeral.roman(current.level))
                        .font(.widgetNumeral)
                        .foregroundStyle(ink.accent)
                        .widgetAccentable()
                }
                HUDLevelBar(trained: current.trainedLevel, training: current.level,
                            paused: status.phase == .paused, trainingProgress: current.progress,
                            height: 8, spacing: 3)
                    .padding(.top, 8)
                if status.phase == .paused {
                    Text("Resume it from the EVE client.")
                        .font(.widgetNote)
                        .foregroundStyle(ink.warnNote)
                        .lineLimit(2)
                        .padding(.top, 10)
                } else {
                    WidgetLabel(Text("Queue ends in"))
                        .padding(.top, 10)
                    QueueFigure(status: status, now: now)
                }
            } else if status.phase == .idle {
                Text("Nothing in training")
                    .font(.widgetTitle)
                    .foregroundStyle(ink.ink)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                Text("Add skills in the EVE client.")
                    .font(.widgetNote)
                    .foregroundStyle(ink.bodyMuted)
                    .lineLimit(2)
                    .padding(.top, 4)
                // Without a known moment the queue ran out, there is no figure to count from.
                if let since = status.idleSince, since < now {
                    WidgetLabel(Text("Idle for"))
                        .padding(.top, 10)
                    Text(verbatim: TrainingTime.string(now.timeIntervalSince(since)))
                        .font(.widgetFigure)
                        .foregroundStyle(ink.warn)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            } else {
                Text("No queue yet")
                    .font(.widgetTitle)
                    .foregroundStyle(ink.ink)
                Text("Open Neocom to load the training queue.")
                    .font(.widgetNote)
                    .foregroundStyle(ink.bodyMuted)
                    .lineLimit(3)
                    .padding(.top, 4)
            }
        }
    }
}

/// The bottom of the small widget with nobody signed in.
private struct NoPilotSummary: View {
    @Environment(\.widgetRenderingMode) private var renderingMode

    var body: some View {
        let ink = HUDInk(renderingMode)
        VStack(alignment: .leading, spacing: 4) {
            Text("No pilot")
                .font(.widgetTitle)
                .foregroundStyle(ink.ink)
            Text("Open Neocom and sign in with EVE Online.")
                .font(.widgetNote)
                .foregroundStyle(ink.bodyMuted)
                .lineLimit(3)
        }
    }
}

// MARK: - Medium

/// The medium widget for one pilot: the small widget's face on the left, what comes next on
/// the right — the queue, or the local plan when the queue is empty.
struct MediumQueueView: View {
    let pilot: WidgetSnapshot.Pilot
    let now: Date
    @Environment(\.widgetRenderingMode) private var renderingMode

    var body: some View {
        let ink = HUDInk(renderingMode)
        let status = QueueStatus(pilot: pilot, now: now)
        HStack(spacing: 16) {
            SmallQueueView(pilot: pilot, now: now)
                .frame(width: 150)
            ink.line
                .frame(width: 1)
            NextList(pilot: pilot, status: status, now: now)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}

/// The right half of the medium widget.
private struct NextList: View {
    let pilot: WidgetSnapshot.Pilot
    let status: QueueStatus
    let now: Date
    @Environment(\.widgetRenderingMode) private var renderingMode

    private struct Row: Identifiable {
        let id: Int
        let name: String
        let level: Int
        let time: String
    }

    var body: some View {
        let ink = HUDInk(renderingMode)
        VStack(alignment: .leading, spacing: 0) {
            WidgetLabel(header)
                .frame(height: 28, alignment: .leading)
            ForEach(rows) { row in
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(verbatim: row.name)
                            .font(.widgetListSkill)
                            .foregroundStyle(ink.ink)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text(verbatim: SkillLevelNumeral.roman(row.level))
                            .font(.widgetListNumeral)
                            // The plan is not training yet: its numerals stay quiet.
                            .foregroundStyle(isPlan ? ink.muted : ink.accent)
                    }
                    Text(verbatim: row.time)
                        .font(.widgetListTime)
                        .foregroundStyle(ink.muted)
                        .lineLimit(1)
                }
                .padding(.vertical, 3)
                .overlay(alignment: .top) { ink.lineSubtle.frame(height: 1) }
            }
            if let note {
                Spacer(minLength: 4)
                note
                    .font(.widgetNote)
                    .foregroundStyle(ink.warnNote)
                    .lineLimit(3)
                    .padding(.top, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .overlay(alignment: .top) { ink.lineSubtle.frame(height: 1) }
            }
        }
    }

    private var isPlan: Bool { status.phase == .idle }

    private var header: Text {
        if isPlan {
            return pilot.plan.isEmpty ? Text("In your plan") : Text("In your plan · \(pilot.plan.count)")
        }
        if status.phase == .noData { return Text("Next") }
        switch status.remainingCount {
        case 0: return Text("Next · nothing queued")
        case 1: return Text("Next · last in queue")
        default: return Text("Next · \(status.remainingCount) in queue")
        }
    }

    private var rows: [Row] {
        if isPlan {
            return pilot.plan.prefix(3).enumerated().map { index, entry in
                Row(id: index, name: entry.name, level: entry.level,
                    time: entry.duration.map(TrainingTime.string) ?? "")
            }
        }
        // A queue that ends soon keeps a line for the note under it.
        let limit = status.phase == .endingSoon ? 2 : 3
        return status.next.prefix(limit).enumerated().map { index, entry in
            Row(id: index, name: entry.name, level: entry.level, time: time(of: entry))
        }
    }

    /// "2d 3h · OCT 21, 13:52"; a paused entry waits instead of finishing.
    private func time(of entry: WidgetSnapshot.QueueEntry) -> String {
        let duration = entry.duration.map(TrainingTime.string)
        let when: String
        if let finish = entry.finishDate {
            // The day and the time apart: together the formatter puts "at" between them.
            let day = finish.formatted(.dateTime.day().month(.abbreviated))
            let time = finish.formatted(.dateTime.hour().minute())
            when = "\(day) \(time)".uppercased()
        } else {
            when = String(localized: "waits for resume")
        }
        return [duration, when].compactMap { $0 }.joined(separator: " · ")
    }

    private var note: Text? {
        switch status.phase {
        case .endingSoon:
            return Text("The queue ends within a day. Add skills in the EVE client.")
        case .idle where pilot.plan.isEmpty:
            return Text("Nothing planned. Plan skills in Neocom.")
        default:
            return nil
        }
    }
}
