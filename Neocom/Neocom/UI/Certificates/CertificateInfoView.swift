import LiteRow
import LiteRowUI
import SDEKit
import SwiftUI
import TrainingKit

/// One certificate: its description, its five grades, the skills each grade asks for, and the ships
/// it is recommended for.
struct CertificateInfoView: View {
    let certificateID: CertificateID

    @LiteQuery private var summary: CertificateSummary?

    init(certificateID: CertificateID) {
        self.certificateID = certificateID
        _summary = LiteQuery(CertificateBrowser.summary(of: certificateID))
    }

    var body: some View {
        Group {
            if let summary {
                CertificateInfoBody(summary: summary)
            } else {
                ContentUnavailableView(
                    "Unknown Certificate",
                    systemImage: "rosette",
                    description: Text("Certificate \(certificateID.rawValue, format: .number.grouping(.never)) is not in the database.")
                )
            }
        }
        .hudScreen()
        .navigationTitle(summary?.name ?? "")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Everything else about the certificate, keyed off the id the summary has confirmed.
///
/// A separate view because `@LiteQuery` builds its query in `init`: a query that depends on another
/// one's result lives one level down, where that result is an argument.
private struct CertificateInfoBody: View {
    let summary: CertificateSummary

    @Environment(\.trainingContext) private var trainingContext
    @Environment(AccountStore.self) private var accounts

    @LiteQuery private var ships: [TypeReference]

    /// The grade the player picked in the required-skills picker, `nil` until they pick one.
    ///
    /// Only the pick is stored; the default is computed on every read (`shownTier`), so it follows
    /// the character sheet loading.
    @State private var selectedTier: CertificateTier?

    init(summary: CertificateSummary) {
        self.summary = summary
        _ships = LiteQuery(CertificateBrowser.ships(recommendedBy: summary.id))
    }

    var body: some View {
        HUDList {
            HUDListSection {
                header
                NavigationLink(value: DatabaseRoute.group(summary.groupID)) {
                    HUDReadoutRow("Skill Group") {
                        HStack(spacing: 8) {
                            Text(summary.groupName)
                            HUDChevron()
                        }
                    }
                }
                .hudRowButton(.readout)
            }

            if let description = summary.descriptionText, !description.isEmpty {
                Section {
                    HUDDescriptionPanel(text: EVEMarkup.attributedString(from: description))
                        .hudBareRow()
                } header: {
                    HUDSectionHeader(Text("Description")).hudListHeader()
                }
            }

            // Nothing to time and nothing to plan without a pilot.
            if let context = trainingContext, context.pilot != nil {
                HUDListSection("Grades") {
                    ForEach(CertificateTier.allCases, id: \.self) { tier in
                        let queue = context.queue(forCertificate: summary.id, tier: tier)
                        CertificateTierRow(
                            tier: tier,
                            status: context.tierStatus(ofCertificate: summary.id, tier: tier) ?? .absent,
                            time: (queue?.isEmpty ?? true) ? nil : queue?.totalTime
                        ) {
                            if let queue {
                                accounts.currentPlan?.add(context.unplanned(in: queue))
                            }
                        }
                    }
                }
            }

            CertificateSkillsSection(certificateID: summary.id, selectedTier: shownTier)

            // No section without a recommendation; an empty "Recommended For" would read as missing
            // data.
            if !ships.isEmpty {
                HUDListSection(Text("Recommended For · \(ships.count)")) {
                    ForEach(ships) { ship in
                        NavigationLink(value: DatabaseRoute.type(ship.id)) {
                            HStack(spacing: 12) {
                                HUDItemIcon(typeID: ship.id, size: 28)
                                Text(ship.name)
                                    .font(.hudBody)
                                Spacer(minLength: 4)
                                HUDChevron()
                            }
                            .hudRow()
                        }
                        .hudRowButton()
                    }
                }
            }
        }
    }

    private var achieved: CertificateTier? {
        trainingContext?.achievedTier(ofCertificate: summary.id)
    }

    /// Which grade the picker shows, and where a pick goes.
    ///
    /// Until the player picks one it answers the lowest grade they have not earned, and `elite` for
    /// a character who holds the whole certificate. It is recomputed on every read, so a pilot
    /// loading later moves the default; a pick takes over for good.
    private var shownTier: Binding<CertificateTier> {
        Binding(get: { selectedTier ?? achieved.map { $0.next ?? .elite } ?? .basic },
                set: { selectedTier = $0 })
    }

    private var header: some View {
        HStack(spacing: 14) {
            Image(systemName: "rosette")
                .font(.system(size: 28))
                .foregroundStyle(Color.hudAccent)
                .frame(width: 56, height: 56)
                .background(Color.hudSurfaceRaised, in: .rect(cornerRadius: 12))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                Text(summary.name)
                    .font(HUDFont.display(22, weight: .bold, relativeTo: .title2))
                    .tracking(0.5)
                    .textCase(.uppercase)
                HStack(spacing: 8) {
                    CertificateTierBadge(tier: achieved)
                    Text(achieved?.title ?? "Not achieved")
                        .font(.hudCaption)
                        .textCase(.uppercase)
                        .foregroundStyle(Color.hudInkMuted)
                }
            }
            Spacer(minLength: 0)
        }
        .hudRow(HUDRowStyle(minHeight: 0, verticalPadding: HUDMetrics.gutter))
    }
}

/// One grade: its name, the time left to reach it, where the plan stands, and a tap that plans
/// exactly what is missing.
///
/// A view of its own so the haptic fires once: on the section, the modifier would apply to all five
/// rows.
private struct CertificateTierRow: View {
    let tier: CertificateTier
    let status: TrainingContext.PlanStatus
    /// `nil` once there is nothing left to train for this grade.
    let time: TimeInterval?
    let action: () -> Void

