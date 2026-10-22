import SDEKit
import SwiftUI
import TrainingKit

/// The five levels of a skill as rows that can be planned. Exists only with a pilot and for a
/// type the catalog knows as a skill. Times are cumulative and include the skill's prerequisites.
struct SkillLevelsSection: View {
    let skillID: TypeID

    @Environment(\.trainingContext) private var trainingContext
    @Environment(AccountStore.self) private var accounts

    var body: some View {
        // `queue(forSkill:level:)` is `nil` without a pilot, as for every other plan control.
        if let context = trainingContext,
           context.catalog.isSkill(skillID),
           let queue = context.queue(forSkill: skillID, level: Self.maximumLevel) {
            HUDListSection("Training") {
                ForEach(1...Self.maximumLevel, id: \.self) { level in
                    SkillLevelRow(
                        level: level,
                        status: context.planStatus(ofSkill: skillID, level: level) ?? .absent,
                        time: time(through: level, in: queue),
                        inGame: context.pilot?.queue.first { $0.skillID == skillID && $0.finishedLevel == level },
                        canLower: accounts.currentPlan?.contains(skill: skillID, level: level + 1) ?? false
                    ) {
                        if accounts.currentPlan?.contains(skill: skillID, level: level + 1) == true {
                            // A higher level is planned: tapping a lower one cuts the plan back to it.
                            accounts.currentPlan?.trim(skill: skillID, toLevel: level)
                        } else {
                            accounts.currentPlan?.add(requirements(through: level, in: queue))
                        }
                    }
                }
            }
        }
    }

    private static let maximumLevel = 5

    /// Everything still missing on the way to `level`: the skill's own levels up to it plus every
    /// prerequisite, in training order. Prerequisites belong to every level, so only the skill's own
    /// rows are cut off at `level`.
    private func items(through level: Int, in queue: TrainingQueue) -> [TrainingQueue.Item] {
        queue.items.filter { $0.skillID != skillID || $0.targetLevel <= level }
    }

    private func requirements(through level: Int, in queue: TrainingQueue) -> [SkillCatalog.Requirement] {
        items(through: level, in: queue).map {
            SkillCatalog.Requirement(skillID: $0.skillID, level: $0.targetLevel)
        }
    }

    /// `nil` when nothing is left to train.
    private func time(through level: Int, in queue: TrainingQueue) -> TimeInterval? {
        let times = items(through: level, in: queue).map(\.trainingTime)
        guard !times.isEmpty else { return nil }
        return times.reduce(0, +)
    }
}

/// One level: its cost, its state, and a tap that plans everything up to it. A view of its own
/// so the haptic applies to one row.
private struct SkillLevelRow: View {
    let level: Int
    let status: TrainingContext.PlanStatus
    /// `nil` once nothing is left to train.
    let time: TimeInterval?
    /// The game's queue entry for exactly this level, when the game is training it.
    let inGame: CharacterSnapshot.QueueEntry?
    /// A higher level of this skill is planned, so a tap lowers the plan to this level.
    let canLower: Bool
    let action: () -> Void

    @State private var tapped = false

    var body: some View {
        Button {
            tapped.toggle()
            action()
        } label: {
            HStack(spacing: 10) {
                Text("Level \(Text(verbatim: SkillLevel.roman(level)).font(HUDFont.mono(15, weight: .regular, relativeTo: .body)).foregroundStyle(Color.hudInkMuted))")
                    .font(.hudBody)
                Spacer()
                if let inGame {
                    // Paused is stated, as the time would otherwise read as a running countdown.
                    if inGame.finishDate == nil {
                        HUDStatusChip(text: Text("In Game · Paused"), color: .hudWarn, mark: .symbol("pause.fill"))
                    } else {
                        HUDStatusChip(text: Text("In Game"), color: .hudAccent, mark: .dot)
                    }
                } else if let time {
                    Text(TrainingTime.string(time))
                        .font(.hudCaption)
                        .foregroundStyle(Color.hudInkMuted)
                }
                if inGame == nil || status != .absent {
                    PlanRowAccessory(status: status)
                }
            }
            .hudRow()
        }
        .hudRowButton()
        // Trained, or planned in full.
        .disabled((status == .trained || status == .planned) && !canLower)
        .sensoryFeedback(.success, trigger: tapped)
    }
}
