import DogmaKit
import DogmaKitIO
import DogmaText
import LiteRow
import LiteRowUI
import SDEKit
import SwiftData
import SwiftUI

/// The fit editor: the resource header, one section per slot the hull has (or has something in),
/// then drones.
///
/// Opened on one record or on several (a fleet). A fleet adds a strip of ships over the same
/// screen, which shows one ship at a time. The fleet is stored nowhere; every ship is saved to its
/// My Fits record.
///
/// `@Environment(FittingStore.self)` is unavailable in `init`, so `model` starts `nil` and is
/// built and loaded from `.task`. The screen owns a model because it holds state that outlives a
/// body pass: a live engine session and its command queue.
struct FittingEditorView: View {
    let fittingIDs: [UUID]

    init(fittingID: UUID) {
        self.fittingIDs = [fittingID]
    }

    @Environment(FittingStore.self) private var fittings
    @Environment(AccountStore.self) private var accounts
    @Environment(SDEStore.self) private var sde
    @Environment(\.dismiss) private var dismiss
    /// The narrowest screen area that shows the stats as a trailing column instead of a pushed
    /// screen: the column (380) plus about 420 for the modules. Measured on the area, not on the
    /// size class, which stays `.regular` on an iPad in portrait with the sidebar up.
    private static let statsColumnMinimumWidth: CGFloat = 800

    private static let statsColumnWidth: CGFloat = 380

    /// The narrowest the modules get next to the stats column. Enforced on Mac only; the window's
    /// minimum width is sized from it (`macMinimumWidth`).
    private static let fittingAreaMinimumWidth: CGFloat = 420

    static let macMinimumWidth: CGFloat = fittingAreaMinimumWidth + 1 + statsColumnWidth

    /// On Mac the stats are always a column; the window is sized never to be too narrow for both
    /// (see `NeocomApp`).
    private static var alwaysShowsStatsColumn: Bool {
        #if targetEnvironment(macCatalyst)
        true
        #else
        false
        #endif
    }

    /// Whether the screen area is wide enough for the stats column. Measured on the container of
    /// the editor and the column: showing the column shrinks the editor, which would flip the flag.
    @State private var isWideEnoughForStatsColumn = false

    @State private var model: FittingEditorModel?

    // Name and notes live in their own `Fitting` columns, not in the document, so they survive a
    // document that cannot be decoded. In a fleet they follow the shown ship (`editedFittingID`).
    @State private var editedFittingID: UUID?
    @State private var name = ""
    @State private var notes = ""
    /// The values last written to the store, so a dismissed alert that changed nothing does not
    /// re-save and bump `updatedAt`.
    @State private var savedName = ""
    @State private var savedNotes = ""

    @State private var isRenameAlertPresented = false
    @State private var copyError: String?
    /// Set by the menu's "Delete"; the record goes only from the dialog's button.
    @State private var isNotesSheetPresented = false
    @State private var isSkillsSheetPresented = false
    /// The item screen a row asked for. Pushed through `navigationDestination(item:)` because the
    /// request comes from inside the item sheet, which has to close first (`FitItemFollowUp`).
    @State private var infoRoute: FitInfoRoute?
    /// Whether the stats screen is pushed; a one-case token because `navigationDestination` keys
    /// on a value.
    @State private var statsRoute: FitStatsRoute?
    @State private var isImplantsSheetPresented = false
    @State private var fleetRoute: FleetOverviewRoute?
    @State private var environmentRoute: FitEnvironmentRoute?
    @State private var mutationRoute: FitMutationRoute?
    @State private var isAddShipSheetPresented = false
    @State private var uploader = FitUploader()
    /// Handed to every sheet and destination: a presentation requested from a menu action is
    /// built without the app's environment (see `CarriedEnvironment`).
    private var carried = CarriedEnvironment()

