import SDEKit
import SwiftUI
import TrainingKit

/// One skill: its state, name and rank, the level bar, and the plan bookmark at the end. A
/// locked skill says what it still needs instead of its rank.
/// Leads to the skill's own screen in Database.
struct SkillRowView: View {
    let skill: SkillsOverview.Skill
    /// Every skill's name, for the prerequisites of a locked one.
    let names: [TypeID: String]

    private static let style = HUDRowStyle(horizontalPadding: 14, minHeight: 56)

    var body: some View {
        let standing = skill.standing
        NavigationLink(value: DatabaseRoute.type(skill.id)) {
            HStack(spacing: 12) {
                HUDSkillStateIcon(state: standing.state.icon)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: skill.row.name)
                        .font(HUDFont.display(15, weight: .semibold, relativeTo: .body))
                        .foregroundStyle(standing.state == .locked ? Color.hudInkMuted : Color.hudInk)
                    subtitle
                        .font(HUDFont.mono(11, weight: .regular, relativeTo: .caption))
                        .textCase(.uppercase)
                        .foregroundStyle(Color.hudInkMuted)
                }
                .multilineTextAlignment(.leading)
                Spacer(minLength: 4)
                if standing.showsLevelBar {
                    levelBar(standing)
                        .frame(width: 64)
                }
                // A column of its own, drawn or not, so the bars of a list line up.
                SwiftUI.Group {
                    if standing.isPlanned {
                        Image(systemName: "bookmark.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.hudAccent)
                            .accessibilityLabel("In the training plan")
                    }
                }
                .frame(width: 12)
            }
            .hudRow(Self.style)
        }
        .hudRowButton(Self.style)
        .hudTypeContextMenu(typeID: skill.id, name: skill.row.name)
    }

    private var subtitle: Text {
        let standing = skill.standing
        if standing.state == .locked {
            let missing = standing.missing
                .map { "\(names[$0.skillID] ?? "") \(SkillLevel.roman($0.level))" }
                .joined(separator: ", ")
            return Text("Needs \(missing)")
        }
        let rank = skill.rank.formatted(.number.precision(.fractionLength(0...1)))
        if standing.level > 0 {
            return Text("Rank ×\(rank) · Level \(SkillLevel.roman(standing.level))")
        }
        if standing.isInjected {
            return Text("Rank ×\(rank) · Not started")
        }
        return Text("Rank ×\(rank)")
    }

    private func levelBar(_ standing: SkillStanding) -> HUDLevelBar {
        var training: Int?
        var paused = false
        var queued: Int?
        var planned: Int?
        for (index, mark) in standing.marks.enumerated() {
            let level = index + 1
            switch mark {
            case let .training(isPaused):
                training = level
                paused = isPaused
            case .queued: queued = level
            case .planned: planned = level
            case .trained, .empty: break
            }
        }
        return HUDLevelBar(trained: standing.level, training: training, paused: paused,
                           queued: queued, planned: planned, height: 8, spacing: 2)
    }
}

/// The per-state counts after a group's figures: at V, can train, needs a book, locked, and —
/// on the root only — in the game queue and in the plan. A state with none is left out.
struct SkillCountChips: View {
    let tally: SkillTally
    var includesQueueAndPlan = true

    var body: some View {
        HStack(spacing: 10) {
            ForEach(SkillStanding.State.allCases, id: \.self) { state in
                let count = tally.count(of: state)
                if count > 0 {
                    HUDCountChip(count: count, accessibilityLabel: state.icon.title) {
                        HUDSkillStateIcon(state: state.icon, size: 14)
                    }
                }
            }
            if includesQueueAndPlan {
                if tally.queued > 0 {
                    HUDCountChip(count: tally.queued, accessibilityLabel: Text("In the game queue")) {
                        HUDLevelSwatch(segment: queueSegment, width: 10)
                    }
                }
                if tally.planned > 0 {
                    HUDCountChip(count: tally.planned, accessibilityLabel: Text("In the training plan")) {
                        Image(systemName: "bookmark.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.hudAccent)
                    }
                }
            }
        }
    }

    /// The queue's chip is the segment the bar would draw: the level in training when it is in this
    /// group, the outline of a queued one otherwise.
    private var queueSegment: HUDLevelSegment {
        switch tally.queueMark {
        case .training(paused: true): .paused
        case .training(paused: false): .training
        default: .queued
        }
    }
}

/// `21 / 32 · 15.89M SP` — injected out of all, and the points in them.
func skillFigures(_ tally: SkillTally, skillsWord: Bool = false) -> Text {
    let points = tally.skillPoints > 0 ? SkillPointsFormat.compact(tally.skillPoints) : "0"
    return skillsWord
        ? Text("\(tally.injected) / \(tally.total) skills · \(points) SP")
        : Text("\(tally.injected) / \(tally.total) · \(points) SP")
}

/// One group on the root: its name, the figures and the counts under it.
struct SkillGroupRowView: View {
    let group: SkillsOverview.Group

    private static let style = HUDRowStyle(minHeight: 60, verticalPadding: 10)

    var body: some View {
        NavigationLink(value: SkillsRoute.group(group.id)) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(verbatim: group.name)
                        .font(.hudBody)
                    // On one line while it fits, the counts under the figures otherwise.
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 10) {
                            figures
                            Spacer(minLength: 0)
                            SkillCountChips(tally: group.tally)
                        }
                        VStack(alignment: .leading, spacing: 5) {
                            figures
                            SkillCountChips(tally: group.tally)
                        }
                    }
                }
                HUDChevron()
            }
            .hudRow(Self.style)
        }
        .hudRowButton(Self.style)
    }

    private var figures: some View {
        skillFigures(group.tally)
            .font(.hudLabel)
            .foregroundStyle(Color.hudInkMuted)
            .lineLimit(1)
            .fixedSize()
    }
}

/// Where the Skills section pushes inside its own stack.
enum SkillsRoute: Hashable {
    case group(GroupID)
}
