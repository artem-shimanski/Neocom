import DogmaKit
import LiteRow
import LiteRowUI
import SDEKit
import SwiftUI

/// What `CLEAR` empties; the answer to the dialog it opens.
private enum ClearScope {
    case implants, boosters, both
}

/// The pilot's implants and boosters: a grid of ten implant slots, a grid of booster slots, every
/// signed-in character's set as a preset above them, `CLEAR` in the navigation bar, and what a
/// booster does to the pilot besides its bonus under each booster row.
///
/// A row per slot, empty or not; a tap opens the picker for that slot only. Implant slots are
/// 1…10; booster slots are the `boosterness` values `FittingBrowser.boosterSlots()` reads
/// (1, 2, 3, 10, 11, …). An item whose slot a grid has no row for keeps a row of its own after it.
///
/// A sheet on the editor's own model: a second `FitSession` on the same fit would renumber the
/// engine's entities. It has its own `NavigationStack` and `SDESectionView`, since a sheet does
/// not inherit `liteDatabase`. Names, the one-line bonus and side effects are static data read
/// through `@LiteQuery`; the session only knows which type is in which slot.
struct FitImplantsView: View {
    let model: FittingEditorModel
    /// The fit's name, for the subtitle; handed over as to `FittedTypeInfoView`.
    let fitName: String

    @Environment(\.dismiss) private var dismiss
    @Environment(\.trainingContext) private var trainingContext
    @Environment(AccountStore.self) private var accounts

    /// The info screen a slot's context menu asked for, pushed on this sheet's own stack.
    @State private var infoRoute: FitInfoRoute?
    /// Handed to the info screen: it is asked for from a menu action (see `CarriedEnvironment`).
    private var carried = CarriedEnvironment()
    /// Whether `CLEAR` is asking what to clear.
    @State private var isClearChoicePresented = false

    var body: some View {
        NavigationStack {
            SDESectionView { database in
                content
                    // The screen the editor's rows push, with the engine's values for the item.
                    .navigationDestination(item: $infoRoute) { route in
                        FittedTypeInfoView(typeID: route.typeID, target: route.target, model: model, fitName: fitName)
                            .liteDatabase(database.database)
                            .carryingEnvironment(carried)
                    }
            }
            .hudScreen()
            .navigationTitle("Implants & Boosters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done", systemImage: "xmark", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    // Nothing to clear: skip a snapshot and a write for a fit that already looks
                    // like this.
                    Button("Clear", role: .destructive) { isClearChoicePresented = true }
                        .disabled(isClear)
                        .accessibilityHint(Text("Clear implants, boosters or both"))
                        // The choice is the confirmation: three buttons that each do what they say.
                        .confirmationDialog("Clear", isPresented: $isClearChoicePresented, titleVisibility: .visible) {
                            Button("Implants", role: .destructive) { clear(.implants) }
                            Button("Boosters", role: .destructive) { clear(.boosters) }
                            Button("Both", role: .destructive) { clear(.both) }
                        } message: {
                            Text("Remove from this fit's pilot:")
                        }
                }
            }
            .task(id: roster.memberIDs) { await roster.ensureFresh() }
        }
        // On the sheet itself, so the alert is shown over it and not held back behind it.
        .fitCommandAlert(model)
    }

    /// The signed-in characters, each with the implants their sheet has; see `FitPilotRoster`.
    private var roster: FitPilotRoster {
        FitPilotRoster(accounts: accounts, catalog: trainingContext?.catalog)
    }

    /// Whether the fit's pilot carries nothing `CLEAR` could remove.
    private var isClear: Bool {
        guard let snapshot = model.snapshot else { return true }
        return snapshot.implants.isEmpty && snapshot.boosters.isEmpty
    }

    /// One command: `CLEAR` empties the list it was told to and leaves the other (`nil`) as it is.
    private func clear(_ scope: ClearScope) {
        model.setPilotItems(implants: scope == .boosters ? nil : [],
                            boosters: scope == .implants ? nil : [])
    }

    @ViewBuilder
    private var content: some View {
        Group {
            if let snapshot = model.snapshot {
                FitImplantsBody(
                    pilotID: snapshot.pilotID,
                    shipTypeID: snapshot.shipTypeID,
                    fitName: fitName,
                    implants: snapshot.implants,
                    boosters: snapshot.boosters,
                    roster: roster,
                    skills: model.skills,
                    appliedAttributes: { ids in await model.attributesOfBoosters(ids: ids) },
                    onAdd: { kind, typeID in
                        switch kind {
                        case .implant: model.add(implant: typeID)
                        case .booster: model.add(booster: typeID)
                        }
                    },
                    onSet: { kind, typeID, slot in
                        switch kind {
                        case .implant: model.setImplant(typeID, inSlot: slot)
                        case .booster: model.setBooster(typeID, inSlot: slot)
                        }
                    },
                    onRemove: { kind, slot in
                        switch kind {
                        case .implant: model.remove(implantIn: slot)
                        case .booster: model.remove(boosterIn: slot)
                        }
                    },
                    // One `edit`, one snapshot, one write. A character's set touches the implants
                    // only.
                    onApplyPilotImplants: { model.setPilotItems(implants: $0, boosters: nil) },
                    onShowInfo: { infoRoute = $0 }
                )
            } else {
                // Only the moment between two snapshots, or a fit that could not be opened.
                ContentUnavailableView {
                    Label("No Pilot", systemImage: "brain.head.profile")
                } description: {
                    Text("This fit could not be opened, so it has no pilot to carry implants.")
                }
            }
        }
    }
}