    var body: some View {
        SDESectionView { database in
            // With enough width the stats are a permanent trailing column beside the modules. A plain
            // `HStack` rather than `.inspector`, which becomes a dismissable overlay in a narrow detail
            // column and cannot be brought back. The column has no `NavigationStack` of its own: a nested
            // stack breaks `FittingRoute` links. It shares this screen's navigation bar and reads the one
            // `model`.
            HStack(spacing: 0) {
                content
                    .frame(minWidth: Self.alwaysShowsStatsColumn ? Self.fittingAreaMinimumWidth : nil)
                if isStatsColumnShown, let model {
                    Rectangle()
                        .fill(Color.hudLine)
                        .frame(width: 1)
                        .ignoresSafeArea(edges: .bottom)
                    FitStatsView(model: model, fitName: name)
                        .frame(width: Self.statsColumnWidth)
                }
            }
                .frame(maxWidth: .infinity)
                .onGeometryChange(for: Bool.self) { proxy in
                    proxy.size.width >= Self.statsColumnMinimumWidth
                } action: { isWideEnoughForStatsColumn = $0 }
                // Registered where the database is in scope and handed on explicitly: the navigation stack
                // does not hold this section's environment.
                .navigationDestination(item: $infoRoute) { route in
                    if let model {
                        // Known issue: the `DatabaseRoute` links on this screen (group, required
                        // skills) do nothing when tapped. `SDESectionView` registers that destination twice on this stack; neither
                        // removing the second registration nor registering it here fixes it.
                        FittedTypeInfoView(typeID: route.typeID, target: route.target, model: model, fitName: name)
                            .liteDatabase(database.database)
                            .carryingEnvironment(carried)
                    }
                }
                .navigationDestination(item: $statsRoute) { _ in
                    if let model {
                        FitStatsView(model: model, fitName: name)
                            .navigationTitle("Stats")
                            .navigationBarTitleDisplayMode(.inline)
                            .liteDatabase(database.database)
                            .carryingEnvironment(carried)
                    }
                }
                .navigationDestination(item: $fleetRoute) { _ in
                    if let model {
                        FleetOverviewView(model: model)
                            .liteDatabase(database.database)
                            .carryingEnvironment(carried)
                    }
                }
                .navigationDestination(item: $environmentRoute) { _ in
                    if let model {
                        FitEnvironmentView(model: model, fitName: name)
                            .liteDatabase(database.database)
                            .carryingEnvironment(carried)
                    }
                }
                .navigationDestination(item: $mutationRoute) { route in
                    if let model {
                        FitMutationView(model: model, moduleID: route.moduleID, fitName: name)
                            .liteDatabase(database.database)
                            .carryingEnvironment(carried)
                    }
                }
        }
        // `SDESectionView` hangs no HUD background; the spinner and the unreadable-fit message are
        // system views that need one.
        .hudScreen()
        .navigationTitle(name.isEmpty ? String(localized: "Fit") : name)
        .fleetSubtitle(fleetLine)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // Redundant while the stats column is shown, and never offered on Mac.
            if !isStatsColumnShown && !Self.alwaysShowsStatsColumn {
                ToolbarItem(placement: .primaryAction) {
                    Button("Stats", systemImage: "chart.bar") {
                        statsRoute = .stats
                    }
                    .disabled(model?.snapshot?.stats == nil)
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    if let shownFittingID, fittings.isDraft(shownFittingID) {
                        Button("Save", systemImage: "square.and.arrow.down") {
                            fittings.persist(shownFittingID)
                        }
                    }
                    Button("Rename", systemImage: "pencil") {
                        isRenameAlertPresented = true
                    }
                    Button("Notes", systemImage: "square.and.pencil") {
                        isNotesSheetPresented = true
                    }
                    Menu("Copy Fit", systemImage: "doc.on.doc") {
                        Button("EFT") { copyShownFit(.eft) }
                        Button("In-Game Link (DNA)") { copyShownFit(.dna) }
                    }
                    .disabled(shownFittingID == nil || model?.snapshot == nil)
                    if accounts.currentFittings != nil {
                        uploadButton
                    }
                    Divider()
                    Button("Add Ship…", systemImage: "plus") {
                        isAddShipSheetPresented = true
                    }
                    .disabled(!(model?.canAddShip ?? false))
                    if isFleet {
                        Button("Fleet", systemImage: "square.stack.3d.up") {
                            fleetRoute = .overview
                        }
                    }
                    Divider()
                    Button("Delete", systemImage: "trash", role: .destructive) {
                        deleteShownFit()
                    }
                    .disabled(editedFittingID == nil)
                } label: {
                    Label("More", systemImage: "ellipsis.circle")
                }
            }
        }
        .onChange(of: isWideEnoughForStatsColumn) { _, isWide in
            if isWide { statsRoute = nil }
        }
        .task {
            guard model == nil else { return }
            loadNameAndNotes(of: fittingIDs.first)
            let model = FittingEditorModel(fittingIDs: fittingIDs, store: fittings, sde: sde)
            self.model = model
            await model.load()
        }
        // Another ship shown: what was typed for the last one is saved to it.
        .onChange(of: shownFittingID) { _, shown in
            guard shown != editedFittingID else { return }
            commitName()
            commitNotes()
            loadNameAndNotes(of: shown)
        }
        .onDisappear {
            commitName()
            commitNotes()
        }
        .alert("Rename Fit", isPresented: $isRenameAlertPresented) {
            TextField("Name", text: $name)
            Button("Cancel", role: .cancel) {
                name = savedName
            }
            Button("Rename", action: commitName)
        }
        .sheet(isPresented: $isNotesSheetPresented) {
            FitNotesEditorView(notes: $notes, onDone: commitNotes)
                .carryingEnvironment(carried)
        }
        .sheet(isPresented: $isSkillsSheetPresented) {
            if let model {
                FitSkillsView(model: model)
                    .carryingEnvironment(carried)
            }
        }
        .sheet(isPresented: $isImplantsSheetPresented) {
            if let model {
                FitImplantsView(model: model, fitName: name)
                    .carryingEnvironment(carried)
            }
        }
        .sheet(isPresented: $isAddShipSheetPresented) {
            if let model {
                FleetShipPickerView(fleetFittingIDs: model.ships.map(\.fittingID)) { picked in
                    for fittingID in picked {
                        model.addShip(fittingID: fittingID)
                    }
                }
                .carryingEnvironment(carried)
            }
        }
        // Not while the implants sheet is up: it carries the same alert.
        .fitCommandAlert(isImplantsSheetPresented ? nil : model)
        .fitUploadFlow(uploader)
        .alert("Could Not Copy", isPresented: Binding(get: { copyError != nil },
                                                       set: { if !$0 { copyError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(copyError ?? "")
        }
    }

    private enum CopyFormat { case eft, dna }

    /// English names whatever the app's language: EFT and the game's chat only understand English.
    /// Built once; the catalog is memory-mapped.
    private static let exporter = Result { try FitExporter(names: TextCatalog.english()) }

    /// Puts the ship on screen, as the engine holds it now, on the pasteboard.
    private func copyShownFit(_ format: CopyFormat) {
        guard let fittingID = shownFittingID, let model else { return }
        let fitName = name
        Task {
            do {
                guard var document = await model.currentDocument(of: fittingID) else {
                    throw FittingEngineError.noShip
                }
                document.name = fitName.isEmpty ? nil : fitName
                let exporter = try Self.exporter.get()
                let result = switch format {
                case .eft: exporter.export(document, as: .eft)
                case .dna: Self.chatLinks(of: document, exporter: exporter)
                }
                UIPasteboard.general.string = result.text
            } catch {
                copyError = error.localizedDescription
            }
        }
    }

    /// The game's chat link, `<url=fitting:DNA>Name</url>`, one line per ship; the exporter writes the bare DNA.
    private static func chatLinks(of document: FitDocument, exporter: FitExporter) -> ExportResult {
        var result = exporter.export(document, as: .dna)
        let ships = document.pilots.compactMap { pilot in pilot.ship.map { (pilot, $0.type) } }
        let lines = result.text.split(separator: "\n", omittingEmptySubsequences: false)
        result.text = zip(lines, ships).map { dna, ship in
            let title = (ship.0.name ?? document.name ?? "")
                .filter { $0 != "<" && $0 != ">" }
                .map { $0.isNewline ? " " : String($0) }
                .joined()
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let label = title.isEmpty
                ? (exporter.names.name(of: ship.1) ?? String(ship.1.rawValue))
                : title
            return "<url=fitting:\(dna)>\(label)</url>"
        }.joined(separator: "\n")
        return result
    }

    private var isStatsColumnShown: Bool {
        (Self.alwaysShowsStatsColumn || isWideEnoughForStatsColumn) && model?.snapshot?.stats != nil
    }

    /// "Upload to EVE", or "Upload Again" for a fit already linked to a game fitting; disabled
    /// while that ship's upload is in flight.
    @ViewBuilder
    private var uploadButton: some View {
        let summary = editedFittingID.flatMap { id in fittings.fits.first { $0.id == id } }
        if let fittingID = editedFittingID, uploader.isUploading(fittingID) {
            Button("Uploading…", systemImage: "icloud.and.arrow.up") {}
                .disabled(true)
        } else {
            Button(summary?.esiFittingID == nil ? "Upload to EVE" : "Upload Again",
                   systemImage: "icloud.and.arrow.up",
                   action: uploadShownFit)
                .disabled(editedFittingID == nil || model?.snapshot == nil)
        }
    }

    /// Uploads the ship on screen as the engine holds it now. A draft is stored first, since the
    /// link patches a record, so it stays in My Fits even if the upload fails. Name and notes being
    /// typed are committed first.
    private func uploadShownFit() {
        guard let fittingID = editedFittingID, let model else { return }
        fittings.persist(fittingID)
        commitName()
        commitNotes()
        uploader.upload(fittingID, fittings: fittings, accounts: accounts) {
            await model.currentDocument(of: fittingID)
        }
    }

    /// The record of the ship on screen: the selected one in a fleet, the first one otherwise.
    private var shownFittingID: UUID? {
        guard let model, let pilot = model.selectedPilot else { return fittingIDs.first }
        return model.fittingID(of: pilot) ?? fittingIDs.first
    }

    private var isFleet: Bool {
        (model?.ships.count ?? 0) > 1
    }

    private var fleetLine: String? {
        guard let model, isFleet else { return nil }
        let dps = model.fleet.reduce(0) { $0 + $1.stats.damage.dps.sum() }
        return String(localized: "\(model.ships.count) ships · \(FitStatFormat.dpsFigure(dps)) DPS")
    }

    @ViewBuilder
    private var content: some View {
        if let model, !model.isLoading {
            if let snapshot = model.snapshot {
                let pilot = snapshot.pilotID
                FittingEditorSections(
                    snapshot: snapshot,
                    fleet: model.members(named: fittings.fits + fittings.drafts),
                    selectedPilot: model.selectedPilot,
                    canAddShip: model.canAddShip,
                    onSelectShip: { model.select($0) },
                    onAddShip: { isAddShipSheetPresented = true },
                    onSetTarget: { subject, target in
                        switch subject {
                        case let .module(id): model.setTarget(target, of: id)
                        case let .drone(id): model.setTarget(target, of: id)
                        }
                    },
                    shipContext: model.shipContext,
                    allowedTypeIDs: model.allowedTypeIDs,
                    tacticalModes: model.tacticalModes,
                    onSetMode: { typeID in
                        model.perform(on: pilot) { session in try await session.setMode(typeID, of: pilot) }
                    },
                    skills: model.skills,
                    damagePattern: model.damagePattern,
                    digest: { subject in await model.digest(of: subject) },
                    onShowSkills: { isSkillsSheetPresented = true },
                    onShowStats: { if !isStatsColumnShown && !Self.alwaysShowsStatsColumn { statsRoute = .stats } },
                    onShowImplants: { isImplantsSheetPresented = true },
                    onShowEnvironment: { environmentRoute = .environment },
                    onShowInfo: { infoRoute = $0 },
                    onShowMutation: { mutationRoute = FitMutationRoute(moduleID: $0) },
                    onRemoveMutation: { model.demutate($0) },
                    onSetState: { id, state in
                        model.perform(on: id.hull.pilot) { session in await session.setState(state, of: id) }
                    },
                    onRemoveModule: { id in
                        model.perform(on: id.hull.pilot) { session in await session.remove(module: id) }
                    },
                    onAddModule: { typeID in
                        model.perform(on: pilot) { session in try await session.add(module: typeID, to: pilot) }
                    },
                    onSetCharge: { id, typeID in
                        model.perform(on: id.hull.pilot) { session in try await session.setCharge(typeID, of: id) }
                    },
                    onApplyChargeToAll: { id, typeID in
                        model.perform(on: id.hull.pilot) { session in await session.setCharge(typeID, ofAllLike: id) }
                    },
                    onRemoveCharge: { id in
                        model.perform(on: id.hull.pilot) { session in await session.removeCharge(of: id) }
                    },
                    onReplace: { subject, typeID in
                        switch subject {
                        case let .module(id):
                            model.perform(on: id.hull.pilot) { session in try await session.replace(id, with: typeID) }
                        case let .drone(id):
                            model.perform(on: id.hull.pilot) { session in try await session.replace(id, with: typeID) }
                        }
                    },
                    onSetDroneCount: { id, count in
                        model.perform(on: id.hull.pilot) { session in await session.setCount(count, of: id) }
                    },
                    onSetDroneActive: { id, isActive in
                        model.perform(on: id.hull.pilot) { session in await session.setActive(isActive, of: id) }
                    },
                    onRemoveDrone: { id in
                        model.perform(on: id.hull.pilot) { session in await session.remove(drone: id) }
                    },
                    onAddDrone: { typeID in
                        model.perform(on: pilot) { session in try await session.add(drone: typeID, to: pilot) }
                    }
                )
            } else {
                ContentUnavailableView {
                    Label("Fit Not Readable", systemImage: "exclamationmark.triangle")
                } description: {
                    Text("This fit's data could not be read. Its name and notes can still be edited.")
                }
            }
        } else {
            ProgressView()
                .controlSize(.large)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func loadNameAndNotes(of fittingID: UUID?) {
        editedFittingID = fittingID
        guard let fittingID, let summary = fittings.summary(of: fittingID) else { return }
        name = summary.name
        notes = summary.notes
        savedName = summary.name
        savedNotes = summary.notes
    }

    /// Deletes the record of the ship on screen (only that one in a fleet) and leaves the screen.
    /// `FittingStore.save`, `rename` and `setNotes` ignore a deleted id, so queued saves and the
    /// `onDisappear` commit cannot recreate it. A draft is dropped.
    private func deleteShownFit() {
        guard let fittingID = editedFittingID else { return }
        editedFittingID = nil
        fittings.delete(fittingID)
        dismiss()
    }

    private func commitName() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let fittingID = editedFittingID, !trimmed.isEmpty, trimmed != savedName else { return }
        fittings.rename(fittingID, to: trimmed)
        name = trimmed
        savedName = trimmed
    }

    private func commitNotes() {
        guard let fittingID = editedFittingID, notes != savedNotes else { return }
        fittings.setNotes(notes, of: fittingID)
        savedNotes = notes
    }
}

enum FleetOverviewRoute: Hashable {
    case overview
}

private extension View {
    /// Nothing for a single fit, so the bar keeps no empty subtitle.
    @ViewBuilder
    func fleetSubtitle(_ subtitle: String?) -> some View {
        if let subtitle {
            navigationSubtitle(subtitle)
        } else {
            self
        }
    }
}

/// The notes field, a sheet because notes need more than one line.
private struct FitNotesEditorView: View {
    @Binding var notes: String
    let onDone: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            HUDList {
                HUDListSection {
                    TextField("Notes", text: $notes, axis: .vertical)
                        .font(.hudBody)
                        .lineLimit(5...15)
                        .hudRow(HUDRowStyle(minHeight: 44, verticalPadding: 12))
                } footer: {
                    HUDFootnote("Saved as the fitting's description when uploaded to EVE.")
                }
            }
            .navigationTitle("Notes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        onDone()
                        dismiss()
                    }
                }
            }
        }
    }
}

