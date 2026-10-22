//
//  WidgetTimeline.swift
//  TrainingTimeline
//

import Foundation

/// Which pilots a widget shows and the moments its timeline needs.
public enum WidgetTimeline {
    /// How many pilots the multi-pilot widget lists.
    public static let pilotLimit = 3
    /// The spacing of the entries that move the progress bars between events.
    public static let progressStep: TimeInterval = 15 * 60
    /// The most entries one timeline gets; the widget asks for a new one after the last.
    public static let entryLimit = 48

    /// The pilot of a single-pilot widget: `selected` when it is still signed in, otherwise the
    /// app's active pilot, otherwise the first one. `nil` when nobody is signed in.
    public static func pilot(in snapshot: WidgetSnapshot, selected: Int64? = nil) -> WidgetSnapshot.Pilot? {
        if let selected, let pilot = snapshot[selected] { return pilot }
        if let active = snapshot.activePilotID, let pilot = snapshot[active] { return pilot }
        return snapshot.pilots.first
    }

    /// The pilots of the multi-pilot widget: the `selected` ones in the order given, skipping
    /// those no longer signed in; with no selection, the active pilot first and the others in the
    /// app's order. At most `limit`.
    public static func pilots(in snapshot: WidgetSnapshot, selected: [Int64]? = nil,
                              limit: Int = pilotLimit) -> [WidgetSnapshot.Pilot] {
        var result: [WidgetSnapshot.Pilot]
        if let selected, !selected.isEmpty {
            var seen = Set<Int64>()
            result = selected.filter { seen.insert($0).inserted }.compactMap { snapshot[$0] }
        } else {
            let active = snapshot.activePilotID.flatMap { snapshot[$0] }
            result = (active.map { [$0] } ?? []) + snapshot.pilots.filter { $0.id != active?.id }
        }
        return Array(result.prefix(max(limit, 0)))
    }

    /// The entry dates of a timeline over `pilots`, starting at `now`: every finish ahead (the
    /// current skill changes), the moment each queue starts ending soon and each snapshot turns
    /// stale, and a point every `step` between them for the progress. Sorted, at most `limit`.
    public static func dates(for pilots: [WidgetSnapshot.Pilot], from now: Date,
                             step: TimeInterval = progressStep, limit: Int = entryLimit) -> [Date] {
        guard limit > 0 else { return [] }
        var events = Set<Date>()
        var hasData = false
        for pilot in pilots {
            guard let training = pilot.training else { continue }
            hasData = true
            for finish in training.queue.compactMap(\.finishDate) {
                events.insert(finish)
            }
            if let end = training.queue.compactMap(\.finishDate).max() {
                events.insert(end.addingTimeInterval(-QueueStatus.endingSoonWithin))
            }
            events.insert(training.fetchedAt.addingTimeInterval(QueueStatus.staleAfter))
        }
        if hasData, step > 0 {
            for index in 1..<limit {
                events.insert(now.addingTimeInterval(step * Double(index)))
            }
        }
        let ahead = events.filter { $0 > now }.sorted()
        return [now] + ahead.prefix(limit - 1)
    }
}

/// Skill levels the way the game writes them, for the app and the widget alike. Zero is the
/// digit: there is no Roman zero.
public enum SkillLevelNumeral {
    private static let numerals = ["0", "I", "II", "III", "IV", "V"]

    public static func roman(_ level: Int) -> String {
        guard numerals.indices.contains(level) else { return String(level) }
        return numerals[level]
    }
}
