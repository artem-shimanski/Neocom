import SwiftUI
import TrainingTimeline
import UIKit
import WidgetKit

/// One moment of a single-pilot widget. `pilot` is `nil` when nobody is signed in.
nonisolated struct SkillQueueEntry: TimelineEntry {
    let date: Date
    let pilot: WidgetSnapshot.Pilot?
}

/// One moment of the multi-pilot widget; empty when nobody is signed in.
nonisolated struct PilotsEntry: TimelineEntry {
    let date: Date
    let pilots: [WidgetSnapshot.Pilot]
}

/// The snapshot only changes when the app writes a new one (and reloads the timelines), so a
/// timeline is the same pilots at every moment `WidgetTimeline.dates` names: the views work out
/// where each queue stands from the entry's date. One date means there is nothing to move —
/// the timeline then waits for the app.
private nonisolated func policy(_ dates: [Date]) -> TimelineReloadPolicy {
    dates.count > 1 ? .atEnd : .never
}

nonisolated struct SkillQueueProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> SkillQueueEntry {
        SkillQueueEntry(date: .now, pilot: WidgetSamples.artem(.training, now: .now))
    }

    func snapshot(for configuration: SkillQueueIntent, in context: Context) async -> SkillQueueEntry {
        if context.isPreview {
            return placeholder(in: context)
        }
        return SkillQueueEntry(date: .now, pilot: pilot(for: configuration))
    }

    func timeline(for configuration: SkillQueueIntent, in context: Context) async -> Timeline<SkillQueueEntry> {
        let now = Date.now
        let pilot = pilot(for: configuration)
        let dates = WidgetTimeline.dates(for: pilot.map { [$0] } ?? [], from: now)
        return Timeline(entries: dates.map { SkillQueueEntry(date: $0, pilot: pilot) }, policy: policy(dates))
    }

    private func pilot(for configuration: SkillQueueIntent) -> WidgetSnapshot.Pilot? {
        guard let snapshot = WidgetStore.read() else { return nil }
        return WidgetTimeline.pilot(in: snapshot, selected: configuration.pilot.map { Int64($0.id) })
    }
}

nonisolated struct PilotsProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> PilotsEntry {
        PilotsEntry(date: .now, pilots: WidgetSamples.snapshot(now: .now).pilots)
    }

    func snapshot(for configuration: PilotsIntent, in context: Context) async -> PilotsEntry {
        if context.isPreview {
            return placeholder(in: context)
        }
        return PilotsEntry(date: .now, pilots: pilots(for: configuration))
    }

    func timeline(for configuration: PilotsIntent, in context: Context) async -> Timeline<PilotsEntry> {
        let now = Date.now
        let pilots = pilots(for: configuration)
        let dates = WidgetTimeline.dates(for: pilots, from: now)
        return Timeline(entries: dates.map { PilotsEntry(date: $0, pilots: pilots) }, policy: policy(dates))
    }

    private func pilots(for configuration: PilotsIntent) -> [WidgetSnapshot.Pilot] {
        guard let snapshot = WidgetStore.read() else { return [] }
        return WidgetTimeline.pilots(in: snapshot, selected: configuration.pilots?.map { Int64($0.id) })
    }
}

/// The portrait the app left in the App Group, read at once: a widget cannot wait for a
/// download. `nil` keeps the initials.
func portraitImage(of pilot: WidgetSnapshot.Pilot) -> Image? {
    guard let url = WidgetStore.portraitURL(of: pilot),
          let image = UIImage(contentsOfFile: url.path(percentEncoded: false))
    else { return nil }
    return Image(uiImage: image)
}