/// Which row asked for a sheet: a slot's "+ Add …" (a module of the slot's kind), the drones
/// section's (a drone), or a module row's "Ammo…" (that module's charges).
private enum PickerRequest: Hashable, Identifiable {
    case module(Entity.Module.Slot)
    case drone
    case fighter(Entity.Drone.Squadron)
    case charge(moduleID: ModuleID, groups: [GroupID], size: UInt8?)
    /// An item sheet's "Variations…". `kind` is the subject's slot mapped through
    /// `dogmaItemKind` (`.drone` for a drone stack); the replacement must fit the same slot.
    case variations(subject: FitItemSubject, typeID: TypeID, kind: DogmaItemKind)

    var id: Self { self }
}

/// What an item sheet asked for that cannot happen while it is open. `Info` is a push and the
/// pickers are sheets; starting either inside an open sheet races its dismissal, so the action
/// is parked and `onDismiss` carries it out.
private enum FitItemFollowUp {
    case info(FitInfoRoute)
    case picker(PickerRequest)
    case mutation(ModuleID)
}

/// How the editor presents a fighter squadron type; the fighter picker uses the same name.
extension Entity.Drone.Squadron {
    var sectionLabel: LocalizedStringKey {
        switch self {
        case .none: "Drones"
        case .light: "Light Fighters"
        case .heavy: "Heavy Fighters"
        case .support: "Support Fighters"
        case .standupLight: "Light Fighters (Structure)"
        case .standupHeavy: "Heavy Fighters (Structure)"
        case .standupSupport: "Support Fighters (Structure)"
        }
    }

    var pluralTitle: String {
        switch self {
        case .none: String(localized: "Drones")
        case .light: String(localized: "Light Fighters")
        case .heavy: String(localized: "Heavy Fighters")
        case .support: String(localized: "Support Fighters")
        case .standupLight: String(localized: "Light Fighters (Structure)")
        case .standupHeavy: String(localized: "Heavy Fighters (Structure)")
        case .standupSupport: String(localized: "Support Fighters (Structure)")
        }
    }
}

/// How the editor presents a slot: order and name. The stats screen lists the same slots in
/// the same order, so the table is shared.
extension Entity.Module.Slot {
    /// The order the editor and the stats screen list slots in; display order is not
    /// `Entity.Module.Slot.allCases`. Subsystems come first: on a strategic cruiser the other racks
    /// derive from them.
    ///
    /// No `.mode`: a tactical mode is a module only to the engine; on screen it is the hull's switch
    /// (`FitTacticalModeSection`).
    static let displayOrder: [Entity.Module.Slot] = [.subsystem, .hi, .med, .low, .rig, .service]

