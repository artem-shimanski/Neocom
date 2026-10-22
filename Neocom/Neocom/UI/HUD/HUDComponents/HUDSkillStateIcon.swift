import SwiftUI

/// Where a skill stands, as one SF Symbol whose colour is the state: trained to V in `ok`, can
/// train now in the accent, needs a skillbook in `warn`, locked in `ink-faint`.
///
/// The same glyph heads a skill's row (20pt), counts a group's skills (14pt, in a
/// `HUDCountChip`) and explains itself in the Skills legend.
struct HUDSkillStateIcon: View {
    enum State: Hashable, CaseIterable {
        case trainedToV
        case canTrain
        case needsBook
        case locked
    }

    let state: State
    var size: CGFloat = 20

    var body: some View {
        Image(systemName: state.systemImage)
            .font(.system(size: size * 0.9, weight: .medium))
            .foregroundStyle(state.color)
            .frame(width: size, height: size)
            .accessibilityLabel(state.title)
    }
}

extension HUDSkillStateIcon.State {
    var systemImage: String {
        switch self {
        case .trainedToV: "checkmark.circle.fill"
        case .canTrain: "arrow.up.circle"
        case .needsBook: "book.closed.fill"
        case .locked: "lock.fill"
        }
    }

    var color: Color {
        switch self {
        case .trainedToV: .hudOk
        case .canTrain: .hudAccent
        case .needsBook: .hudWarn
        case .locked: .hudInkFaint
        }
    }

    var title: Text {
        switch self {
        case .trainedToV: Text("Trained to V")
        case .canTrain: Text("Can train now")
        case .needsBook: Text("Needs a skillbook")
        case .locked: Text("Locked")
        }
    }
}

#Preview("Skill state icon") {
    HUDList {
        HUDListSection {
            ForEach(HUDSkillStateIcon.State.allCases, id: \.self) { state in
                HStack(spacing: 12) {
                    HUDSkillStateIcon(state: state)
                    state.title.font(.hudBody)
                    Spacer()
                    HUDSkillStateIcon(state: state, size: 14)
                }
                .hudRow(HUDRowStyle(minHeight: 0, verticalPadding: 10))
            }
        }
    }
}