// MARK: - Body

/// Everything the screen draws, once the fit is open: the snapshot's plain values and the four
/// reads that turn type ids into words. Takes values and closures because `@LiteQuery` queries
/// are built in `init`.
private struct FitImplantsBody: View {
    /// The ship's pilot, which names an implant or a booster for its info screen.
    let pilotID: PilotID
    let shipTypeID: TypeID
    let fitName: String
    let implants: [FitSnapshot.Implant]
    let boosters: [FitSnapshot.Booster]
    /// The signed-in characters and the implants each wears, from their own sheets. A character
    /// whose sheet has not loaded, or who wears nothing, is drawn but not tappable: an empty set
    /// applied as a preset is `CLEAR`.
    let roster: FitPilotRoster
    /// The skills the fit is calculated for. Not read by the body; part of the key that re-reads
    /// the applied side effects.
    let skills: FitDocument.Skills
    /// What the engine holds for each fitted booster, for the given attributes; see
    /// `FittingEditorModel.attributesOfBoosters(ids:)`.
    let appliedAttributes: ([AttributeID]) async -> [BoosterID: [AttributeID: Double]]
    let onAdd: (SlotItemPickerView.Kind, TypeID) -> Void
    let onSet: (SlotItemPickerView.Kind, TypeID, UInt16) -> Void
    let onRemove: (SlotItemPickerView.Kind, UInt16) -> Void
    let onApplyPilotImplants: ([TypeID]) -> Void
    let onShowInfo: (FitInfoRoute) -> Void

    /// The booster slots there are rows for, ascending.
    @LiteQuery private var boosterSlotRows: [SlotNumberRow]
    /// The hull's name for the subtitle, and the name of everything in a slot.
    @LiteQuery private var typeNames: [TypeNameRow]
    /// The two sources of the one-line bonus, folded by `ItemBonusLine`.
    @LiteQuery private var attributeBonuses: [DogmaImplantAttribute]
    @LiteQuery private var modifiers: [ItemModifierRow]
    /// The side effects of every fitted booster, read for all of them at once.
    @LiteQuery private var sideEffects: [BoosterSideEffectRow]

