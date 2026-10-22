import LiteRow
import LiteRowUI
import SDEKit
import SwiftUI
import TrainingKit

/// The Training Queue section: what ESI says the character is training, and the local plan for what
/// comes after.
///
/// Wrapped in `SDESectionView`: skill names live in the SDE.
struct TrainingQueueView: View {
    var body: some View {
        SDESectionView { _ in
            TrainingQueueBody()
        }
        .hudScreen()
        .navigationTitle("Training Queue")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Reads the pilot's ESI queue and the local plan out of the environment and hands the fixed lists
/// to `TrainingQueueList`: `@LiteQuery` builds its query in `init`, so the skills to name must be
/// known when the child is created.
private struct TrainingQueueBody: View {
    @Environment(\.trainingContext) private var trainingContext
    @Environment(AccountStore.self) private var accounts

    var body: some View {
        let planEntries = accounts.currentPlan?.entries ?? []
        return TrainingQueueList(
            gameQueue: trainingContext?.pilot?.queue ?? [],
            planEntries: planEntries,
            planQueue: trainingContext?.queue(forRequirements: planEntries),
            remapStatus: accounts.currentSheet?.snapshot.flatMap { RemapAvailability(snapshot: $0) },
            plan: accounts.currentPlan
        )
    }
}

/// The two sections, once both queues and the names of everything in them are known.
private struct TrainingQueueList: View {
    let gameQueue: [CharacterSnapshot.QueueEntry]
    let planEntries: [SkillCatalog.Requirement]
    /// `nil` when there is no pilot to compute times against; the plan lists its entries without
    /// durations.
    let planQueue: TrainingQueue?
    /// `nil` before the character is loaded, or when `/attributes` said nothing about remaps.
    let remapStatus: RemapAvailability?
    /// `nil` only when there is no SwiftData context (previews, tests).
    let plan: TrainingPlanStore?

    @Environment(AccountStore.self) private var accounts

    @LiteQuery private var names: [TypeNameRow]

    @State private var isConfirmingClear = false

    init(gameQueue: [CharacterSnapshot.QueueEntry],
         planEntries: [SkillCatalog.Requirement],
         planQueue: TrainingQueue?,
         remapStatus: RemapAvailability?,
         plan: TrainingPlanStore?) {
        self.gameQueue = gameQueue
        self.planEntries = planEntries
        self.planQueue = planQueue
        self.remapStatus = remapStatus
        self.plan = plan
        let skillIDs = Set(gameQueue.map(\.skillID)).union(planEntries.map(\.skillID))
        _names = LiteQuery(SDEBrowser.typeNames(of: Array(skillIDs)))
    }

    var body: some View {
        // The screen's one clock.
        let now = Date.now
        return HUDList {
            gameSections
            planSections
            if let planQueue, !planEntries.isEmpty {
                TrainingRemapSection(queue: planQueue, availability: remapStatus, now: now)
            }
        }
        .refreshableCommand {
            await accounts.currentSheet?.refresh()
        }
        .task(id: accounts.currentAccountID) {
            await accounts.currentSheet?.ensureFresh()
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    isConfirmingClear = true
                } label: {
                    Label("Clear Plan", systemImage: "trash")
                }
                .disabled(plan == nil || planEntries.isEmpty)
            }
        }
        .confirmationDialog(Text("Clear Training Plan"), isPresented: $isConfirmingClear,
                            titleVisibility: .visible) {
            Button("Clear Plan", role: .destructive) {
                plan?.clear()
            }
        } message: {
            Text("All \(planEntries.count) skill levels will be removed from the plan. The in-game queue is not affected.")
        }
    }

    // MARK: - In Game

    /// What ESI's `/skillqueue` reports, read-only. The skill in training gets a panel of its own;
    /// the rest of the queue is a list under it.
    @ViewBuilder
    private var gameSections: some View {
        let header = HUDSectionHeader(Text("In Game · \(gameQueue.count) Skills"))
        if let current = gameQueue.first {
            // One titled section: the panel leads it, the queued entries follow as a card
            // `headerSpacing` under it.
            HUDListSection {
                NavigationLink(value: DatabaseRoute.type(current.skillID)) {
                    currentPanel(for: current)
                }
                .buttonStyle(.hudTile)
                .hudTypeContextMenu(typeID: current.skillID, name: name(of: current.skillID))
                .hudLeadingBlock(hasCardBelow: gameQueue.count > 1)
                ForEach(gameQueue.dropFirst(), id: \.position) { entry in
                    NavigationLink(value: DatabaseRoute.type(entry.skillID)) {
                        gameRow(for: entry)
                    }
                    .hudRowButton()
                    .hudTypeContextMenu(typeID: entry.skillID, name: name(of: entry.skillID))
                }
            } header: {
                header
            }
        } else {
            Section {
                HUDEmptyPanel(title: Text("Nothing in Training"),
                              message: Text("The queue in game is empty. Start training from the EVE client."))
                    .hudBareRow()
            } header: {
                header.hudListHeader()
            }
        }
    }

