import DogmaKit
import LiteRow
import LiteRowUI
import SDEKit
import SwiftUI
import TrainingKit

/// The skills the fit is calculated with: presets, the signed-in pilots (`HUDPilotCarousel`),
/// then every skill the fit asks for, each as a bar whose segments are tapped.
///
/// A sheet with its own `NavigationStack` and `SDESectionView`: a sheet does not inherit
/// `liteDatabase` from the screen behind it. Every change goes out as the full
/// `FitDocument.Skills` through `FittingEditorModel.setSkills(_:)`; the document stores `default`
/// plus exceptions, which only mean something read together.
struct FitSkillsView: View {
    let model: FittingEditorModel

    @Environment(\.dismiss) private var dismiss
    @Environment(\.trainingContext) private var trainingContext
    @Environment(AccountStore.self) private var accounts

    var body: some View {
        // Built once per pass: each set is a few hundred levels and several views ask the same
        // question.
        let roster = FitPilotRoster(accounts: accounts, catalog: trainingContext?.catalog)
        let match = roster.member(trained: model.skills)
        NavigationStack {
            SDESectionView { _ in
                FitSkillsBody(
                    typeIDs: model.snapshot?.typeIDs ?? [],
                    skills: model.skills,
                    catalog: trainingContext?.catalog,
                    // Rows compare against the character whose set the fit holds, else the selected
                    // character.
                    pilot: (match ?? roster.current)?.pilot,
                    roster: roster,
                    selectedPilotID: match?.id,
                    onChange: { model.setSkills($0) }
                )
            }
            .task(id: roster.memberIDs) { await roster.ensureFresh() }
            .hudScreen()
            .navigationTitle("Skills")
            // The state of the set in words; see `FitDocument.Skills.SetKind`.
            .navigationSubtitle(Text(verbatim: roster.label(of: model.skills)))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done", systemImage: "xmark", role: .cancel) { dismiss() }
                }
            }
        }
    }
}

// MARK: - Skill sets

extension FitDocument.Skills {
    /// The level this set gives a skill, 0…5.
    func level(of skill: TypeID) -> Int {
        let raw = levels.first { $0.type == skill }.map(\.level) ?? self.default
        return min(Int(raw), 5)
    }

    /// This set with one skill moved to `level`.
    ///
    /// An exception equal to `default` is dropped; exceptions are kept sorted by type for a stable
    /// diff.
    func setting(_ level: Int, of skill: TypeID) -> FitDocument.Skills {
        var copy = self
        copy.levels.removeAll { $0.type == skill }
        let clamped = UInt8(min(max(level, 0), 5))
        if clamped != copy.default {
            copy.levels.append(.init(type: skill, level: clamped))
            copy.levels.sort { $0.type.rawValue < $1.type.rawValue }
        }
        return copy
    }

    /// Every skill at `level`, no exceptions.
    static func all(_ level: Int) -> FitDocument.Skills {
        FitDocument.Skills(default: UInt8(min(max(level, 0), 5)))
    }

    /// What the character has trained: `default` 0 plus an exception per skill above 0.
    static func trained(by pilot: Pilot) -> FitDocument.Skills {
        let levels = pilot.skills
            .filter { $0.value.level > 0 }
            .map { FitDocument.Skills.Level(type: $0.key, level: UInt8(min($0.value.level, 5))) }
            .sorted { $0.type.rawValue < $1.type.rawValue }
        return FitDocument.Skills(default: 0, levels: levels)
    }

    /// `N` when this is exactly "all skills at N", `nil` for anything with exceptions.
    var uniformLevel: Int? {
        levels.isEmpty ? min(Int(self.default), 5) : nil
    }

    /// Which of the three answers this set is. Shared by the skills screen's subtitle and a fitted
    /// item's sheet caption.
    ///
    /// A preset is recognised by comparing the stored value, and `DogmaEngine.export` does not
    /// round-trip it: it recomputes `default` as the mode of the level histogram. A set saved as
    /// `default: 0` plus exceptions can come back as `default: 5` plus other exceptions and read
    /// `Custom` after reopening. The levels stay correct.
    enum SetKind: Equatable {
        /// Every skill at this level, no exceptions.
        case uniform(Int)
        /// Exactly what the character has trained.
        case pilot
        case custom
    }