    /// Which slot's picker is open, if any. Screen state, not an engine command.
    @State private var pickerRequest: SlotPickerRequest?
    /// Handed to the picker: a sheet asked for from a menu action is built without the app's
    /// environment.
    private var carried = CarriedEnvironment()
    /// The penalty attributes of every fitted booster as the engine applies them (`-15%` on a pilot
    /// with `Nanite Control V` where the SDE says `-20%`). Read when the screen opens and when
    /// `AppliedKey` changes; not carried on the snapshot, which is rebuilt on every tap.
    ///
    /// A booster that has not been read yet shows no magnitude rather than the SDE's figure.
    @State private var applied: [BoosterID: [AttributeID: Double]] = [:]

    init(
        pilotID: PilotID,
        shipTypeID: TypeID,
        fitName: String,
        implants: [FitSnapshot.Implant],
        boosters: [FitSnapshot.Booster],
        roster: FitPilotRoster,
        skills: FitDocument.Skills,
        appliedAttributes: @escaping ([AttributeID]) async -> [BoosterID: [AttributeID: Double]],
        onAdd: @escaping (SlotItemPickerView.Kind, TypeID) -> Void,
        onSet: @escaping (SlotItemPickerView.Kind, TypeID, UInt16) -> Void,
        onRemove: @escaping (SlotItemPickerView.Kind, UInt16) -> Void,
        onApplyPilotImplants: @escaping ([TypeID]) -> Void,
        onShowInfo: @escaping (FitInfoRoute) -> Void
    ) {
        self.pilotID = pilotID
        self.shipTypeID = shipTypeID
        self.fitName = fitName
        self.implants = implants
        self.boosters = boosters
        self.roster = roster
        self.skills = skills
        self.appliedAttributes = appliedAttributes
        self.onAdd = onAdd
        self.onSet = onSet
        self.onRemove = onRemove
        self.onApplyPilotImplants = onApplyPilotImplants
        self.onShowInfo = onShowInfo
        _boosterSlotRows = LiteQuery(FittingBrowser.boosterSlots())
        // Sorted: a query is `@LiteQuery`'s cache key, so the same fit must render the same SQL.
        let itemIDs = (implants.map(\.typeID) + boosters.map(\.typeID)).sortedIDs
        let boosterIDs = boosters.map(\.typeID).sortedIDs
        _typeNames = LiteQuery(SDEBrowser.typeNames(of: (itemIDs + [shipTypeID]).sortedIDs))
        _attributeBonuses = LiteQuery(FittingBrowser.attributeBonuses(of: itemIDs))
        _modifiers = LiteQuery(FittingBrowser.effectModifiers(of: itemIDs))
        _sideEffects = LiteQuery(FittingBrowser.sideEffects(of: boosterIDs))
    }