    @State private var tapped = false

    private var numeral: Text {
        Text(verbatim: " " + SkillLevel.roman(tier.displayNumber))
            .font(HUDFont.mono(15, weight: .regular, relativeTo: .body))
            .foregroundStyle(Color.hudInkMuted)
    }

    var body: some View {
        Button {
            tapped.toggle()
            action()
        } label: {
            HStack(spacing: 10) {
                // The title goes in as a `Text`, not as its key: a `LocalizedStringKey`
                // interpolated into another one prints as the key itself.
                Text("\(Text(tier.title))\(numeral)")
                    .font(.hudBody)
                Spacer()
                if let time {
                    Text(TrainingTime.string(time))
                        .font(.hudCaption)
                        .foregroundStyle(Color.hudInkMuted)
                }
                PlanRowAccessory(status: status)
            }
            .hudRow()
        }
        .hudRowButton()
        // Already at this grade, or already planned to it in full: nothing left to add.
        .disabled(status == .trained || status == .planned)
        .sensoryFeedback(.success, trigger: tapped)
    }
}

/// The skills one grade of the certificate asks for, with the segmented picker that switches which
/// grade is shown.
///
/// A view of its own because `@LiteQuery` builds its query in `init`: the names depend on the
/// certificate's id, not on the selected grade.
private struct CertificateSkillsSection: View {
    let certificateID: CertificateID
    @Binding var selectedTier: CertificateTier

    @Environment(\.trainingContext) private var trainingContext

    @LiteQuery private var names: [TypeNameRow]

    init(certificateID: CertificateID, selectedTier: Binding<CertificateTier>) {
        self.certificateID = certificateID
        _selectedTier = selectedTier
        _names = LiteQuery(CertificateBrowser.skills(ofCertificate: certificateID))
    }

    var body: some View {
        // Built once per grade rather than once per row: every row's time comes from the same
        // queue.
        let queue = trainingContext?.queue(forCertificate: certificateID, tier: selectedTier)
        // One titled section: the picker leads it, the skills of the picked grade are the card
        // `headerSpacing` under it.
        HUDListSection("Skills for Grade") {
            Picker("Grade", selection: $selectedTier) {
                ForEach(CertificateTier.allCases, id: \.self) { tier in
                    // Roman numerals only: the full grade names do not fit in a segment.
                    Text(SkillLevel.roman(tier.displayNumber)).tag(tier)
                }
            }
            .pickerStyle(.segmented)
            .hudLeadingBlock(hasCardBelow: !rows.isEmpty)
            ForEach(rows) { row in
                NavigationLink(value: DatabaseRoute.type(row.id)) {
                    label(for: row, queue: queue)
                }
                .hudRowButton()
            }
        }
    }

    /// The skills the selected grade asks for, alphabetical, with the level it wants of each.
    ///
    /// Levels come from the catalog, never from `names`, which carries only the alphabetical order.
    /// A level of `0` means the grade does not ask for the skill, so those are left out.
    private var rows: [SkillRow] {
        guard let certificate = trainingContext?.certificates[certificateID] else { return [] }
        let levels = Dictionary(
            certificate.skills.map { ($0.skillID, $0.level(at: selectedTier)) },
            uniquingKeysWith: { first, _ in first }
        )
        return names.compactMap { name in
            guard let level = levels[name.id], level > 0 else { return nil }
            return SkillRow(id: name.id, name: name.name, level: level)
        }
    }

    private func label(for row: SkillRow, queue: TrainingQueue?) -> some View {
        HStack(spacing: 12) {
            HUDItemIcon(typeID: row.id, size: 28)
            hudSkillText(row.name, level: row.level)
                .font(.hudBody)
            Spacer(minLength: 4)
            trailing(for: row, queue: queue)
        }
        .hudRow()
    }

    /// Time and plan marker for one skill at the level the selected grade wants. The time is shown
    /// only when that level is not already trained. No "add to plan" control: planning lives in the
    /// grades section above.
    @ViewBuilder
    private func trailing(for row: SkillRow, queue: TrainingQueue?) -> some View {
        if let status = trainingContext?.planStatus(ofSkill: row.id, level: row.level) {
            HStack(spacing: 6) {
                if status != .trained, let time = trainingTime(of: row, in: queue) {
                    Text(TrainingTime.string(time))
                        .font(.hudCaption)
                        .foregroundStyle(Color.hudInkMuted)
                }
                PlanStatusMarker(status: status)
            }
        }
    }

    /// Every level of this skill the character still misses on the way to the level the selected
    /// grade wants, summed. `nil` when none of them are in the queue.
    private func trainingTime(of row: SkillRow, in queue: TrainingQueue?) -> TimeInterval? {
        guard let queue else { return nil }
        let times = (1...row.level).compactMap { queue.time(forSkill: row.id, level: $0) }
        guard !times.isEmpty else { return nil }
        return times.reduce(0, +)
    }
}

/// One row of the required-skills section: a skill, and the level the selected grade wants
/// of it.
private struct SkillRow: Identifiable {
    var id: TypeID
    var name: String
    var level: Int
}

#Preview {
    NavigationStack {
        CertificateInfoView(certificateID: 1)
    }
    .environment(AccountStore())
    .environment(SDEStore())
}