    /// `pilotSkills` is what the character has trained (`trained(by:)`), or `nil` when there is no
    /// character to compare against.
    func setKind(comparedTo pilotSkills: FitDocument.Skills?) -> SetKind {
        if let level = uniformLevel {
            return .uniform(level)
        }
        if let pilotSkills, self == pilotSkills {
            return .pilot
        }
        return .custom
    }
}

extension FitDocument.Skills.SetKind {
    /// The set in words: `All V`, the character's own name, or `Custom`.
    func label(characterName: String?) -> String {
        switch self {
        case let .uniform(level): String(localized: "All \(SkillLevel.roman(level))")
        case .pilot: characterName ?? String(localized: "Pilot")
        case .custom: String(localized: "Custom")
        }
    }
}

// MARK: - Body

/// Looks up what the fit's items require and expands it.
private struct FitSkillsBody: View {
    let skills: FitDocument.Skills
    let catalog: SkillCatalog?
    let pilot: Pilot?
    /// The signed-in characters, for the carousel.
    let roster: FitPilotRoster
    /// The character whose trained set the fit holds exactly, if any.
    let selectedPilotID: Int64?
    let onChange: (FitDocument.Skills) -> Void

    @LiteQuery private var requirementRows: [ItemSkillRow]

    init(
        typeIDs: [TypeID],
        skills: FitDocument.Skills,
        catalog: SkillCatalog?,
        pilot: Pilot?,
        roster: FitPilotRoster,
        selectedPilotID: Int64?,
        onChange: @escaping (FitDocument.Skills) -> Void
    ) {
        self.skills = skills
        self.catalog = catalog
        self.pilot = pilot
        self.roster = roster
        self.selectedPilotID = selectedPilotID
        self.onChange = onChange
        _requirementRows = LiteQuery(FittingBrowser.skills(requiredBy: typeIDs))
    }

    var body: some View {
        HUDList {
            presets
            FitMissingSkillsSection(requirements: directRequirements)
            FitSkillsList(
                skillIDs: skillIDs,
                skills: skills,
                pilot: pilot,
                onChange: onChange
            )
        }
    }

    /// Every skill the fit stands on, directly or through prerequisites, in a fixed order.
    ///
    /// The query returns a row per (item, skill), so duplicates collapse to the highest level
    /// before expanding. The order is by id: it keys the names query and must be stable across
    /// rebuilds. Without a catalog the direct requirements are listed as they are.
    private var skillIDs: [TypeID] {
        let direct = directRequirements
        let expanded = catalog?.expand(direct) ?? direct
        return expanded.map(\.skillID).sorted { $0.rawValue < $1.rawValue }
    }

    /// The fit's direct requirements, one per skill at the highest level any item asks for.
    private var directRequirements: [SkillCatalog.Requirement] {
        var levels: [TypeID: Int] = [:]
        for row in requirementRows {
            levels[row.id] = max(levels[row.id] ?? 0, row.level)
        }
        return levels
            .map { SkillCatalog.Requirement(skillID: $0.key, level: $0.value) }
            .sorted { $0.skillID.rawValue < $1.skillID.rawValue }
    }

    // MARK: Presets

    private var presets: some View {
        Section {
            VStack(spacing: HUDMetrics.headerSpacing) {
                HStack(spacing: 6) {
                    ForEach(0...5, id: \.self) { level in
                        // `ALL 0` for the first, the numeral alone for the rest; the accessibility
                        // label spells it out.
                        HUDPresetKey(title: Text(verbatim: level == 0 ? "ALL 0" : SkillLevel.roman(level)),
                                     isSelected: skills == .all(level),
                                     accessibilityLabel: Text("All \(SkillLevel.roman(level))")) {
                            onChange(.all(level))
                        }
                    }
                }
                // A character whose sheet has not loaded is drawn but not tappable. Tapping the
                // chosen one again re-applies it: the fit does not follow the training on its own.
                if !roster.members.isEmpty {
                    HUDPilotCarousel(entries: roster.members.map { member in
                        let isSelected = member.id == selectedPilotID
                        return HUDPilotCarousel.Entry(
                            account: member.account,
                            caption: member.pilot == nil ? Text("Loading…")
                                : Text("Trained Skills"),
                            isSelected: isSelected,
                            isEnabled: member.pilot != nil
                        )
                    }) { account in
                        guard let set = roster.members.first(where: { $0.id == account.id })?.skills else { return }
                        onChange(set)
                    }
                }
            }
            .hudBareRow()
        } header: {
            HUDSectionHeader("Preset")
                .hudListHeader()
        }
    }
}