    var body: some View {
        let names = Dictionary(typeNames.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        // The screen's bonus lines in one fold, in the data's own case; the row upper-cases.
        let bonuses = ItemBonusLine.lines(attributeBonuses: attributeBonuses, modifiers: modifiers)
        let effects = Dictionary(grouping: sideEffects, by: \.typeID)
        HUDList {
            presetSection
            implantSection(names: names, bonuses: bonuses)
            boosterSection(names: names, bonuses: bonuses, effects: effects)
            // About both sections, not the boosters' own footnote.
            Section {
                HUDFootnote("Implants and boosters belong to this fit's pilot and are stored in the fit. The preset copies the character's implants once; it does not follow what they change later. A booster's side effects are part of what it does: the engine always applies them, as strong as this fit's skills leave them.")
                    .hudBareRow()
            }
        }
        .navigationSubtitle(Text(verbatim: subtitle(hullName: names[shipTypeID] ?? "")))
        // Keyed on everything the figure depends on, the attribute list included: a `@LiteQuery`
        // result is not there in `init`. A task for a key that is gone is cancelled and its answer
        // dropped.
        .task(id: AppliedKey(boosters: boosters, implants: implants, skills: skills,
                             attributes: sideEffects.map(\.attributeID).sortedAttributeIDs)) {
            let ids = sideEffects.map(\.attributeID).sortedAttributeIDs
            guard !ids.isEmpty else {
                applied = [:]
                return
            }
            let read = await appliedAttributes(ids)
            guard !Task.isCancelled else { return }
            applied = read
        }
        .sheet(item: $pickerRequest) { request in
            SlotItemPickerView(kind: request.kind, slot: request.slot, current: request.current) { typeID in
                select(typeID, for: request)
            }
            .carryingEnvironment(carried)
        }
    }

    /// `Vexor — drone ratting` (`FitScreenSubtitle`).
    private func subtitle(hullName: String) -> String {
        FitScreenSubtitle.text(hullName: hullName, fitName: fitName)
    }

    // MARK: Preset

    /// Every signed-in character's implants as a preset (`HUDPilotCarousel`); left out with nobody
    /// signed in. A card is checked by implants alone: the preset copies nothing else.
    @ViewBuilder
    private var presetSection: some View {
        if !roster.members.isEmpty {
            let selectedID = roster.member(wearing: implants.map(\.typeID))?.id
            Section {
                HUDPilotCarousel(entries: roster.members.map { member in
                    let worn = member.implants?.sortedIDs
                    let caption: Text = switch worn?.count {
                    case nil: Text("Loading…")
                    case 0: Text("No Implants")
                    case let count?: Text("\(count) Implants · Copy")
                    }
                    return HUDPilotCarousel.Entry(
                        account: member.account,
                        caption: caption,
                        isSelected: member.id == selectedID,
                        isEnabled: !(worn?.isEmpty ?? true)
                    )
                }) { account in
                    guard let worn = roster.members.first(where: { $0.id == account.id })?.implants?.sortedIDs,
                          !worn.isEmpty
                    else { return }
                    onApplyPilotImplants(worn)
                }
                .hudBareRow()
            } header: {
                HUDSectionHeader("Preset")
                    .hudListHeader()
            }
        }
    }

    // MARK: Sections

    /// The ten implant slots, `N / 10` in the heading, a row per slot.
    @ViewBuilder
    private func implantSection(names: [TypeID: String], bonuses: [TypeID: String]) -> some View {
        HUDListSection(SlotRow.grid(Array(1...10), items: implants.map { (slot: $0.slot, typeID: $0.typeID) }), row: { row in
            FitSlotItemRow(
                kind: .implant,
                slot: row.slot,
                name: row.typeID.map { names[$0] ?? "" },
                bonus: row.typeID.flatMap { bonuses[$0] },
                isOutsideGrid: row.isOutsideGrid,
                onPick: {
                    pickerRequest = SlotPickerRequest(kind: .implant, slot: row.slot, current: row.typeID)
                },
                onRemove: { onRemove(.implant, row.slot) },
                onShowInfo: implants.first { $0.slot == row.slot }.map { implant in
                    { onShowInfo(FitInfoRoute(typeID: implant.typeID, target: .implant(implant.id, of: pilotID))) }
                }
            )
        }, header: {
            // Counts every implant of the list, so a fit with one in a slot the grid lacks reads
            // `11 / 10`.
            HUDSectionHeader(Text("Implants")) {
                Text(verbatim: "\(implants.count) / 10")
            }
        })
    }

    /// A row per booster slot, empty or not, each fitted booster's side effects under its row;
    /// `N / slots` in the heading.
    ///
    /// The picker lists that slot's boosters only, so a pick into an empty row is an `add` that
    /// cannot meet `boosterSlotOccupied`, and a pick on an occupied one replaces what is there.
    @ViewBuilder
    private func boosterSection(names: [TypeID: String], bonuses: [TypeID: String],
                                effects: [TypeID: [BoosterSideEffectRow]]) -> some View {
        let slots = boosterSlotRows.compactMap { UInt16(exactly: $0.id) }
        // Keyed on the slot, the first booster of a slot winning, as `SlotRow.grid` does.
        let bySlot = Dictionary(boosters.map { ($0.slot, $0) }, uniquingKeysWith: { first, _ in first })
        HUDListSection(SlotRow.grid(slots, items: boosters.map { (slot: $0.slot, typeID: $0.typeID) }), row: { row in
            let booster = bySlot[row.slot]
            VStack(alignment: .leading, spacing: 0) {
                FitSlotItemRow(
                    kind: .booster,
                    slot: row.slot,
                    name: row.typeID.map { names[$0] ?? "" },
                    bonus: row.typeID.flatMap { bonuses[$0] },
                    isOutsideGrid: row.isOutsideGrid,
                    onPick: {
                        pickerRequest = SlotPickerRequest(kind: .booster, slot: row.slot, current: row.typeID)
                    },
                    onRemove: { onRemove(.booster, row.slot) },
                    onShowInfo: booster.map { booster in
                        { onShowInfo(FitInfoRoute(typeID: booster.typeID, target: .booster(booster.id, of: pilotID))) }
                    }
                )
                if let booster, let rows = effects[booster.typeID], !rows.isEmpty {
                    FitSideEffectsBlock(effects: rows, applied: applied[booster.id])
                }
            }
            // The card row is the booster with its side effects: a list reads a cell off the
            // outermost view.
            .hudRow(HUDRowStyle(horizontalPadding: 0, minHeight: 0, verticalPadding: 0))
        }, header: {
            HUDSectionHeader(Text("Boosters")) {
                Text(verbatim: "\(boosters.count) / \(slots.count)")
            }
        })
    }

    // MARK: Picking

    /// What the picker's answer means for its slot: an empty slot is an `add`, an occupied one a
    /// replacement in one command (`add` into an occupied slot throws). Applies to implants and
    /// boosters alike.
    private func select(_ typeID: TypeID, for request: SlotPickerRequest) {
        // The picker checkmarks what is in the slot and calls back on a tap: a dismissal, not an
        // edit.
        guard typeID != request.current else { return }
        if request.current != nil {
            onSet(request.kind, typeID, request.slot)
        } else {
            onAdd(request.kind, typeID)
        }
    }
}

// MARK: - Rows of a grid

/// One cell of a slot grid: the slot, and what stands in it.
private struct SlotRow: Identifiable {
    let slot: UInt16
    /// `nil` for an empty slot.
    let typeID: TypeID?
    /// An item whose slot the grid has no cell for; drawn after the grid with its own number.
    let isOutsideGrid: Bool

