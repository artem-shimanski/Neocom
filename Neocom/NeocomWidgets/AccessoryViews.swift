import SwiftUI
import TrainingTimeline
import WidgetKit

// The Lock Screen faces. The system renders them in one tint, so every state is a word or a
// symbol, and the snapshot's age is left out: there is no room to say it well.

/// The ring is the current skill's progress; the centre says whose queue it is and how long it
/// has left. A state that needs attention trades the initials for its symbol and sits on the
/// system's accessory background.
struct CircularAccessoryView: View {
    let pilot: WidgetSnapshot.Pilot?
    let now: Date
    @Environment(\.widgetRenderingMode) private var renderingMode

    var body: some View {
        ZStack {
            if let pilot {
                let status = QueueStatus(pilot: pilot, now: now)
                if [.endingSoon, .paused, .idle].contains(status.phase) {
                    AccessoryWidgetBackground()
                }
                HUDProgressRing(fraction: status.current?.progress ?? 0,
                                arcOpacity: status.phase == .paused ? 0.55 : 1)
                centre(status, pilot: pilot)
            } else {
                Circle()
                    .strokeBorder(Color.white.opacity(0.35), style: StrokeStyle(lineWidth: 2, dash: [4, 5]))
                    .padding(3)
                Image(systemName: "person")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.75))
            }
        }
        .containerBackground(for: .widget) { Color.clear }
    }

    @ViewBuilder
    private func centre(_ status: QueueStatus, pilot: WidgetSnapshot.Pilot) -> some View {
        let ink = HUDInk(renderingMode)
        switch status.phase {
        case .training, .endingSoon:
            let parts = Self.parts(of: status.queueEnd.map { $0.timeIntervalSince(now) } ?? 0)
            VStack(spacing: 0) {
                if status.phase == .endingSoon {
                    Image(systemName: "hourglass")
                        .font(.system(size: 10, weight: .bold))
                } else {
                    Text(verbatim: pilot.initials)
                        .font(HUDFont.mono(10, weight: .regular, relativeTo: .caption2))
                        .tracking(1)
                        .foregroundStyle(ink.muted)
                }
                Text(verbatim: parts.major)
                    .font(HUDFont.mono(18, weight: .semibold, relativeTo: .title3))
                    .widgetAccentable()
                if let minor = parts.minor {
                    Text(verbatim: minor)
                        .font(HUDFont.mono(11, weight: .regular, relativeTo: .caption))
                        .foregroundStyle(ink.muted)
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.6)
        case .idle:
            VStack(spacing: 3) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 13, weight: .bold))
                Text("Idle")
                    .font(HUDFont.mono(11, weight: .semibold, relativeTo: .caption))
                    .tracking(1)
                    .textCase(.uppercase)
            }
        case .paused:
            Image(systemName: "pause.fill")
                .font(.system(size: 20, weight: .bold))
                .accessibilityLabel(Text("Paused"))
        case .noData:
            VStack(spacing: 0) {
                Text(verbatim: pilot.initials)
                    .font(HUDFont.mono(10, weight: .regular, relativeTo: .caption2))
                    .foregroundStyle(ink.muted)
                Text(verbatim: "—")
                    .font(HUDFont.mono(18, weight: .semibold, relativeTo: .title3))
            }
        }
    }

    /// "12d" over "7h", "5h" over "12m", "40m" alone: the two largest units, stacked.
    static func parts(of interval: TimeInterval) -> (major: String, minor: String?) {
        let total = max(Int(interval), 0)
        func days(_ value: Int) -> String {
            Duration.seconds(value * 86_400).formatted(.units(allowed: [.days], width: .narrow))
        }
        func hours(_ value: Int) -> String {
            Duration.seconds(value * 3600).formatted(.units(allowed: [.hours], width: .narrow))
        }
        func minutes(_ value: Int) -> String {
            Duration.seconds(value * 60).formatted(.units(allowed: [.minutes], width: .narrow))
        }
        let d = total / 86_400, h = total % 86_400 / 3600, m = total % 3600 / 60
        if d > 0 { return (days(d), hours(h)) }
        if h > 0 { return (hours(h), minutes(m)) }
        return (minutes(m), nil)
    }
}

/// The pilot, the current skill with its progress, and one line for the queue.
struct RectangularAccessoryView: View {
    let pilot: WidgetSnapshot.Pilot?
    let now: Date
    @Environment(\.widgetRenderingMode) private var renderingMode

    var body: some View {
        let ink = HUDInk(renderingMode)
        VStack(alignment: .leading, spacing: 3) {
            if let pilot {
                let status = QueueStatus(pilot: pilot, now: now)
                Text(verbatim: pilot.name)
                    .font(HUDFont.display(14, weight: .bold, relativeTo: .headline))
                    .tracking(0.5)
                    .textCase(.uppercase)
                    .lineLimit(1)
                Group {
                    if let current = status.current {
                        Text(verbatim: "\(current.name) \(SkillLevelNumeral.roman(current.level))")
                    } else if status.phase == .idle {
                        Text("Nothing in training")
                    } else {
                        Text("Open Neocom to load the queue.")
                    }
                }
                .font(HUDFont.display(12, weight: .medium, relativeTo: .caption))
                .foregroundStyle(ink.bodyMuted)
                .lineLimit(1)
                if let current = status.current {
                    let paused = status.phase == .paused
                    // Paused, the whole bar is the hatch: there is no progress to speak of.
                    HUDJobProgressBar(fraction: paused ? 1 : current.progress, isPaused: paused, height: 4)
                        .padding(.vertical, 2)
                }
                queueLine(status, ink: ink)
            } else {
                Text(verbatim: "Neocom")
                    .font(HUDFont.display(14, weight: .bold, relativeTo: .headline))
                    .tracking(0.5)
                    .textCase(.uppercase)
                Text("Open the app and sign in with EVE Online.")
                    .font(HUDFont.display(12, weight: .medium, relativeTo: .caption))
                    .foregroundStyle(ink.bodyMuted)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .containerBackground(for: .widget) { Color.clear }
    }

    @ViewBuilder
    private func queueLine(_ status: QueueStatus, ink: HUDInk) -> some View {
        let label = HUDFont.mono(10, weight: .regular, relativeTo: .caption2)
        let figure = HUDFont.mono(14, weight: .semibold, relativeTo: .subheadline)
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            switch status.phase {
            case .training:
                Text("Queue").font(label).tracking(1.5).textCase(.uppercase).foregroundStyle(ink.muted)
                QueueFigure(status: status, now: now, font: figure)
            case .endingSoon:
                Image(systemName: "hourglass").font(.system(size: 10, weight: .bold))
                Text("Ends").font(label).tracking(1.5).textCase(.uppercase)
                QueueFigure(status: status, now: now, font: figure)
            case .idle:
                Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 10, weight: .bold))
                Text("Idle for").font(label).tracking(1.5).textCase(.uppercase)
                if let since = status.idleSince, since < now {
                    Text(verbatim: TrainingTime.string(now.timeIntervalSince(since))).font(figure)
                }
            case .paused:
                Image(systemName: "pause.fill").font(.system(size: 10, weight: .bold))
                Text("Paused in game").font(label).tracking(1.5).textCase(.uppercase)
            case .noData:
                EmptyView()
            }
        }
        .lineLimit(1)
    }
}