    /// The skill the game is working on, as the panel the whole screen is about.
    ///
    /// No dates is how ESI reports a paused entry, not a broken one; the panel turns `warn` and
    /// says how to fix it.
    private func currentPanel(for entry: CharacterSnapshot.QueueEntry) -> some View {
        let isPaused = entry.finishDate == nil
        return HUDPanel(tone: isPaused ? .warn : .normal) {
            HUDPanelHeader(title: Text("Slot 01")) {
                if isPaused {
                    HUDStatusChip(text: Text("Paused"), color: .hudWarn, mark: .symbol("pause.fill"))
                } else {
                    HUDStatusChip(text: Text("Training"), color: .hudAccent, mark: .dot)
                }
            }

            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    HUDItemIcon(typeID: entry.skillID, size: 40)
                    Text(name(of: entry.skillID))
                        .font(HUDFont.display(22, weight: .bold, relativeTo: .title2))
                        .tracking(0.5)
                        .textCase(.uppercase)
                        .lineLimit(2)
                    Spacer(minLength: 4)
                    Text(SkillLevel.roman(entry.finishedLevel))
                        .font(HUDFont.display(30, weight: .bold, relativeTo: .title))
                        .foregroundStyle(Color.hudAccent)
                }
                HUDLevelBar(trained: entry.finishedLevel - 1, training: entry.finishedLevel, paused: isPaused)
                HStack {
                    Text("LVL \(SkillLevel.roman(entry.finishedLevel - 1)) → \(SkillLevel.roman(entry.finishedLevel))")
                    Spacer()
                    if let finishDate = entry.finishDate {
                        Text(finishDate, format: .dateTime.month().day().hour().minute())
                    } else {
                        Text("No finish date")
                    }
                }
                .font(.hudCaption)
                .textCase(.uppercase)
                .foregroundStyle(Color.hudInkMuted)
            }
            .padding(HUDMetrics.gutter)

            if isPaused {
                HUDWarnNote("The queue is paused in game. Resume it from the EVE client.")
            }
        }
        .multilineTextAlignment(.leading)
    }

    private func gameRow(for entry: CharacterSnapshot.QueueEntry) -> some View {
        HStack(spacing: 12) {
            HUDItemIcon(typeID: entry.skillID, size: 28)
            hudSkillText(name(of: entry.skillID), level: entry.finishedLevel)
                .font(.hudBody)
            Spacer(minLength: 4)
            if let finishDate = entry.finishDate {
                Text(finishDate, format: .dateTime.month().day().hour().minute())
                    .font(.hudCaption)
                    .foregroundStyle(Color.hudInkMuted)
            }
            HUDChevron()
        }
        .hudRow()
    }

    // MARK: - Training Plan

    /// The local plan. Never what EVE is training: nothing added here reaches the game.
    @ViewBuilder
    private var planSections: some View {
        if planEntries.isEmpty {
            Section {
                HUDEmptyPanel(title: Text("No Skills Planned"),
                              message: Text("Add skills from an item's page in Database. They line up after the in‑game queue, each with its own training time.")) {
                    NavigationLink(value: MainMenuSection.database) {
                        Label("Open Database", systemImage: MainMenuSection.database.systemImage)
                    }
                    .hudProminentButton()
                }
                .hudBareRow()
            } header: {
                HUDSectionHeader(Text("Training Plan")).hudListHeader()
            }
        } else {
            HUDListSection("Training Plan") {
                ForEach(planEntries, id: \.self) { entry in
                    NavigationLink(value: DatabaseRoute.type(entry.skillID)) {
                        planRow(for: entry)
                    }
                    .hudRowButton()
                    .hudRowActions(inContextMenu: false, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            removeFromPlan(entry)
                        } label: {
                            Label("Remove", systemImage: "trash")
                        }
                    }
                    .contextMenu {
                        HUDTypeCopyButtons(typeID: entry.skillID, name: name(of: entry.skillID))
                        Button("Remove from Plan", systemImage: "trash", role: .destructive) {
                            removeFromPlan(entry)
                        }
                    }
                }
            } footer: {
                planFooter
            }
        }
    }

    private func planRow(for entry: SkillCatalog.Requirement) -> some View {
        HStack(spacing: 12) {
            HUDItemIcon(typeID: entry.skillID, size: 28)
            hudSkillText(name(of: entry.skillID), level: entry.level)
                .font(.hudBody)
            Spacer(minLength: 4)
            if let time = planQueue?.time(forSkill: entry.skillID, level: entry.level) {
                Text(TrainingTime.string(time))
                    .font(.hudCaption)
                    .foregroundStyle(Color.hudInkMuted)
            }
            HUDChevron()
        }
        .hudRow()
    }

    @ViewBuilder
    private var planFooter: some View {
        // Nothing to total without a pilot, or once every entry is already trained.
        if let planQueue, !planQueue.isEmpty {
            HUDFootnote(Text("Total: \(TrainingTime.string(planQueue.totalTime)). Touch and hold a skill to remove it."))
        } else {
            HUDFootnote("Touch and hold a skill to remove it.")
        }
    }

    /// Drops the row's level and every higher level of the skill: a plan is trained low to high.
    /// Lower levels are kept.
    private func removeFromPlan(_ entry: SkillCatalog.Requirement) {
        plan?.trim(skill: entry.skillID, toLevel: entry.level - 1)
    }

    private func name(of skill: TypeID) -> String {
        nameByID[skill] ?? ""
    }

    private var nameByID: [TypeID: String] {
        Dictionary(names.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
    }
}

#Preview {
    NavigationStack {
        TrainingQueueView()
    }
    .environment(AccountStore())
    .environment(SDEStore())
}
