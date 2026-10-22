import LiteRow
import LiteRowUI
import SDEKit
import SwiftUI
import TrainingKit
import TrainingTimeline

/// A direct requirement as the type `TrainingKit` understands; the tree is expanded by
/// `TrainingContext.queue(forRequirements:)`.
extension RequiredSkillRow {
    var requirement: SkillCatalog.Requirement {
        SkillCatalog.Requirement(skillID: id, level: level)
    }
}

/// The skills an item asks for as a tree: the direct requirements and, under each, the
/// prerequisites the character would have to train first. Draws without a character; only times
/// and checkmarks need a pilot.
struct RequiredSkillsSection: View {
    @Environment(\.trainingContext) private var trainingContext

    @LiteQuery private var requirements: [RequiredSkillRow]

    init(typeID: TypeID) {
        _requirements = LiteQuery(SDEBrowser.requiredSkills(of: typeID))
    }

    var body: some View {
        // No heading for an item without requirements.
        if !requirements.isEmpty {
            RequiredSkillsList(
                rows: rows,
                queue: trainingContext?.queue(forRequirements: directRequirements)
            )
        }
    }

    private var directRequirements: [SkillCatalog.Requirement] {
        requirements.map(\.requirement)
    }

    /// The expanded tree flattened in reading order: every skill once, at the highest level asked
    /// for, with the depth it was first reached at. `SkillCatalog.expand(_:)` supplies the levels but
    /// lists prerequisites first and carries no depth, so order and indentation come from walking
    /// `prerequisites` here, parent before children.
    private var rows: [RequiredSkillTreeRow] {
        let direct = directRequirements
        // Without a catalog the direct requirements are shown flat.
        guard let catalog = trainingContext?.catalog else {
            return direct.map { RequiredSkillTreeRow(skillID: $0.skillID, level: $0.level, depth: 0) }
        }

        let levels = Dictionary(
            catalog.expand(direct).map { ($0.skillID, $0.level) },
            uniquingKeysWith: { first, _ in first }
        )

        var rows: [RequiredSkillTreeRow] = []
        // Cycle guard and deduplication: a skill already on screen is not expanded again.
        var visited: Set<TypeID> = []

        func visit(_ requirement: SkillCatalog.Requirement, depth: Int) {
            let id = requirement.skillID
            guard visited.insert(id).inserted else { return }
            rows.append(
                RequiredSkillTreeRow(skillID: id, level: levels[id] ?? requirement.level, depth: depth)
            )
            for prerequisite in catalog[id]?.prerequisites ?? [] {
                visit(prerequisite, depth: depth + 1)
            }
        }

        for requirement in direct {
            visit(requirement, depth: 0)
        }
        return rows
    }
}

/// One line of the tree: which skill, at what level, how far in.
private struct RequiredSkillTreeRow: Identifiable, Hashable {
    var id: TypeID { skillID }
    var skillID: TypeID
    var level: Int
    var depth: Int
}

/// The rows once the tree is known; a separate view because `@LiteQuery` builds its query in
/// `init` and the skills to name come from the expansion.
private struct RequiredSkillsList: View {
    let rows: [RequiredSkillTreeRow]
    /// `nil` when there is no character: the tree still draws, without times or checkmarks.
    let queue: TrainingQueue?

    @Environment(\.trainingContext) private var trainingContext
    @Environment(AccountStore.self) private var accounts

    @LiteQuery private var names: [TypeNameRow]

    init(rows: [RequiredSkillTreeRow], queue: TrainingQueue?) {
        self.rows = rows
        self.queue = queue
        _names = LiteQuery(SDEBrowser.typeNames(of: rows.map(\.skillID)))
    }

    var body: some View {
        HUDListSection("Required Skills") {
            ForEach(rows) { row in
                NavigationLink(value: DatabaseRoute.type(row.skillID)) {
                    label(for: row)
                }
                .hudRowButton()
            }
            // Only with a character: `queue` is `nil` without a pilot, and an empty one means nothing to plan.
            if let queue, !queue.isEmpty {
                let unplanned = trainingContext?.unplanned(in: queue) ?? []
                AddToPlanRow(time: queue.totalTime, isPlanned: unplanned.isEmpty) {
                    accounts.currentPlan?.add(unplanned)
                }
            }
        }
    }

    private func label(for row: RequiredSkillTreeRow) -> some View {
        HStack(spacing: 10) {
            if row.depth > 0 {
                TreeElbow()
            }
            HUDItemIcon(typeID: row.skillID, size: 28)
            // The name is empty until the query returns.
            hudSkillText(names(of: row.skillID), level: row.level)
                .font(.hudBody)
            Spacer(minLength: 4)
            trailing(for: row)
        }
        .padding(.leading, CGFloat(max(row.depth - 1, 0)) * 18)
        .hudRow()
    }

    /// Time and plan marker. `planStatus` is `nil` without a character.
    @ViewBuilder
    private func trailing(for row: RequiredSkillTreeRow) -> some View {
        if let status = trainingContext?.planStatus(ofSkill: row.skillID, level: row.level) {
            HStack(spacing: 6) {
                if status != .trained, let time = trainingTime(of: row) {
                    Text(TrainingTime.string(time))
                        .font(.hudCaption)
                        .foregroundStyle(Color.hudInkMuted)
                }
                PlanStatusMarker(status: status)
            }
        }
    }

    /// Time to get this skill to this level: every level the character still misses, summed.
    /// `TrainingQueue.time(forSkill:level:)` returns `nil` for trained levels. `nil` when no level of
    /// the skill is in the queue.
    private func trainingTime(of row: RequiredSkillTreeRow) -> TimeInterval? {
        guard let queue, row.level >= 1 else { return nil }
        let times = (1...row.level).compactMap { queue.time(forSkill: row.skillID, level: $0) }
        guard !times.isEmpty else { return nil }
        return times.reduce(0, +)
    }

    private func names(of skill: TypeID) -> String {
        nameByID[skill] ?? ""
    }

    private var nameByID: [TypeID: String] {
        Dictionary(names.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
    }
}

private struct TreeElbow: View {
    var body: some View {
        Path { path in
            path.move(to: CGPoint(x: 0.5, y: 0))
            path.addLine(to: CGPoint(x: 0.5, y: 14))
            path.addLine(to: CGPoint(x: 10, y: 14))
        }
        .stroke(Color.hudLineLeader, lineWidth: 1)
        .frame(width: 10, height: 14)
        .offset(y: -5)
        .accessibilityHidden(true)
    }
}

/// Skill levels as Roman numerals. Internal because `TrainingQueueView` reuses it. Zero is the
/// digit, as there is no Roman zero.
enum SkillLevel {
    /// The table is `SkillLevelNumeral`'s, shared with the widget extension.
    static func roman(_ level: Int) -> String {
        SkillLevelNumeral.roman(level)
    }
}
