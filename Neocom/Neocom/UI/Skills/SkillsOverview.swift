import SDEKit
import SwiftUI
import TrainingKit

/// The Skills section's data: every published skill with its standing for the pilot, grouped the
/// way the SDE files them, with the counts of each group and of the whole set.
///
/// Built from in-memory values only, so it costs a pass over ~500 skills and makes no request.
struct SkillsOverview {
    struct Skill: Identifiable {
        var row: SkillListRow
        var standing: SkillStanding
        var rank: Double
        var id: TypeID { row.id }
    }

    struct Group: Identifiable {
        var id: GroupID
        var name: String
        var skills: [Skill]
        var tally: SkillTally
    }

    let groups: [Group]
    let tally: SkillTally
    /// Every skill's name, for spelling out the prerequisites a locked skill is missing.
    let names: [TypeID: String]

    /// `rows` arrive ordered by group and then by name (`SkillBrowser.skills()`); that order is
    /// kept.
    init(rows: [SkillListRow], context: TrainingContext, pilot: Pilot) {
        var order: [GroupID] = []
        var byGroup: [GroupID: [Skill]] = [:]
        var names: [TypeID: String] = [:]
        for row in rows {
            names[row.id] = row.name
            let standing = SkillStanding(skill: row.id, pilot: pilot, catalog: context.catalog,
                                         plannedLevel: context.plannedLevels[row.id] ?? 0)
            if byGroup[row.groupID] == nil { order.append(row.groupID) }
            byGroup[row.groupID, default: []].append(
                Skill(row: row, standing: standing, rank: context.catalog[row.id]?.rank ?? 1)
            )
        }
        groups = order.map { id in
            let skills = byGroup[id] ?? []
            return Group(id: id, name: skills.first?.row.groupName ?? "", skills: skills,
                         tally: SkillTally(skills.map(\.standing)))
        }
        tally = SkillTally(groups.flatMap { $0.skills.map(\.standing) })
        self.names = names
    }

    func group(_ id: GroupID) -> Group? {
        groups.first { $0.id == id }
    }

    /// The groups again, narrowed to the skills `filter` and `search` let through. Groups left
    /// with nothing are dropped.
    ///
    /// - Parameter byRank: orders each group by rank, cheapest first; otherwise the alphabetical
    ///   order is kept.
    func sections(filter: SkillFilter, search: String, byRank: Bool) -> [Group] {
        let query = search.trimmingCharacters(in: .whitespaces)
        return groups.compactMap { group in
            var skills = group.skills.filter { skill in
                filter.includes(skill.standing.state)
                    && (query.isEmpty || skill.row.name.localizedStandardContains(query))
            }
            guard !skills.isEmpty else { return nil }
            if byRank {
                // Stable on the alphabetical order the rows came in.
                skills = skills.enumerated()
                    .sorted { ($0.element.rank, $0.offset) < ($1.element.rank, $1.offset) }
                    .map(\.element)
            }
            return Group(id: group.id, name: group.name, skills: skills, tally: SkillTally(skills.map(\.standing)))
        }
    }
}

/// The segmented filter of the Skills section. The four states partition every skill, so the
/// three narrowed views are three of them and only `all` shows the locked ones.
enum SkillFilter: Hashable, CaseIterable {
    case all
    case trained
    case canTrain
    case needBook

    var title: LocalizedStringKey {
        switch self {
        case .all: "All"
        case .trained: "Trained"
        case .canTrain: "Can train"
        case .needBook: "Need book"
        }
    }

    /// The state a narrowed view lists, `nil` for `all`.
    var state: SkillStanding.State? {
        switch self {
        case .all: nil
        case .trained: .trainedToV
        case .canTrain: .canTrain
        case .needBook: .needsBook
        }
    }

    func includes(_ state: SkillStanding.State) -> Bool {
        self.state.map { $0 == state } ?? true
    }
}

extension SkillStanding.State {
    /// The HUD's glyph for this state.
    var icon: HUDSkillStateIcon.State {
        switch self {
        case .trainedToV: .trainedToV
        case .canTrain: .canTrain
        case .needsBook: .needsBook
        case .locked: .locked
        }
    }
}

/// Skill points the way the section prints them: `176.8M`, `15.89M`.
enum SkillPointsFormat {
    static func compact(_ value: Int64) -> String {
        Double(value).formatted(.number.notation(.compactName).precision(.significantDigits(1...4)))
    }
}
