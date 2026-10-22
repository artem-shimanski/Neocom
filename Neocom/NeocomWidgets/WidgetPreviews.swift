import SwiftUI
import TrainingTimeline
import WidgetKit

// One entry per state of the sample pilot's queue, then nobody signed in; the canvas steps through
// them. Rendering modes (tinted, Lock Screen) are switched in the canvas's own controls.

#Preview("Small", as: .systemSmall) {
    SkillQueueWidget()
} timeline: {
    SkillQueueEntry(date: .now, pilot: WidgetSamples.artem(.training, now: .now))
    SkillQueueEntry(date: .now, pilot: WidgetSamples.artem(.endingSoon, now: .now))
    SkillQueueEntry(date: .now, pilot: WidgetSamples.artem(.idle, now: .now))
    SkillQueueEntry(date: .now, pilot: WidgetSamples.artem(.paused, now: .now))
    SkillQueueEntry(date: .now, pilot: WidgetSamples.artem(.stale, now: .now))
    SkillQueueEntry(date: .now, pilot: WidgetSamples.artem(.noData, now: .now))
    SkillQueueEntry(date: .now, pilot: nil)
}

#Preview("Medium · queue", as: .systemMedium) {
    SkillQueueWidget()
} timeline: {
    SkillQueueEntry(date: .now, pilot: WidgetSamples.artem(.training, now: .now))
    SkillQueueEntry(date: .now, pilot: WidgetSamples.artem(.endingSoon, now: .now))
    SkillQueueEntry(date: .now, pilot: WidgetSamples.artem(.paused, now: .now))
    SkillQueueEntry(date: .now, pilot: WidgetSamples.artem(.idle, now: .now))
    SkillQueueEntry(date: .now, pilot: WidgetSamples.artem(.stale, now: .now))
    SkillQueueEntry(date: .now, pilot: nil)
}

#Preview("Circular", as: .accessoryCircular) {
    SkillQueueWidget()
} timeline: {
    SkillQueueEntry(date: .now, pilot: WidgetSamples.artem(.training, now: .now))
    SkillQueueEntry(date: .now, pilot: WidgetSamples.artem(.endingSoon, now: .now))
    SkillQueueEntry(date: .now, pilot: WidgetSamples.artem(.idle, now: .now))
    SkillQueueEntry(date: .now, pilot: WidgetSamples.artem(.paused, now: .now))
    SkillQueueEntry(date: .now, pilot: nil)
}

#Preview("Rectangular", as: .accessoryRectangular) {
    SkillQueueWidget()
} timeline: {
    SkillQueueEntry(date: .now, pilot: WidgetSamples.artem(.training, now: .now))
    SkillQueueEntry(date: .now, pilot: WidgetSamples.artem(.endingSoon, now: .now))
    SkillQueueEntry(date: .now, pilot: WidgetSamples.artem(.idle, now: .now))
    SkillQueueEntry(date: .now, pilot: WidgetSamples.artem(.paused, now: .now))
    SkillQueueEntry(date: .now, pilot: nil)
}

#Preview("Medium · pilots", as: .systemMedium) {
    PilotsWidget()
} timeline: {
    PilotsEntry(date: .now, pilots: WidgetSamples.snapshot(now: .now).pilots)
    PilotsEntry(date: .now, pilots: [WidgetSamples.artem(.paused, now: .now), WidgetSamples.mira(now: .now, stale: true)])
    PilotsEntry(date: .now, pilots: [])
}

// MARK: - Tinted

// The canvas has no control for the tinted Home Screen, so these widgets, which exist only for
// the previews, draw the same views with the rendering mode set. Only the tokens (`HUDInk`)
// change; the system's own tinting of the accent group is not drawn here.

#if DEBUG
private nonisolated struct TintedPreviewProvider: TimelineProvider {
    func placeholder(in context: Context) -> SkillQueueEntry {
        SkillQueueEntry(date: .now, pilot: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping @Sendable (SkillQueueEntry) -> Void) {
        completion(SkillQueueEntry(date: .now, pilot: nil))
    }

    func getTimeline(in context: Context, completion: @escaping @Sendable (Timeline<SkillQueueEntry>) -> Void) {
        completion(Timeline(entries: [SkillQueueEntry(date: .now, pilot: nil)], policy: .never))
    }
}

private struct TintedSkillQueueWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "TintedPreview", provider: TintedPreviewProvider()) { entry in
            SkillQueueWidgetView(entry: entry)
                .environment(\.widgetRenderingMode, .accented)
        }
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

#Preview("Small · tinted", as: .systemSmall) {
    TintedSkillQueueWidget()
} timeline: {
    SkillQueueEntry(date: .now, pilot: WidgetSamples.artem(.training, now: .now))
    SkillQueueEntry(date: .now, pilot: WidgetSamples.artem(.endingSoon, now: .now))
    SkillQueueEntry(date: .now, pilot: WidgetSamples.artem(.paused, now: .now))
    SkillQueueEntry(date: .now, pilot: WidgetSamples.artem(.idle, now: .now))
}

#Preview("Medium · tinted", as: .systemMedium) {
    TintedSkillQueueWidget()
} timeline: {
    SkillQueueEntry(date: .now, pilot: WidgetSamples.artem(.training, now: .now))
    SkillQueueEntry(date: .now, pilot: WidgetSamples.artem(.paused, now: .now))
}

/// The canvas snapshots of the Lock Screen families come out empty, so the two accessories are
/// also drawn side by side inside a medium widget, at their iPhone sizes, in the Lock Screen's
/// rendering mode. `AccessoryWidgetBackground` draws nothing there.
private struct LockScreenPreviewWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "LockScreenPreview", provider: TintedPreviewProvider()) { entry in
            HStack(spacing: 12) {
                CircularAccessoryView(pilot: entry.pilot, now: entry.date)
                    .frame(width: 72, height: 72)
                RectangularAccessoryView(pilot: entry.pilot, now: entry.date)
                    .frame(width: 172, height: 76)
            }
            .foregroundStyle(.white)
            .environment(\.widgetRenderingMode, .vibrant)
            .containerBackground(for: .widget) {
                LinearGradient(colors: [Color(red: 0.23, green: 0.18, blue: 0.39), Color(red: 0.11, green: 0.16, blue: 0.25)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
            }
        }
        .supportedFamilies([.systemMedium])
    }
}

#Preview("Lock Screen · side by side", as: .systemMedium) {
    LockScreenPreviewWidget()
} timeline: {
    SkillQueueEntry(date: .now, pilot: WidgetSamples.artem(.training, now: .now))
    SkillQueueEntry(date: .now, pilot: WidgetSamples.artem(.endingSoon, now: .now))
    SkillQueueEntry(date: .now, pilot: WidgetSamples.artem(.idle, now: .now))
    SkillQueueEntry(date: .now, pilot: WidgetSamples.artem(.paused, now: .now))
    SkillQueueEntry(date: .now, pilot: nil)
}
#endif
