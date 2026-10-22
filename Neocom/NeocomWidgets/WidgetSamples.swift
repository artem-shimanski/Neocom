import Foundation
import TrainingTimeline

/// Example pilots for the widget gallery, the placeholder and the previews: the main sample pilot on the
/// drone specializations, and two fictional alts. Every date is laid out around `now`, so the
/// sample reads the same whenever it is drawn.
nonisolated enum WidgetSamples {
    enum State: CaseIterable {
        case training, endingSoon, paused, idle, stale, noData
    }

    static let artemID: Int64 = 1
    static let miraID: Int64 = 2
    static let bramID: Int64 = 3

    /// The gallery's picture: one pilot training, one whose queue ends today, one idle.
    static func snapshot(now: Date) -> WidgetSnapshot {
        WidgetSnapshot(activePilotID: artemID, pilots: [
            artem(.training, now: now),
            mira(now: now),
            bram(now: now),
        ])
    }

    /// The main sample pilot in `state`.
    static func artem(_ state: State, now: Date) -> WidgetSnapshot.Pilot {
        let fresh = now.addingTimeInterval(-20 * 60)
        let training: WidgetSnapshot.Training?
        switch state {
        case .training:
            training = .init(fetchedAt: fresh, queue: queue(now: now, current: (name: "Amarr Drone Specialization", level: 4, rank: 5, progress: 0.62, left: hours(30)), next: [
                ("Caldari Drone Specialization", 3, 5, hours(51)),
                ("Minmatar Drone Specialization", 3, 5, hours(51)),
                ("Fighters", 1, 12, minutes(256)),
                ("Gallente Drone Specialization", 3, 5, hours(51)),
                ("Fighter Hangar Management", 1, 8, minutes(220)),
                ("Light Fighters", 1, 8, hours(98)),
            ]))
        case .endingSoon:
            training = .init(fetchedAt: fresh, queue: queue(now: now, current: (name: "Caldari Drone Specialization", level: 3, rank: 5, progress: 0.88, left: minutes(184)), next: [
                ("Fighters", 1, 12, minutes(128)),
            ]))
        case .paused:
            training = .init(fetchedAt: fresh, queue: [
                paused("Shield Rigging", level: 5, rank: 3, held: 0.4, duration: hours(64)),
                paused("Jury Rigging", level: 5, rank: 2, duration: hours(107)),
                paused("Armor Rigging", level: 4, rank: 3, duration: hours(33)),
            ])
        case .idle:
            training = .init(fetchedAt: fresh, queue: [], idleSince: now.addingTimeInterval(-hours(52)))
        case .stale:
            training = .init(fetchedAt: now.addingTimeInterval(-hours(73)), queue: queue(now: now, current: (name: "Minmatar Drone Specialization", level: 3, rank: 5, progress: 0.35, left: hours(40)), next: [
                ("Gallente Drone Specialization", 3, 5, hours(51)),
                ("Fighters", 1, 12, minutes(256)),
                ("Light Fighters", 1, 8, hours(122)),
            ]))
        case .noData:
            training = nil
        }
        return WidgetSnapshot.Pilot(id: artemID, name: "Artem Valiant", training: training, plan: [
            .init(skillID: 1, name: "Amarr Drone Specialization", level: 5, duration: hours(206)),
            .init(skillID: 2, name: "Fighters", level: 2, duration: hours(26)),
            .init(skillID: 3, name: "Fighter Hangar Management", level: 1, duration: minutes(220)),
        ])
    }

    /// Mira Quillfeather: her queue ends today, or — `stale` — the app has not seen her for
    /// three days, still training.
    static func mira(now: Date, stale: Bool = false) -> WidgetSnapshot.Pilot {
        if stale {
            return WidgetSnapshot.Pilot(id: miraID, name: "Mira Quillfeather", training: .init(
                fetchedAt: now.addingTimeInterval(-hours(73)),
                queue: queue(now: now, current: (name: "Large Hybrid Turret", level: 5, rank: 5, progress: 0.3, left: hours(218)), next: [])))
        }
        return WidgetSnapshot.Pilot(id: miraID, name: "Mira Quillfeather", training: .init(
            fetchedAt: now.addingTimeInterval(-35 * 60),
            queue: queue(now: now, current: (name: "Large Hybrid Turret", level: 4, rank: 5, progress: 0.4, left: minutes(184)), next: [
                ("Surgical Strike", 4, 3, minutes(128)),
            ])))
    }

    static func bram(now: Date) -> WidgetSnapshot.Pilot {
        WidgetSnapshot.Pilot(id: bramID, name: "Bram Ironvale", training: .init(
            fetchedAt: now.addingTimeInterval(-50 * 60), queue: [],
            idleSince: now.addingTimeInterval(-hours(52))))
    }

    // MARK: - Building

    private static func hours(_ value: Double) -> TimeInterval { value * 3600 }
    private static func minutes(_ value: Double) -> TimeInterval { value * 60 }

    /// The points a skill of `rank` holds at `level`, by the game's formula.
    private static func points(level: Int, rank: Int) -> Int {
        guard level > 0 else { return 0 }
        return Int((250 * Double(rank) * pow(32, Double(level - 1) / 2)).rounded())
    }

    /// A queue under way: the current entry `progress` into its level with `left` to go, the
    /// others one after another behind it.
    private static func queue(now: Date,
                              current: (name: String, level: Int, rank: Int, progress: Double, left: TimeInterval),
                              next: [(String, Int, Int, TimeInterval)]) -> [WidgetSnapshot.QueueEntry] {
        let total = current.left / (1 - current.progress)
        let start = now.addingTimeInterval(-total * current.progress)
        var finish = now.addingTimeInterval(current.left)
        var entries = [entry(current.name, level: current.level, rank: current.rank, start: start, finish: finish)]
        for (name, level, rank, duration) in next {
            let start = finish
            finish = start.addingTimeInterval(duration)
            entries.append(entry(name, level: level, rank: rank, start: start, finish: finish))
        }
        return entries
    }

    private static func entry(_ name: String, level: Int, rank: Int, start: Date, finish: Date) -> WidgetSnapshot.QueueEntry {
        let bottom = points(level: level - 1, rank: rank)
        let top = points(level: level, rank: rank)
        return WidgetSnapshot.QueueEntry(
            skillID: skillID(name), name: name, level: level,
            startDate: start, finishDate: finish,
            levelStartSkillPoints: bottom, levelEndSkillPoints: top,
            trainingStartSkillPoints: bottom, duration: finish.timeIntervalSince(start))
    }

    /// Not the game's id — nothing in the widget looks one up — but stable from one draw to the next.
    private static func skillID(_ name: String) -> Int64 {
        name.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int64($1.value)) % 1_000_000 }
    }

    private static func paused(_ name: String, level: Int, rank: Int, held: Double = 0,
                               duration: TimeInterval) -> WidgetSnapshot.QueueEntry {
        let bottom = points(level: level - 1, rank: rank)
        let top = points(level: level, rank: rank)
        return WidgetSnapshot.QueueEntry(
            skillID: skillID(name), name: name, level: level,
            startDate: nil, finishDate: nil,
            levelStartSkillPoints: bottom, levelEndSkillPoints: top,
            trainingStartSkillPoints: bottom + Int(Double(top - bottom) * held), duration: duration)
    }
}