    var id: UInt16 { slot }

    /// The grid's own slots in order, then one row per slot that falls outside it.
    ///
    /// Ten implant slots are an interface choice (`implantness` is 1…10 and 79), so an item from a
    /// foreign document keeps a row of its own. The booster grid is the slots of the marketable
    /// boosters; an expired dose falls outside it. One row per slot, the first item winning: the
    /// row's id is the slot.
    static func grid(_ slots: [UInt16], items: [(slot: UInt16, typeID: TypeID)]) -> [SlotRow] {
        let bySlot = Dictionary(items.map { ($0.slot, $0.typeID) }, uniquingKeysWith: { first, _ in first })
        let inGrid = Set(slots)
        let grid = inGrid.sorted().map { SlotRow(slot: $0, typeID: bySlot[$0], isOutsideGrid: false) }
        let outside = bySlot
            .filter { !inGrid.contains($0.key) }
            .sorted { $0.key < $1.key }
            .map { SlotRow(slot: $0.key, typeID: $0.value, isOutsideGrid: true) }
        return grid + outside
    }
}

/// Which slot's picker to open, and what is in that slot now. `Identifiable` by the slot.
private struct SlotPickerRequest: Identifiable {
    let kind: SlotItemPickerView.Kind
    /// The slot of the tapped cell; the picker lists that slot's types.
    let slot: UInt16
    let current: TypeID?