    var title: LocalizedStringKey {
        switch self {
        case .hi: "High Slots"
        case .med: "Med Slots"
        case .low: "Low Slots"
        case .rig: "Rigs"
        case .subsystem: "Subsystems"
        case .mode: "Tactical Mode"
        case .service: "Services"
        }
    }

    /// The section heading's name for the rack (`HIGH`); `title` is the longer name.
    var sectionLabel: LocalizedStringKey {
        switch self {
        case .hi: "High"
        case .med: "Medium"
        case .low: "Low"
        case .rig: "Rigs"
        case .subsystem: "Subsystems"
        case .mode: "Tactical Mode"
        case .service: "Services"
        }
    }

    /// The section's "+ Add" row, named for what it adds, as in `ModulePickerView`'s title.
    var addTitle: LocalizedStringKey {
        switch self {
        case .hi, .med, .low, .mode: "Add Module"
        case .rig: "Add Rig"
        case .subsystem: "Add Subsystem"
        case .service: "Add Service"
        }
    }

    /// The slot as the item sheet's caption names it (`HIGH SLOT`), as opposed to the rack.
    var captionName: String {
        switch self {
        case .hi: String(localized: "High slot")
        case .med: String(localized: "Medium slot")
        case .low: String(localized: "Low slot")
        case .rig: String(localized: "Rig slot")
        case .subsystem: String(localized: "Subsystem")
        case .mode: String(localized: "Tactical mode")
        case .service: String(localized: "Service slot")
        }
    }

    /// The item kind that fits a module slot. Not a `rawValue` cast: `Entity.Module.Slot` and
    /// `DogmaItemKind` share case names but not order. A rig slot has two kinds: a structure's rigs
    /// are `.structureRig`.
    func dogmaItemKind(onStructure: Bool) -> DogmaItemKind {
        switch self {
        case .hi: .hi
        case .med: .med
        case .low: .low
        case .rig: onStructure ? .structureRig : .rig
        case .subsystem: .subsystem
        case .mode: .mode
        case .service: .service
        }
    }
}

/// Everything that needs the fit to be open: the header, one section per slot, then drones.
///
/// Takes the snapshot rather than the model. `@LiteQuery` needs a fixed input at `init`; one
/// query reads every `TypeID` the snapshot mentions (ship, modules, charges, drones).
private struct FittingEditorSections: View {
    let snapshot: FitSnapshot
    /// Every ship of the fleet in fleet order, the shown one included. With one element nothing
    /// fleet-related is drawn.
    let fleet: [FleetMember]
    /// The ship the strip marks as shown: the model's selection, which moves before
    /// `snapshot.pilotID` does.
    let selectedPilot: PilotID?
    let canAddShip: Bool
    let onSelectShip: (PilotID) -> Void
    let onAddShip: () -> Void
    let onSetTarget: (FitItemSubject, PilotID?) -> Void
    /// The hull's group and rig size, read once by `FittingEditorModel`. `nil` when that read
    /// failed; the "+ Add …" rows then do nothing.
    let shipContext: ShipContextRow?
    /// Every type the hull is explicitly named to accept, handed to whichever picker opens.
    let allowedTypeIDs: [TypeID]
    let tacticalModes: [TacticalMode]
    let onSetMode: (TypeID) -> Void
    let skills: FitDocument.Skills
    let damagePattern: FitDamagePattern
    let digest: (FitItemSubject) async -> FitItemDigest
    /// The header chips ask for the skills and stats screens through these; the sheets' state
    /// lives in `FittingEditorView`.
    let onShowSkills: () -> Void
    let onShowStats: () -> Void
    let onShowImplants: () -> Void
    let onShowEnvironment: () -> Void
    /// A row's info tap or menu item; the push lives in `FittingEditorView`.
    let onShowInfo: (FitInfoRoute) -> Void
    let onShowMutation: (ModuleID) -> Void
    let onRemoveMutation: (ModuleID) -> Void
    /// Forwarded to each `FitModuleRow`, bound to that row's module id.
    let onSetState: (ModuleID, Entity.Module.State) -> Void
    let onRemoveModule: (ModuleID) -> Void
    let onAddModule: (TypeID) -> Void
    let onSetCharge: (ModuleID, TypeID) -> Void
    let onApplyChargeToAll: (ModuleID, TypeID) -> Void
    let onRemoveCharge: (ModuleID) -> Void
    let onReplace: (FitItemSubject, TypeID) -> Void
    let onSetDroneCount: (DroneID, Int) -> Void
    let onSetDroneActive: (DroneID, Bool) -> Void
    let onRemoveDrone: (DroneID) -> Void
    let onAddDrone: (TypeID) -> Void

    @LiteQuery private var typeNames: [TypeNameRow]
    @LiteQuery private var environmentRows: [EnvironmentEffectRow]
    @LiteQuery private var mutableRows: [ItemIDRow]
    @LiteQuery private var mutaplasmidRows: [MutaplasmidNameRow]
    /// Handed to both sheets: a sheet requested from a menu action is built without the app's
    /// environment (see `CarriedEnvironment`).
    private var carried = CarriedEnvironment()

    /// Which "+ Add …" row is open; local to this view, since presenting a sheet is not an
    /// engine command.
    @State private var pickerRequest: PickerRequest?
    /// The market groups the last module was picked from (root first) and the slot kind it was
    /// picked for. The next "+ Add Module" for the same kind opens pushed into them; another kind
    /// forgets it. Not persisted.
    @State private var lastPickerGroup: (kind: DogmaItemKind, groups: [MarketGroupID])?
    /// Which item's sheet is open; ids only, so the sheet reads the current snapshot.
    @State private var itemSubject: FitItemSubject?
    @State private var followUp: FitItemFollowUp?

