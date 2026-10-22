import SwiftUI

/// What the symbols and the bar segments of the Skills screens mean. Hidden by default; the
/// (?) button in the navigation bar of every Skills screen opens it.
struct SkillsLegendSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            HUDList(isTransparent: true) {
                HUDListSection("Skill State") {
                    ForEach(HUDSkillStateIcon.State.allCases, id: \.self) { state in
                        item(state.title, description: description(of: state)) {
                            HUDSkillStateIcon(state: state)
                        }
                    }
                }
                HUDListSection("Level Bar") {
                    item(Text("Trained"), description: Text("A level you already have.")) {
                        HUDLevelSwatch(segment: .trained)
                    }
                    item(Text("Training · paused"),
                         description: Text("The level training in game. Hatched while the queue is paused.")) {
                        HUDLevelSwatch(segment: .training, width: 12)
                        HUDLevelSwatch(segment: .paused, width: 12)
                    }
                    item(Text("In game queue"), description: Text("Queued in game after the training level.")) {
                        HUDLevelSwatch(segment: .queued)
                    }
                    item(Text("In plan"),
                         description: Text("In the Neocom training plan, not yet in the game queue. The bookmark at the row end marks it too.")) {
                        HUDLevelSwatch(segment: .planned)
                        Image(systemName: "bookmark.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.hudAccent)
                    }
                }
            }
            .navigationTitle("Legend")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", systemImage: "xmark") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func description(of state: HUDSkillStateIcon.State) -> Text {
        switch state {
        case .trainedToV: Text("Every level is trained. Nothing left to do.")
        case .canTrain: Text("Injected and prerequisites met: add the next level to the queue.")
        case .needsBook: Text("Prerequisites met: buy the book and inject it in game.")
        case .locked: Text("Prerequisites missing. The row says which ones.")
        }
    }

    private func item<Mark: View>(_ title: Text, description: Text, @ViewBuilder mark: () -> Mark) -> some View {
        HStack(spacing: 14) {
            HStack(spacing: 3) { mark() }
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 2) {
                title
                    .font(.headline)
                description
                    .font(.subheadline)
                    .foregroundStyle(Color.hudInkBodyMuted)
            }
            Spacer(minLength: 0)
        }
        .hudRow(HUDRowStyle(background: HUDRowStyle.sheet.background,
                            border: HUDRowStyle.sheet.border,
                            divider: HUDRowStyle.sheet.divider,
                            minHeight: 0, verticalPadding: 11))
        .accessibilityElement(children: .combine)
    }
}

/// The (?) button that opens the legend, for the navigation bar of every Skills screen.
struct SkillsLegendButton: ToolbarContent {
    @Binding var isPresented: Bool

    var body: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button("Legend", systemImage: "questionmark.circle") { isPresented = true }
        }
    }
}

#Preview {
    Color.hudBg
        .sheet(isPresented: .constant(true)) {
            SkillsLegendSheet()
        }
}