    var id: String {
        switch kind {
        case .implant: "implant-\(slot)"
        case .booster: "booster-\(slot)"
        }
    }
}

// MARK: - One slot

/// One row of either section: the slot's number, the item's name or `Empty`, and under it what
/// the item gives or `TAP TO CHOOSE`.
///
/// No type icon, chevron or swipe: removal is the cross on the row, without confirmation.
private struct FitSlotItemRow: View {
    /// Which section the row is in. Spoken, not drawn: the two look alike and VoiceOver does not
    /// repeat the heading per row.
    let kind: SlotItemPickerView.Kind
    let slot: UInt16
    /// `nil` for an empty slot, an empty string for an item the export has no name for (drawn
    /// nameless rather than dropped).
    let name: String?
    /// The one-line bonus, in the data's own case; `nil` when the slot is empty or the type has no
    /// line (148 of 1266 implants and boosters, `High-grade Snake Omega` among them).
    let bonus: String?
    /// An item outside the grid: its number is the engine's, not a cell of the grid.
    let isOutsideGrid: Bool
    let onPick: () -> Void
    let onRemove: () -> Void
    /// Opens the item's info screen; `nil` for an empty slot.
    var onShowInfo: (() -> Void)? = nil

    /// A booster's side effects hang under the row inside the same cell.
    private static let height: CGFloat = 58

    var body: some View {
        HStack(spacing: 0) {
            Button(action: onPick) {
                HStack(spacing: 12) {
                    Text(verbatim: "\(slot)")
                        .font(HUDFont.mono(13, weight: .medium, relativeTo: .subheadline))
                        .foregroundStyle(name == nil ? Color.hudInkFaint : Color.hudInkMuted)
                        .lineLimit(1)
                        // 18 for one or two digits, wider for a booster under a three-digit
                        // `boosterness` (up to 504).
                        .frame(minWidth: 18, alignment: .leading)
                        .fixedSize()
                    VStack(alignment: .leading, spacing: 3) {
                        Text(verbatim: name ?? String(localized: "Empty"))
                            .font(.hudBody)
                            .foregroundStyle(name == nil ? Color.hudInkFaint : Color.hudInk)
                            .lineLimit(1)
                        if let caption {
                            caption
                                .font(HUDFont.mono(11, weight: .regular, relativeTo: .caption))
                                .textCase(.uppercase)
                                .foregroundStyle(name == nil ? Color.hudInkFaint : Color.hudAccent)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                    }
                    Spacer(minLength: 4)
                    if name == nil {
                        Image(systemName: "plus")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color.hudAccent)
                            .accessibilityHidden(true)
                    }
                }
                .padding(.vertical, 8)
                .frame(minHeight: Self.height)
                .contentShape(Rectangle())
            }
            .buttonStyle(.hudRow)
            .accessibilityLabel(accessibilityLabel)
            .accessibilityHint("Chooses what goes in this slot")
            if name != nil {
                // 44 × 44: the one way off this screen's rows, which carry no swipe.
                Button(action: onRemove) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color.hudInkMuted)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(removeLabel)
            }
        }
        // 16 in on the leading side; trailing, 6 past the 44 pt cross or 18 past the plus of an
        // empty slot.
        .padding(.leading, HUDMetrics.gutter)
        .padding(.trailing, name == nil ? 18 : 6)
        // An occupied slot's tap and cross, for a right click on the Mac; an empty slot has no
        // menu.
        .contextMenu {
            if let name {
                Button(action: onPick) {
                    Label("Replace…", systemImage: "arrow.left.arrow.right")
                }
                if let onShowInfo {
                    Button(action: onShowInfo) {
                        Label("Info", systemImage: "info.circle")
                    }
                }
                HUDCopyButton("Copy Name", value: name)
                Button(role: .destructive, action: onRemove) {
                    Label("Remove", systemImage: "trash")
                }
            }
        }
        .hudRow(HUDRowStyle(horizontalPadding: 0, minHeight: Self.height, verticalPadding: 0))
    }