// MARK: - Missing skills

/// What the selected character still has to train to use the fit, as one row that adds it to the
/// plan. Measured against the signed-in character, whatever set the fit is calculated with; hidden
/// without a character or when nothing is missing.
private struct FitMissingSkillsSection: View {
    let requirements: [SkillCatalog.Requirement]

    @Environment(\.trainingContext) private var trainingContext
    @Environment(AccountStore.self) private var accounts

    var body: some View {
        if let queue = trainingContext?.queue(forRequirements: requirements), !queue.isEmpty {
            let unplanned = trainingContext?.unplanned(in: queue) ?? []
            HUDListSection("Missing Skills") {
                AddToPlanRow(time: queue.totalTime, isPlanned: unplanned.isEmpty) {
                    accounts.currentPlan?.add(unplanned)
                }
            }
        }
    }
}

// MARK: - The skills the fit uses

/// The panel of skills. Reads the names of the prerequisites added by `expand`, which are not in
/// the requirement rows.
private struct FitSkillsList: View {
    let skills: FitDocument.Skills
    let pilot: Pilot?
    let onChange: (FitDocument.Skills) -> Void

    @LiteQuery private var typeNames: [TypeNameRow]
    private let skillIDs: [TypeID]

    init(
        skillIDs: [TypeID],
        skills: FitDocument.Skills,
        pilot: Pilot?,
        onChange: @escaping (FitDocument.Skills) -> Void
    ) {
        self.skillIDs = skillIDs
        self.skills = skills
        self.pilot = pilot
        self.onChange = onChange
        _typeNames = LiteQuery(SDEBrowser.typeNames(of: skillIDs))
    }

    var body: some View {
        let names = Dictionary(typeNames.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        // `@LiteQuery` reads synchronously, so a missing name means the export has none: the row is
        // drawn nameless, sorted last, rather than dropped.
        let rows = skillIDs
            .map { (id: $0, name: names[$0] ?? "") }
            .sorted { lhs, rhs in
                if lhs.name.isEmpty != rhs.name.isEmpty { return rhs.name.isEmpty }
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }

        if !rows.isEmpty {
            HUDListSection(rows, id: \.id, row: { row in
                FitSkillRow(
                    name: row.name,
                    level: skills.level(of: row.id),
                    pilotLevel: pilot.map { $0.trainedLevel(of: row.id) }
                ) { level in
                    onChange(skills.setting(level, of: row.id))
                }
            }, header: {
                HUDSectionHeader(Text("Used by this fit · \(rows.count)")) {
                    // Column captions; with no character there is only the first.
                    if pilot != nil {
                        Text("Fit · Pilot")
                    }
                }
            }, footer: {
                HUDFootnote("Only the skills this fit stands on are listed. The rest follow the preset.")
            })
        }
    }
}

/// One skill: its name, what the character has for comparison, and the fit's level as a bar of
/// six keys.
private struct FitSkillRow: View {
    let name: String
    let level: Int
    /// `nil` without a character.
    let pilotLevel: Int?
    let onSet: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(verbatim: name)
                    .font(.hudBody)
                    .foregroundStyle(Color.hudInk)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let pilotLevel {
                    // Not a warning: a fit may be calculated for skills the character lacks.
                    if level > pilotLevel {
                        Text("Ahead of pilot")
                            .font(.hudMicro)
                            .tracking(1)
                            .textCase(.uppercase)
                            .foregroundStyle(Color.hudInkFaint)
                            .lineLimit(1)
                            .layoutPriority(1)
                    }
                    Text("Pilot \(SkillLevel.roman(pilotLevel))")
                        .font(.hudLabel)
                        .textCase(.uppercase)
                        .foregroundStyle(Color.hudInkMuted)
                        .lineLimit(1)
                        .layoutPriority(1)
                }
            }
            // Keys past the pilot's own level are the dim ones: a calculation, not what the pilot
            // can do.
            HUDLevelBar(trained: level, height: 22, spacing: 3,
                        includesZero: true, ownLevel: pilotLevel, onSelect: onSet)
                .accessibilityLabel(Text("\(name), level in fit"))
        }
        .padding(.top, 10)
        .padding(.bottom, 12)
        .hudRow(HUDRowStyle(minHeight: 0, verticalPadding: 0))
    }
}