    init(
        snapshot: FitSnapshot,
        fleet: [FleetMember],
        selectedPilot: PilotID?,
        canAddShip: Bool,
        onSelectShip: @escaping (PilotID) -> Void,
        onAddShip: @escaping () -> Void,
        onSetTarget: @escaping (FitItemSubject, PilotID?) -> Void,
        shipContext: ShipContextRow?,
        allowedTypeIDs: [TypeID],
        tacticalModes: [TacticalMode],
        onSetMode: @escaping (TypeID) -> Void,
        skills: FitDocument.Skills,
        damagePattern: FitDamagePattern,
        digest: @escaping (FitItemSubject) async -> FitItemDigest,
        onShowSkills: @escaping () -> Void,
        onShowStats: @escaping () -> Void,
        onShowImplants: @escaping () -> Void,
        onShowEnvironment: @escaping () -> Void,
        onShowInfo: @escaping (FitInfoRoute) -> Void,
        onShowMutation: @escaping (ModuleID) -> Void,
        onRemoveMutation: @escaping (ModuleID) -> Void,
        onSetState: @escaping (ModuleID, Entity.Module.State) -> Void,
        onRemoveModule: @escaping (ModuleID) -> Void,
        onAddModule: @escaping (TypeID) -> Void,
        onSetCharge: @escaping (ModuleID, TypeID) -> Void,
        onApplyChargeToAll: @escaping (ModuleID, TypeID) -> Void,
        onRemoveCharge: @escaping (ModuleID) -> Void,
        onReplace: @escaping (FitItemSubject, TypeID) -> Void,
        onSetDroneCount: @escaping (DroneID, Int) -> Void,
        onSetDroneActive: @escaping (DroneID, Bool) -> Void,
        onRemoveDrone: @escaping (DroneID) -> Void,
        onAddDrone: @escaping (TypeID) -> Void
    ) {
        self.snapshot = snapshot
        self.fleet = fleet
        self.selectedPilot = selectedPilot
        self.canAddShip = canAddShip
        self.onSelectShip = onSelectShip
        self.onAddShip = onAddShip
        self.onSetTarget = onSetTarget
        self.shipContext = shipContext
        self.allowedTypeIDs = allowedTypeIDs
        self.tacticalModes = tacticalModes
        self.onSetMode = onSetMode
        self.skills = skills
        self.damagePattern = damagePattern
        self.digest = digest
        self.onShowSkills = onShowSkills
        self.onShowStats = onShowStats
        self.onShowImplants = onShowImplants
        self.onShowEnvironment = onShowEnvironment
        self.onShowInfo = onShowInfo
        self.onShowMutation = onShowMutation
        self.onRemoveMutation = onRemoveMutation
        self.onSetState = onSetState
        self.onRemoveModule = onRemoveModule
        self.onAddModule = onAddModule
        self.onSetCharge = onSetCharge
        self.onApplyChargeToAll = onApplyChargeToAll
        self.onRemoveCharge = onRemoveCharge
        self.onReplace = onReplace
        self.onSetDroneCount = onSetDroneCount
        self.onSetDroneActive = onSetDroneActive
        self.onRemoveDrone = onRemoveDrone
        self.onAddDrone = onAddDrone
        // Sorted by `FitSnapshot.typeIDs`: the query is `@LiteQuery`'s cache key, and state changes
        // rebuild this view with the same ids. A fleet adds the other ships' hulls and whatever they aim
        // here, sorted the same way.
        var typeIDs = snapshot.typeIDs
        if fleet.count > 1 {
            let extra = Set(fleet.map(\.shipTypeID)).union(snapshot.incoming.map(\.typeID))
            typeIDs = Set(typeIDs).union(extra).sorted { $0.rawValue < $1.rawValue }
        }
        _typeNames = LiteQuery(SDEBrowser.typeNames(of: typeIDs))
        _environmentRows = LiteQuery(FittingBrowser.environmentEffects(of: snapshot.environment.sorted { $0.rawValue < $1.rawValue }))
        // Sorted for the same reason. Only unmutated modules can be offered `Mutate…`; a mutated
        // one's type is the abyssal result, which no mutaplasmid maps.
        let plain = Set(snapshot.modules.filter { $0.mutation == nil }.map(\.typeID))
        let mutaplasmids = Set(snapshot.modules.compactMap { $0.mutation?.mutaplasmidTypeID })
        _mutableRows = LiteQuery(FittingBrowser.mutableTypes(among: plain.sorted { $0.rawValue < $1.rawValue }))
        _mutaplasmidRows = LiteQuery(FittingBrowser.mutaplasmidNames(of: mutaplasmids.sorted { $0.rawValue < $1.rawValue }))
    }

    /// `Mutated · Gravid`: the tier from the mutaplasmid's English name, or its whole name when it
    /// has no known tier. Uppercased by the row.
    private func mutationLabel(of module: FitSnapshot.Module) -> String? {
        guard let mutation = module.mutation else { return nil }
        let mutated = String(localized: "Mutated")
        guard let row = mutaplasmidRows.first(where: { $0.id == mutation.mutaplasmidTypeID }) else { return mutated }
        return "\(mutated) · \(MutaplasmidTier.name(of: row.tierSourceName) ?? row.name)"
    }

    /// The chip's name for the first effect in force: the catalog's short name for a wormhole
    /// (`C4 Pulsar`), the full name otherwise, `nil` with none.
    private var environmentLabel: String? {
        guard let first = snapshot.environment.first else { return nil }
        if let effect = EnvironmentCatalog(rows: environmentRows).effect(first) { return effect.shortName }
        return environmentRows.first { $0.id == first }?.name ?? ""
    }

    private var isFleet: Bool { fleet.count > 1 }

