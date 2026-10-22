import SwiftUI
import TrainingKit

/// Where a skill level stands, as one glyph at the end of a row.
///
/// Trained is a green checkmark; the plan is a bookmark, filled when it covers the level and hollow
/// when it stops short. A level that is neither draws nothing.
struct PlanStatusMarker: View {
    let status: TrainingContext.PlanStatus

    var body: some View {
        switch status {
        case .trained:
            Image(systemName: "checkmark")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Color.hudOk)
                .accessibilityLabel("Trained")
        case .planned:
            Image(systemName: "bookmark.fill")
                .font(.system(size: 14))
                .foregroundStyle(Color.hudAccent)
                .accessibilityLabel("In the training plan")
        case let .partiallyPlanned(through):
            // The level the plan actually reaches, spelled out.
            HStack(spacing: 3) {
                Image(systemName: "bookmark")
                    .font(.system(size: 12, weight: .semibold))
                Text(SkillLevel.roman(through))
                    .font(HUDFont.mono(11, weight: .regular, relativeTo: .caption))
            }
            .foregroundStyle(Color.hudAccent)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("In the training plan through level \(SkillLevel.roman(through))")
        case .absent:
            EmptyView()
        }
    }
}

/// What a plannable row shows at its end: the plan marker, or — when the level is neither
/// trained nor planned — a "+ Plan" affordance saying what a tap on the row does.
struct PlanRowAccessory: View {
    let status: TrainingContext.PlanStatus

    var body: some View {
        if status == .absent {
            HStack(spacing: 4) {
                Image(systemName: "plus.circle")
                    .font(.system(size: 15))
                Text("Plan")
                    .font(.hudLabel)
                    .tracking(1)
                    .textCase(.uppercase)
            }
            .foregroundStyle(Color.hudAccent)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Add to the training plan")
        } else {
            PlanStatusMarker(status: status)
        }
    }
}

/// The row that puts a set of skills into the training plan, with what training them costs.
///
/// Once everything it would add is in the plan it stays on screen, disabled.
struct AddToPlanRow: View {
    /// Training time for the whole set, including what is already planned.
    let time: TimeInterval
    /// Everything this row would add is in the plan already.
    let isPlanned: Bool
    let action: () -> Void

    /// Toggled by the tap, and nothing else. The haptic lives on this view: a modifier on a
    /// `Section` applies to each row and would fire once per skill.
    @State private var tapped = false

    var body: some View {
        Button {
            tapped.toggle()
            action()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: isPlanned ? "bookmark.fill" : "plus.circle")
                    .font(.system(size: 16))
                Text(isPlanned ? "In Training Plan" : "Add to Training Plan")
                    .font(.hudTileTitle)
                Spacer()
                Text(TrainingTime.string(time))
                    .font(.hudCaption)
                    .foregroundStyle(Color.hudInkMuted)
            }
            .foregroundStyle(isPlanned ? Color.hudInkMuted : Color.hudAccent)
            .hudRow()
        }
        .hudRowButton()
        .disabled(isPlanned)
        .sensoryFeedback(.success, trigger: tapped)
    }
}
