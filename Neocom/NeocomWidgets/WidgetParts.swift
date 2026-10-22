import SwiftUI
import TrainingTimeline
import WidgetKit

// The pieces every widget family shares: its type styles, the state chip, the queue figure and
// the no-pilot face. Colours come from `HUDInk`, so each piece follows the rendering mode.

extension Font {
    /// The skill in training, sentence case.
    static var widgetSkill: Font { HUDFont.display(14, weight: .semibold, relativeTo: .subheadline) }
    /// The level numeral beside it.
    static var widgetNumeral: Font { HUDFont.display(22, weight: .bold, relativeTo: .title2) }
    /// A title in place of a skill: "Nothing in training", "No pilot".
    static var widgetTitle: Font { HUDFont.display(15, weight: .semibold, relativeTo: .subheadline) }
    /// A pilot's name, uppercase.
    static var widgetPilot: Font { HUDFont.display(14, weight: .semibold, relativeTo: .subheadline) }
    /// The queue figure.
    static var widgetFigure: Font { HUDFont.mono(22, weight: .semibold, relativeTo: .title2) }
    /// A sentence under a figure or a list.
    static var widgetNote: Font { HUDFont.mono(11, weight: .regular, relativeTo: .caption) }
    /// A queued skill in the medium widget's list.
    static var widgetListSkill: Font { HUDFont.display(13, weight: .medium, relativeTo: .footnote) }
    static var widgetListNumeral: Font { HUDFont.display(13, weight: .bold, relativeTo: .footnote) }
    /// A queued skill's time.
    static var widgetListTime: Font { HUDFont.mono(10, weight: .regular, relativeTo: .caption2) }
}

extension QueueStatus {
    /// The age of the snapshot, as the stale chip says it: whole days, at least one.
    func staleDays(now: Date) -> Int {
        guard let fetchedAt else { return 0 }
        return max(1, Int(now.timeIntervalSince(fetchedAt) / 86_400))
    }
}

/// The state chip of a home-screen widget: a word and a mark, never colour alone — tinted, the
/// colours are gone. A stale snapshot takes the place of `TRAINING` with its age, as
/// `HUDFreshnessChip` says it; an alert state keeps its own word.
struct WidgetStatusChip: View {
    let status: QueueStatus
    let now: Date
    @Environment(\.widgetRenderingMode) private var renderingMode

    var body: some View {
        let ink = HUDInk(renderingMode)
        switch status.phase {
        case .training where status.isStale:
            HUDStatusChip(text: Text("\(status.staleDays(now: now)) days ago"),
                          color: ink.muted, mark: .dot, markColor: ink.warn)
        case .training:
            HUDStatusChip(text: Text("Training"), color: ink.accent, mark: .dot)
        case .endingSoon:
            HUDStatusChip(text: Text("Ends soon"), color: ink.warn, mark: .symbol("hourglass"))
        case .paused:
            HUDStatusChip(text: Text("Paused"), color: ink.warn, mark: .symbol("pause.fill"))
        case .idle:
            HUDStatusChip(text: Text("Idle"), color: ink.warn, mark: .symbol("exclamationmark.triangle.fill"))
        case .noData:
            EmptyView()
        }
    }
}

/// How long the queue has left: under a day a live system timer, which counts down on its own
/// between the timeline's entries; otherwise "12d 7h" at `now`. Part of the accent group.
struct QueueFigure: View {
    let status: QueueStatus
    let now: Date
    var font: Font = .widgetFigure
    @Environment(\.widgetRenderingMode) private var renderingMode

    var body: some View {
        let ink = HUDInk(renderingMode)
        if let end = status.queueEnd, end > now {
            Group {
                if status.phase == .endingSoon {
                    // A system timer takes all the width it is offered and has no ideal width:
                    // under `fixedSize()` (the pilots widget) the whole widget rendered black.
                    // It is sized by the widest string it can show — under a day, "00:00:00" —
                    // and drawn over that, aligned by the surrounding text alignment.
                    Text(verbatim: "00:00:00")
                        .hidden()
                        .overlay {
                            Text(timerInterval: now...end, countsDown: true)
                                .foregroundStyle(ink.warn)
                        }
                } else {
                    Text(verbatim: TrainingTime.string(end.timeIntervalSince(now)))
                        .foregroundStyle(ink.accent)
                }
            }
            .font(font)
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .widgetAccentable()
        }
    }
}

/// The uppercase mono label over a figure or a list.
struct WidgetLabel: View {
    let text: Text
    @Environment(\.widgetRenderingMode) private var renderingMode

    init(_ text: Text) {
        self.text = text
    }

    var body: some View {
        text
            .font(.hudMicro)
            .tracking(1.5)
            .textCase(.uppercase)
            .foregroundStyle(HUDInk(renderingMode).muted)
            .lineLimit(1)
    }
}

/// The pilot's plate: the portrait the app left in the App Group over the initials.
struct PilotAvatar: View {
    let pilot: WidgetSnapshot.Pilot
    var size: CGFloat = 28

    var body: some View {
        HUDInitialsAvatar(name: pilot.name, size: size, image: portraitImage(of: pilot))
    }
}

/// The empty place of a pilot, dashed, for a widget with nobody signed in.
struct NoPilotMark: View {
    var size: CGFloat = 28
    @Environment(\.widgetRenderingMode) private var renderingMode

    var body: some View {
        let ink = HUDInk(renderingMode)
        let radius = HUDImagePlate.radius(for: size)
        Image(systemName: "person")
            .font(.system(size: size * 0.46, weight: .medium))
            .foregroundStyle(ink.muted)
            .frame(width: size, height: size)
            .overlay {
                HUDDashedOutline(cornerRadii: .init(topLeading: radius, bottomLeading: radius,
                                                    bottomTrailing: radius, topTrailing: radius),
                                 dash: 3, gap: 3)
                    .fill(ink.lineLeader)
            }
            .accessibilityHidden(true)
    }
}

/// The medium face with nobody signed in.
struct NoPilotMedium: View {
    @Environment(\.widgetRenderingMode) private var renderingMode

    var body: some View {
        let ink = HUDInk(renderingMode)
        HStack(spacing: 14) {
            NoPilotMark(size: 48)
            VStack(alignment: .leading, spacing: 4) {
                WidgetLabel(Text("No pilot"))
                Text("Open Neocom and sign in with EVE Online. Training queues show up here.")
                    .font(.hudBody)
                    .foregroundStyle(ink.bodyMuted)
                    .lineLimit(3)
                    .minimumScaleFactor(0.8)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