    private var shipNames: [PilotID: String] {
        Dictionary(fleet.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
    }

    var body: some View {
        let names = Dictionary(uniqueKeysWithValues: typeNames.map { ($0.id, $0.name) })
        let modulesBySlot = Dictionary(grouping: snapshot.modules, by: \.slot)
        let fleetNames = shipNames
        // Full width up to the stats column: on Mac the list's readable-width cap would stop short.
        HUDList(fillsWidth: true) {
            // Every block is a section; bare rows would stack with no gap.
            if !snapshot.warnings.isEmpty {
                Section {
                    FitLoadWarningsPanel(warnings: snapshot.warnings)
                        .hudBareRow()
                }
            }
            Section {
                FitResourcesHeader(
                    shipTypeID: snapshot.shipTypeID,
                    shipName: names[snapshot.shipTypeID] ?? "",
                    shipContext: shipContext,
                    skills: skills,
                    implantCount: snapshot.implants.count,
                    boosterCount: snapshot.boosters.count,
                    environmentLabel: environmentLabel,
                    resources: snapshot.resources,
                    stats: snapshot.stats,
                    damagePattern: damagePattern.vector,
                    incoming: snapshot.incoming.map { FleetEffectLine($0, shipNames: fleetNames, typeNames: names) },
                    onShowSkills: onShowSkills,
                    onShowImplants: onShowImplants,
                    onShowEnvironment: onShowEnvironment,
                    onShowStats: onShowStats,
                    // `snapshot.pilotID`, not the strip's selection: the route must name the hull
                    // the header draws.
                    onShowShipInfo: {
                        onShowInfo(FitInfoRoute(typeID: snapshot.shipTypeID, target: .ship(snapshot.pilotID)))
                    }
                )
                .hudBareRow()
            }
            if isBareStrategicCruiser(modulesBySlot) {
                Section {
                    HUDEmptyPanel(
                        systemImage: "square.stack.3d.up",
                        title: Text("No Subsystems Yet"),
                        message: Text("A strategic cruiser has no high, medium, low or drone slots until its subsystems are fitted. Fit a core, defensive, offensive and propulsion subsystem.")
                    )
                    .hudBareRow()
                }
            }
            if (snapshot.resources.slots[.mode]?.total ?? 0) > 0, !tacticalModes.isEmpty {
                FitTacticalModeSection(modes: tacticalModes,
                                       current: modulesBySlot[.mode]?.first,
                                       onSelect: onSetMode,
                                       onShowInfo: onShowInfo)
            }
            ForEach(Entity.Module.Slot.displayOrder, id: \.self) { slot in
                slotSection(slot, modules: modulesBySlot[slot] ?? [], names: names)
            }
            droneSection(names: names)
            ForEach(Entity.Drone.Squadron.fighterSquadrons, id: \.self) { squadron in
                fighterSection(squadron, names: names)
            }
            Section {
                HUDFootnote("Tap a module's round control to cycle offline → online → active → overheat; a drone's sends it to space or back to the bay. Tap a module, rig or drone for its key attributes, ammo, variations or removal; swipe left to remove.")
                    .hudBareRow()
                if isFleet {
                    HUDFootnote("Each ship is its own fit with its own pilot. A remote module or drone is aimed at another ship of the fleet from its sheet; the target shows the effect under Incoming.")
                        .hudBareRow()
                }
            }
        }
        .sheet(item: $pickerRequest) { request in
            pickerSheet(for: request)
                .carryingEnvironment(carried)
        }
        .sheet(item: $itemSubject, onDismiss: performFollowUp) { subject in
            itemSheet(for: subject, names: names)
                .carryingEnvironment(carried)
        }
        // Pinned under the navigation bar while the slots scroll; content, not chrome, and only
        // with a second ship.
        .safeAreaBar(edge: .top) {
            if isFleet {
                HUDTabStrip(
                    items: fleet.map { ship in
                        HUDTabStrip.Item(id: ship.id,
                                         typeID: ship.shipTypeID,
                                         title: Text(verbatim: ship.name),
                                         caption: names[ship.shipTypeID].map { Text(verbatim: $0) })
                    },
                    selection: selectedPilot,
                    label: Text("Ships"),
                    onSelect: onSelectShip,
                    onAdd: onAddShip,
                    addLabel: Text("Add Ship"),
                    canAdd: canAddShip
                )
                .padding(.vertical, 8)
            }
        }
    }

    /// The sheet of one module, rig, subsystem or drone stack.
    ///
    /// Anything that leads elsewhere closes the sheet first and parks its destination in `followUp`.
    /// "Remove Ammo" leaves the sheet open and the caption follows the change.
    private func itemSheet(for subject: FitItemSubject, names: [TypeID: String]) -> some View {
        FitItemSheet(
            subject: subject,
            snapshot: snapshot,
            names: names,
            skills: skills,
            fleet: isFleet ? fleet : [],
            digest: digest,
            onSetTarget: onSetTarget,
            onSetState: onSetState,
            onSetDroneCount: onSetDroneCount,
            onSetDroneActive: onSetDroneActive,
            onRequestAmmo: { module in
                close(after: .picker(.charge(moduleID: module.id,
                                             groups: module.chargeGroups,
                                             size: module.chargeSize)))
            },
            onShowAmmoInfo: { id in
                // The charge's own entity, not the module's: their figures differ.
                guard let charge = snapshot.modules.first(where: { $0.id == id })?.charge else { return }
                close(after: .info(FitInfoRoute(typeID: charge, target: .charge(inModule: id))))
            },
            onApplyAmmoToAll: { module in
                guard let charge = module.charge else { return }
                onApplyChargeToAll(module.id, charge)
                itemSubject = nil
            },
            onRemoveAmmo: onRemoveCharge,
            onRequestVariations: { subject in
                guard shipContext != nil, let request = variationsRequest(for: subject) else { return }
                close(after: .picker(request))
            },
            onShowInfo: { subject in
                guard let route = infoRoute(for: subject) else { return }
                close(after: .info(route))
            },
            onRemove: { subject in
                switch subject {
                case let .module(id): onRemoveModule(id)
                case let .drone(id): onRemoveDrone(id)
                }
                itemSubject = nil
            },
            mutableTypeIDs: mutableTypeIDs,
            onShowMutation: { close(after: .mutation($0)) },
            onRemoveMutation: onRemoveMutation
        )
    }

    private var mutableTypeIDs: Set<TypeID> { Set(mutableRows.map(\.id)) }

    private func close(after followUp: FitItemFollowUp) {
        self.followUp = followUp
        itemSubject = nil
    }

    private func performFollowUp() {
        guard let followUp else { return }
        self.followUp = nil
        switch followUp {
        case let .info(route): onShowInfo(route)
        case let .picker(request): pickerRequest = request
        case let .mutation(id): onShowMutation(id)
        }
    }

    /// The variations picker for one subject: a module's slot decides the replacement's kind, a
    /// drone stack is always `.drone`.
    private func variationsRequest(for subject: FitItemSubject) -> PickerRequest? {
        switch subject {
        case let .module(id):
            guard let module = snapshot.modules.first(where: { $0.id == id }) else { return nil }
            return .variations(subject: subject, typeID: module.typeID, kind: module.slot.dogmaItemKind(onStructure: shipContext?.categoryID == CategoryID.structure))
        case let .drone(id):
            guard let drone = snapshot.drones.first(where: { $0.id == id }) else { return nil }
            return .variations(subject: subject, typeID: drone.typeID, kind: drone.squadron.itemKind)
        }
    }

    private func infoRoute(for subject: FitItemSubject) -> FitInfoRoute? {
        switch subject {
        case let .module(id):
            guard let module = snapshot.modules.first(where: { $0.id == id }) else { return nil }
            return FitInfoRoute(typeID: module.typeID, target: .module(id))
        case let .drone(id):
            guard let drone = snapshot.drones.first(where: { $0.id == id }) else { return nil }
            return FitInfoRoute(typeID: drone.typeID, target: .drone(id))
        }
    }

    @ViewBuilder
    private func pickerSheet(for request: PickerRequest) -> some View {
        switch request {
        case let .module(slot):
            itemsPickerSheet(kind: slot.dogmaItemKind(onStructure: shipContext?.categoryID == CategoryID.structure), slotName: slot.captionName, onSelect: onAddModule)
        case .drone:
            // No hull filter beyond `allowedTypeIDs`: a drone has no slot or rig size.
            ModulePickerView(
                content: .drones(
                    allowed: allowedTypeIDs,
                    hullName: typeNames.first { $0.id == snapshot.shipTypeID }?.name ?? "",
                    bay: snapshot.resources.droneBay,
                    bandwidth: snapshot.resources.droneBandwidth
                ),
                onSelect: onAddDrone
            )
        case let .fighter(squadron):
            // A fighter goes in through the drone command; the engine files it under its squadron.
            ModulePickerView(
                content: .fighters(
                    squadron: squadron,
                    allowed: allowedTypeIDs,
                    hullName: typeNames.first { $0.id == snapshot.shipTypeID }?.name ?? "",
                    hangar: snapshot.resources.fighterHangar,
                    slots: snapshot.resources.squadrons[squadron] ?? SlotCapacity(used: 0, total: 0)
                ),
                onSelect: onAddDrone
            )
        case let .charge(moduleID, groups, size):
            // No `shipContext`: a charge answers to the module in the fit, not to the hull. The sheet's
            // name, charge and module count are read from the snapshot as it is built.
            let module = snapshot.modules.first { $0.id == moduleID }
            let moduleTypeID = module?.typeID
            ModulePickerView(
                content: .charges(
                    groups: groups,
                    size: size,
                    loaded: module?.charge,
                    moduleName: typeNames.first { $0.id == moduleTypeID }?.name ?? "",
                    sameTypeCount: snapshot.modules.filter { $0.typeID == moduleTypeID }.count
                ),
                onSelect: { typeID in onSetCharge(moduleID, typeID) },
                onApplyToAll: { typeID in onApplyChargeToAll(moduleID, typeID) }
            )
        case let .variations(subject, typeID, kind):
            // Same hull filters as "+ Add …": a variation is a replacement the ship must accept.
            if let shipContext {
                ModulePickerView(
                    content: .variations(kind: kind, typeID: typeID, rigSize: shipContext.rigSize,
                                          structureHull: shipContext.categoryID == CategoryID.structure,
                                          allowed: allowedTypeIDs)
                ) { newTypeID in
                    onReplace(subject, newTypeID)
                }
            }
        }
    }

    @ViewBuilder
    private func itemsPickerSheet(kind: DogmaItemKind, slotName: String, onSelect: @escaping (TypeID) -> Void) -> some View {
        // `shipContext` is `nil` only when its SDE read failed, and the "+ Add …" rows then refuse to
        // set `pickerRequest`; the guard avoids a force unwrap.
        if let shipContext {
            ModulePickerView(
                content: .items(kind: kind, rigSize: shipContext.rigSize,
                                structureHull: shipContext.categoryID == CategoryID.structure,
                                allowed: allowedTypeIDs,
                                slotName: slotName,
                                hullName: typeNames.first { $0.id == snapshot.shipTypeID }?.name ?? ""),
                initialGroups: lastPickerGroup.flatMap { $0.kind == kind ? $0.groups : nil } ?? [],
                onSelectFromGroup: { lastPickerGroup = (kind, $0) },
                onSelect: { typeID in
                    if lastPickerGroup?.kind != kind { lastPickerGroup = nil }
                    onSelect(typeID)
                }
            )
        }
    }

    /// A hull with subsystem slots and nothing in them, such as a new strategic cruiser: every
    /// other rack is empty until a subsystem gives it sockets. The note says so.
    private func isBareStrategicCruiser(_ modulesBySlot: [Entity.Module.Slot: [FitSnapshot.Module]]) -> Bool {
        let capacity = snapshot.resources.slots[.subsystem] ?? SlotCapacity(used: 0, total: 0)
        return capacity.total > 0 && (modulesBySlot[.subsystem] ?? []).isEmpty
    }

    /// A slot section is drawn when the hull has the slot (`capacity.total > 0`) or something sits
    /// in it anyway. A bare T3C has no high, medium or low slots until its subsystems are fitted, so
    /// its subsystem section (`0/4`) is drawn.
    @ViewBuilder
    private func slotSection(_ slot: Entity.Module.Slot, modules: [FitSnapshot.Module], names: [TypeID: String]) -> some View {
        let capacity = snapshot.resources.slots[slot] ?? SlotCapacity(used: 0, total: 0)
        if capacity.total > 0 || !modules.isEmpty {
            HUDListSection {
                ForEach(modules) { module in
                    HUDSwipeRow(onRemove: { onRemoveModule(module.id) }, inContextMenu: false, allowsFullSwipe: true) {
                        FitModuleRow(
                            module: module,
                            typeName: names[module.typeID] ?? "",
                            chargeName: module.charge.flatMap { names[$0] },
                            onSetState: { onSetState(module.id, $0) },
                            onSelect: { itemSubject = .module(module.id) },
                            targetName: module.target.flatMap { shipNames[$0] },
                            mutationLabel: mutationLabel(of: module)
                        )
                    }
                    .contextMenu { moduleMenu(module, names: names) }
                }
                // No free socket, no "+ Add" row. An over-capacity rack still lists every module.
                if capacity.available > 0 {
                    HUDAddRow(title: slot.addTitle, caption: freeSlotsText(capacity)) {
                        guard shipContext != nil else { return }
                        pickerRequest = .module(slot)
                    }
                }
            } header: {
                FitSectionHeader(
                    title: Text(slot.sectionLabel),
                    spans: [.init(capacity)] + (slot == .hi ? hardpointSpans : [])
                )
            }
        }
    }

    /// A module row's context menu (right click on Mac, long press on iOS): the item sheet's
    /// actions (`FitItemSheet.actions(for:)`), so a mouse reaches everything without opening the
    /// sheet. The target and the digest stay in the sheet.
    @ViewBuilder
    private func moduleMenu(_ module: FitSnapshot.Module, names: [TypeID: String]) -> some View {
        let subject = FitItemSubject.module(module.id)
        let typeName = names[module.typeID] ?? ""
        Button {
            itemSubject = subject
        } label: {
            Label("Details…", systemImage: "list.bullet.rectangle")
        }
        if module.maxAllowedState > .offline {
            Picker(selection: Binding(get: { module.state },
                                      set: { onSetState(module.id, $0) })) {
                ForEach(Entity.Module.State.ladder(upTo: module.maxAllowedState), id: \.self) { state in
                    Text(verbatim: state.title).tag(state)
                }
            } label: {
                Label("State", systemImage: "power")
            }
            .pickerStyle(.menu)
        }
        if !module.chargeGroups.isEmpty {
            Section {
                Button {
                    pickerRequest = .charge(moduleID: module.id, groups: module.chargeGroups, size: module.chargeSize)
                } label: {
                    Label("Ammo…", systemImage: "line.3.horizontal.decrease")
                }
                if let charge = module.charge {
                    Button {
                        onShowInfo(FitInfoRoute(typeID: charge, target: .charge(inModule: module.id)))
                    } label: {
                        Label("Ammo Info", systemImage: "info.circle")
                    }
                    if snapshot.modules.count(where: { $0.typeID == module.typeID }) > 1 {
                        Button {
                            onApplyChargeToAll(module.id, charge)
                        } label: {
                            Label("Apply Ammo to All \(typeName)", systemImage: "square.grid.2x2")
                        }
                    }
                    Button {
                        onRemoveCharge(module.id)
                    } label: {
                        Label("Remove Ammo", systemImage: "minus.circle")
                    }
                }
            }
        }
        Section {
            // A mutated module is edited or demutated, never swapped.
            if module.mutation != nil {
                Button {
                    onShowMutation(module.id)
                } label: {
                    Label("Edit Mutation…", systemImage: "wand.and.sparkles")
                }
                Button {
                    onRemoveMutation(module.id)
                } label: {
                    Label("Remove Mutation", systemImage: "minus.circle")
                }
            } else {
                if shipContext != nil, let request = variationsRequest(for: subject) {
                    Button {
                        pickerRequest = request
                    } label: {
                        Label("Variations…", systemImage: "arrow.left.arrow.right")
                    }
                }
                if mutableTypeIDs.contains(module.typeID) {
                    Button {
                        onShowMutation(module.id)
                    } label: {
                        Label("Mutate…", systemImage: "wand.and.sparkles")
                    }
                }
            }
            if let route = infoRoute(for: subject) {
                Button {
                    onShowInfo(route)
                } label: {
                    Label("Info", systemImage: "info.circle")
                }
            }
            HUDCopyButton("Copy Name", value: typeName)
        }
        Section {
            Button(role: .destructive) {
                onRemoveModule(module.id)
            } label: {
                Label("Remove", systemImage: "trash")
            }
        }
    }

    @ViewBuilder
    private func droneMenu(_ drone: FitSnapshot.Drone, names: [TypeID: String]) -> some View {
        let subject = FitItemSubject.drone(drone.id)
        Button {
            itemSubject = subject
        } label: {
            Label("Details…", systemImage: "list.bullet.rectangle")
        }
        Button {
            onSetDroneActive(drone.id, !drone.isActive)
        } label: {
            if drone.isActive {
                Label("Return to Bay", systemImage: "arrow.down.circle")
            } else {
                Label("Launch", systemImage: "arrow.up.circle")
            }
        }
        .disabled(!snapshot.canLaunch(drone))
        Section {
            if let route = infoRoute(for: subject) {
                Button {
                    onShowInfo(route)
                } label: {
                    Label("Info", systemImage: "info.circle")
                }
            }
            if shipContext != nil, let request = variationsRequest(for: subject) {
                Button {
                    pickerRequest = request
                } label: {
                    Label("Variations…", systemImage: "arrow.left.arrow.right")
                }
            }
            HUDCopyButton("Copy Name", value: names[drone.typeID] ?? "")
        }
        Section {
            Button(role: .destructive) {
                onRemoveDrone(drone.id)
            } label: {
                Label("Remove", systemImage: "trash")
            }
        }
    }

    /// Turrets and launchers for the high-slot heading, shown when the hull has the hardpoints or
    /// something uses them (`TURRETS 1/0` in red).
    private var hardpointSpans: [FitSectionHeader.Span] {
        let turrets = snapshot.resources.turrets
        let launchers = snapshot.resources.launchers
        var spans: [FitSectionHeader.Span] = []
        if turrets.total > 0 || turrets.used > 0 {
            spans.append(.init(String(localized: "Turrets \(turrets.used)/\(turrets.total)"),
                               isOverloaded: turrets.isOverloaded))
        }
        if launchers.total > 0 || launchers.used > 0 {
            spans.append(.init(String(localized: "Launchers \(launchers.used)/\(launchers.total)"),
                               isOverloaded: launchers.isOverloaded))
        }
        return spans
    }

    /// Empty sections are not drawn; keyed on drone bay volume, not a slot count.
    @ViewBuilder
    private func droneSection(names: [TypeID: String]) -> some View {
        let resources = snapshot.resources
        let drones = snapshot.drones.filter { !$0.isFighter }
        if resources.droneBay.total > 0 || !drones.isEmpty {
            HUDListSection {
                ForEach(drones) { drone in
                    // Standard swipe-remove (`HUDSwipeRow`): the system owns the gesture and the open row.
                    HUDSwipeRow(onRemove: { onRemoveDrone(drone.id) }, inContextMenu: false, allowsFullSwipe: true) {
                        FitDroneRow(
                            drone: drone,
                            typeName: names[drone.typeID] ?? "",
                            onSetActive: { onSetDroneActive(drone.id, $0) },
                            onSelect: { itemSubject = .drone(drone.id) },
                            targetName: drone.target.flatMap { shipNames[$0] }
                        )
                    }
                    .contextMenu { droneMenu(drone, names: names) }
                }
                // A drone bay's free figure is volume (room for another stack), not how many more drones
                // may launch (the heading's `IN SPACE`).
                HUDAddRow(title: "Add Drone", caption: freeVolumeText(resources.droneBay)) {
                    guard shipContext != nil else { return }
                    pickerRequest = .drone
                }
            } header: {
                FitSectionHeader(
                    title: Text("Drones"),
                    spans: [.init(String(localized: "\(resources.dronesInSpace.used)/\(resources.dronesInSpace.total) in space"),
                                   isOverloaded: resources.dronesInSpace.isOverloaded)]
                )
            }
        }
    }

    /// One section per fighter squadron type the hull has slots for (or has fighters of), drawn
    /// like a rack: a squadron takes one slot of its type; the "+ Add" row goes once they are full.
    /// Fighter tubes cap how many squadrons launch at once, so the heading shows them and a
    /// squadron added with every tube taken goes in docked. Drone rules (bay, bandwidth, five in
    /// space) do not apply.
    @ViewBuilder
    private func fighterSection(_ squadron: Entity.Drone.Squadron, names: [TypeID: String]) -> some View {
        let resources = snapshot.resources
        if let capacity = resources.squadrons[squadron] {
            let fighters = snapshot.drones.filter { $0.squadron == squadron }
            let free = capacity.available
            HUDListSection {
                ForEach(fighters) { fighter in
                    HUDSwipeRow(onRemove: { onRemoveDrone(fighter.id) }, inContextMenu: false, allowsFullSwipe: true) {
                        FitDroneRow(
                            drone: fighter,
                            typeName: names[fighter.typeID] ?? "",
                            onSetActive: { onSetDroneActive(fighter.id, $0) },
                            onSelect: { itemSubject = .drone(fighter.id) },
                            targetName: fighter.target.flatMap { shipNames[$0] },
                            canLaunch: snapshot.canLaunch(fighter)
                        )
                    }
                    .contextMenu { droneMenu(fighter, names: names) }
                }
                if free > 0 {
                    HUDAddRow(title: "Add Fighter", caption: freeVolumeText(resources.fighterHangar)) {
                        guard shipContext != nil else { return }
                        pickerRequest = .fighter(squadron)
                    }
                }
            } header: {
                FitSectionHeader(
                    title: Text(squadron.sectionLabel),
                    spans: [
                        .init(capacity),
                        .init(String(localized: "Tubes \(resources.fighterTubes.used)/\(resources.fighterTubes.total)"),
                              isOverloaded: resources.fighterTubes.isOverloaded),
                    ]
                )
            }
        }
    }

    // Captions are written in capitals outright: upper-casing a volume's `m³` unit would say
    // megacubic.

    private func freeSlotsText(_ capacity: SlotCapacity) -> String {
        String(localized: "\(capacity.available) FREE")
    }

    private func freeVolumeText(_ bay: Resource) -> String {
        String(localized: "\(max(bay.available, 0).resourceFigure) m³ FREE")
    }
}

/// What the engine refused while loading this document: a module whose type is gone from the
/// static data, a charge that does not fit its module.
///
/// Shown above the header, not in an alert: this is a standing fact about the fit, and the first
/// successful command writes the document back without the parts that did not load, making the
/// panel the only record of them. Built from `HUDPanel(tone: .warn)`; not a `danger`, since the
/// player cannot act on it from here.
private struct FitLoadWarningsPanel: View {
    let warnings: [String]