    /// The bonus for an occupied slot, `TAP TO CHOOSE` for an empty one, nothing for an item the
    /// SDE says nothing about.
    private var caption: Text? {
        if name == nil { return Text("Tap to choose") }
        if let bonus { return Text(verbatim: bonus) }
        // The engine knows this slot but the grid does not; the row says so in place of the bonus.
        return isOutsideGrid ? Text("Slot \(Int(slot)) · outside the grid") : nil
    }

    private var accessibilityLabel: Text {
        switch (kind, name) {
        case let (.implant, .some(name)) where !name.isEmpty: Text("Slot \(Int(slot)): \(name)")
        case let (.booster, .some(name)) where !name.isEmpty: Text("Booster slot \(Int(slot)): \(name)")
        // The SDE has no name for what is in this slot.
        case (.implant, .some): Text("Slot \(Int(slot)): an item")
        case (.booster, .some): Text("Booster slot \(Int(slot)): an item")
        case (.implant, .none): Text("Slot \(Int(slot)): empty")
        case (.booster, .none): Text("Booster slot \(Int(slot)): empty")
        }
    }

    /// `Remove Ocular Filter - Standard`, and the slot's own words for an item with no name.
    private var removeLabel: Text {
        guard let name, !name.isEmpty else {
            return kind == .booster
                ? Text("Remove the booster in slot \(Int(slot))")
                : Text("Remove the implant in slot \(Int(slot))")
        }
        return Text("Remove \(name)")
    }
}

// MARK: - Side effects

/// What a booster does to the pilot besides its bonus: a row per effect, its magnitude and how
/// often it fires.
///
/// The magnitude is the one the engine applies (`applied`), not the SDE's: the penalty is
/// lowered by the pilot's skills. The chance is the SDE's; the engine does not compute it. The
/// block is read-only: the penalties are passive effects the modifier collector always applies,
/// and the screen's footnote says so.
private struct FitSideEffectsBlock: View {
    let effects: [BoosterSideEffectRow]
    /// The engine's values for this booster, by attribute. `nil` while not read (the magnitude is a
    /// dash); empty when the engine has none, in which case the SDE's figure stands in.
    let applied: [AttributeID: Double]?