    var body: some View {
        HUDPanel(tone: .warn) {
            HUDPanelHeader(title: Text("This Fit")) {
                HUDStatusChip(text: Text("Partly loaded"), color: .hudWarn,
                              mark: .symbol("exclamationmark.triangle.fill"))
            }
            VStack(alignment: .leading, spacing: 6) {
                // Keyed by position: two engine sentences can read alike for different modules.
                ForEach(warnings.indices, id: \.self) { index in
                    Text(verbatim: warnings[index])
                }
            }
            .font(.hudCaption)
            .foregroundStyle(Color.hudWarnNoteInk)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, HUDMetrics.gutter)
            .padding(.top, 12)
            .padding(.bottom, 14)
        }
    }
}

/// The heading of every editor section on one line: the label, the rule, then the section's
/// figures (`HIGH ──── 4/4 · TURRETS 3/4`). Each figure goes `hudDanger` on its own when over its
/// budget; a fit may be over, and this is where the overload shows.
private struct FitSectionHeader: View {
    struct Span: Identifiable {
        var text: String
        var isOverloaded: Bool
        var id: String { text }

        init(_ text: String, isOverloaded: Bool) {
            self.text = text
            self.isOverloaded = isOverloaded
        }

        init(_ capacity: SlotCapacity) {
            self.init("\(capacity.used)/\(capacity.total)", isOverloaded: capacity.isOverloaded)
        }
    }

    let title: Text
    let spans: [Span]

    var body: some View {
        HUDSectionHeader(title) {
            HStack(spacing: 6) {
                ForEach(Array(spans.enumerated()), id: \.element.id) { index, span in
                    if index > 0 {
                        Text(verbatim: "·")
                    }
                    Text(verbatim: span.text)
                        .foregroundStyle(span.isOverloaded ? Color.hudDanger : Color.hudInkMuted)
                }
            }
        }
    }
}

#Preview {
    let container = try! ModelContainer(for: Fitting.self, configurations: .init(isStoredInMemoryOnly: true))
    let store = FittingStore(context: container.mainContext)
    let id = store.create(
        shipTypeID: 17740,
        name: "Vindicator — blaster brawl",
        document: FitDocument(pilots: [.init(skills: .init(default: 5), ship: .init(type: 17740))])
    )
    return NavigationStack {
        FittingEditorView(fittingID: id)
    }
    .environment(store)
    .environment(SDEStore())
    .environment(AccountStore())
    .environment(MarketSheet())
    // Nothing else holds the container, and the first read happens in `.task` after this closure
    // returns: a `ModelContext` does not keep its container alive, and reading through a released
    // one crashes SwiftData.
    .modelContainer(container)
}