    private func magnitudeText(of effect: BoosterSideEffectRow) -> String {
        guard let applied else { return "—" }
        return effect.magnitudeText(applied: applied[effect.attributeID])
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Side Effects")
                .font(.hudMicro)
                .tracking(1.5)
                .textCase(.uppercase)
                .foregroundStyle(Color.hudInkFaint)
                .padding(.top, 4)
                .padding(.bottom, 2)
                .accessibilityAddTraits(.isHeader)
            ForEach(Array(effects.enumerated()), id: \.element.id) { index, effect in
                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: effect.title)
                        .font(HUDFont.display(14, weight: .medium, relativeTo: .subheadline))
                        .foregroundStyle(Color.hudInkBodyMuted)
                    Text("\(magnitudeText(of: effect)) · \(effect.chanceText) chance")
                        .font(HUDFont.mono(11, weight: .regular, relativeTo: .caption))
                        .textCase(.uppercase)
                        .foregroundStyle(Color.hudInkMuted)
                }
                .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
                .overlay(alignment: .top) {
                    // The card divides its own rows; this block is inside one, so it divides
                    // itself, above every effect but the first.
                    if index > 0 {
                        Rectangle().fill(Color.hudLineSubtle).frame(height: 1)
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }
        // Indented past the slot number: the gutter, the number's column and the gap after it.
        .padding(.leading, HUDMetrics.gutter + 18 + 12)
        .padding(.trailing, HUDMetrics.gutter)
        .padding(.bottom, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Ids

/// What the applied side effects are read for. Equatable by value, so a swap of a booster, an
/// implant or the skills reads again, and nothing else does.
private struct AppliedKey: Equatable {
    let boosters: [BoosterID]
    let boosterTypes: [TypeID]
    let implants: [ImplantID]
    let skills: FitDocument.Skills
    let attributes: [AttributeID]

    init(boosters: [FitSnapshot.Booster], implants: [FitSnapshot.Implant], skills: FitDocument.Skills,
         attributes: [AttributeID]) {
        self.boosters = boosters.map(\.id)
        self.boosterTypes = boosters.map(\.typeID)
        self.implants = implants.map(\.id)
        self.skills = skills
        self.attributes = attributes
    }
}

extension [AttributeID] {
    /// Once each, ascending: the key of the read, and the list it asks for.
    var sortedAttributeIDs: [AttributeID] {
        Array(Set(self)).sorted { $0.rawValue < $1.rawValue }
    }
}

extension [TypeID] {
    /// The list once each, ascending: the shape every `@LiteQuery` here wants, as the query is the
    /// cache key.
    var sortedIDs: [TypeID] {
        Array(Set(self)).sorted { $0.rawValue < $1.rawValue }
    }
}

// The rows without the fit behind them, including an item whose slot the grid has no cell for,
// which only a document from elsewhere can carry.
#Preview("Slot rows") {
    HUDList {
        HUDListSection {
            FitSlotItemRow(kind: .implant, slot: 1, name: "Ocular Filter - Standard", bonus: "+4 Perception",
                           isOutsideGrid: false, onPick: {}, onRemove: {})
            FitSlotItemRow(kind: .implant, slot: 2, name: nil, bonus: nil,
                           isOutsideGrid: false, onPick: {}, onRemove: {})
            // One of the 148 types the SDE gives no line for: the row is one line tall.
            FitSlotItemRow(kind: .implant, slot: 6, name: "High-grade Snake Omega", bonus: nil,
                           isOutsideGrid: false, onPick: {}, onRemove: {})
            // `implantness` 79: reaches a fit only through a document written elsewhere.
            FitSlotItemRow(kind: .implant, slot: 79, name: "Capsuleer Hardwiring", bonus: nil,
                           isOutsideGrid: true, onPick: {}, onRemove: {})
        }
        HUDListSection {
            VStack(alignment: .leading, spacing: 0) {
                FitSlotItemRow(kind: .booster, slot: 1, name: "Standard Exile Booster",
                               bonus: "+20% Armor Repair Bonus",
                               isOutsideGrid: false, onPick: {}, onRemove: {})
                FitSideEffectsBlock(effects: [
                    BoosterSideEffectRow(id: EffectID(rawValue: 1), typeID: TypeID(rawValue: 10156),
                                         attributeID: AttributeID(rawValue: 1141), name: "boosterArmorHPPenalty", displayName: "Armor Hitpoint Penalty",
                                         value: -20, chance: 0.2, unitID: UnitID(rawValue: 105), unitName: "%"),
                    BoosterSideEffectRow(id: EffectID(rawValue: 2), typeID: TypeID(rawValue: 10156),
                                         attributeID: AttributeID(rawValue: 1145), name: "boosterTurretTrackingPenalty", displayName: "Turret Tracking Penalty",
                                         value: -20, chance: 0.2, unitID: UnitID(rawValue: 105), unitName: "%"),
                ],
                // `Nanite Control V`: what the engine applies where the SDE says `-20%`.
                applied: [AttributeID(rawValue: 1141): -15, AttributeID(rawValue: 1145): -15])
            }
            .hudRow(HUDRowStyle(horizontalPadding: 0, minHeight: 0, verticalPadding: 0))
        }
    }
}
