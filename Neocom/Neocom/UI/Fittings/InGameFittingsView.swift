import DogmaKit
import LiteRow
import LiteRowUI
import SDEKit
import SwiftUI

/// The "In Game" tab: a read-only mirror of the signed-in character's fittings from `FittingsSheet`.
///
/// A tap opens a fitting in the editor as a draft copy; a swipe deletes it from the game after
/// confirmation; the context menu holds the rest.
struct InGameFittingsView: View {
    @Environment(AccountStore.self) private var accounts

    var body: some View {
        if let sheet = accounts.currentFittings {
            InGameFittingsScreen(sheet: sheet)
        } else {
            HUDList {
                Section {
                    HUDEmptyPanel(title: Text("No Character"),
                                  message: Text("Sign in with EVE Online to see the fittings saved in the game."))
                        .hudBareRow()
                }
            }
        }
    }
}

/// Distinguishes the loading, failed and loaded states of `sheet.snapshot`; a stale value is
/// still shown.
private struct InGameFittingsScreen: View {
    let sheet: FittingsSheet

    var body: some View {
        Group {
            if let fittings = sheet.snapshot.value {
                InGameFittingsList(sheet: sheet, fittings: fittings)
            } else if case let .failed(error) = sheet.snapshot.state {
                ContentUnavailableView {
                    Label("Fittings Unavailable", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(error.localizedDescription)
                } actions: {
                    Button("Retry") {
                        Task { await sheet.refresh() }
                    }
                }
            } else {
                ProgressView()
                    .controlSize(.large)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task { await sheet.ensureFresh() }
        .refreshableCommand { await sheet.refresh() }
    }
}

/// The list once a value exists. Ship names come from one query over every fitting's
/// `shipTypeID`, built in `init` by `@LiteQuery`.
private struct InGameFittingsList: View {
    let sheet: FittingsSheet
    let fittings: [ESIFitting]

    @Environment(FittingStore.self) private var fittingStore
    @Environment(AccountStore.self) private var accounts
    /// The section's database, handed to the pushed editor, which does not inherit it.
    @Environment(\.liteDatabase) private var database

    @LiteQuery private var ships: [ShipRow]

    /// Loaded in `.task`, not `init`: it opens a file, and `State(initialValue:)` evaluates its
    /// argument on every re-creation. `nil` when the catalog cannot be loaded.
    @State private var typeCatalog: TypeCatalog?

    /// Set by the swipe or the context menu; the deletion runs from the dialog's button. Deleting
    /// a game fitting is irreversible on the server.
    @State private var fitPendingDeletion: ESIFitting?
    @State private var actionError: (any Error)?
    /// Set after "Copy to My Fits" when part of the fitting could not be carried over.
    @State private var copyWarnings: [String]?
    @State private var pushedRoute: FittingRoute?
    /// A draft that lost something on the way: opened once the warnings are read, otherwise dropped.
    @State private var pendingFitID: UUID?
    @State private var openWarnings: [String]?

    init(sheet: FittingsSheet, fittings: [ESIFitting]) {
        self.sheet = sheet
        self.fittings = fittings
        let shipTypeIDs = Array(Set(fittings.map { TypeID(rawValue: UInt32(clamping: $0.shipTypeID)) }))
        _ships = LiteQuery(FittingBrowser.ships(shipTypeIDs))
    }

    var body: some View {
        // Keyed by the raw ESI id to match `fitting.shipTypeID`.
        let shipByID = Dictionary(ships.map { (Int64($0.id.rawValue), $0) }, uniquingKeysWith: { first, _ in first })

        HUDList {
            if hasStatus {
                Section {
                    status.hudBareRow()
                }
            }
            if fittings.isEmpty {
                Section {
                    HUDEmptyPanel(title: Text("No Fittings"),
                                  message: Text("Fittings are created in the EVE client. Save one there and it appears here."))
                        .hudBareRow()
                } header: {
                    HUDSectionHeader(sectionTitle)
                        .hudListHeader()
                } footer: {
                    footnote.hudListFooter()
                }
            } else {
                HUDListSection(fittings, row: { fitting in
                    row(for: fitting, ship: shipByID[fitting.shipTypeID])
                }, header: {
                    HUDSectionHeader(sectionTitle)
                }, footer: {
                    footnote
                })
            }
        }
        .confirmationDialog(
            "Delete Fitting?",
            isPresented: Binding(
                get: { fitPendingDeletion != nil },
                set: { isPresented in if !isPresented { fitPendingDeletion = nil } }
            ),
            presenting: fitPendingDeletion
        ) { fitting in
            Button("Delete \(fitting.name)", role: .destructive) {
                performDelete(fitting)
            }
        } message: { _ in
            Text("This deletes the fitting in the game.")
        }
        .alert(
            "Something Went Wrong",
            isPresented: Binding(
                get: { actionError != nil },
                set: { isPresented in if !isPresented { actionError = nil } }
            ),
            presenting: actionError
        ) { _ in
            Button("OK", role: .cancel) {}
        } message: { error in
            Text(error.localizedDescription)
        }
        .task {
            if typeCatalog == nil { typeCatalog = try? TypeCatalog() }
        }
        .navigationDestination(item: $pushedRoute) { route in
            if let database {
                route.destination.liteDatabase(database)
            } else {
                route.destination
            }
        }
        .alert(
            "Not Everything Was Copied",
            isPresented: Binding(
                get: { openWarnings != nil },
                set: { isPresented in if !isPresented { openWarnings = nil } }
            ),
            presenting: openWarnings
        ) { _ in
            Button("Open Fit") {
                if let pendingFitID { pushedRoute = .editor(pendingFitID) }
                pendingFitID = nil
            }
            Button("OK", role: .cancel) {
                if let pendingFitID { fittingStore.discardDraft(pendingFitID) }
                pendingFitID = nil
            }
        } message: { warnings in
            Text(warnings.joined(separator: "\n"))
        }
        .alert(
            "Not Everything Was Copied",
            isPresented: Binding(
                get: { copyWarnings != nil },
                set: { isPresented in if !isPresented { copyWarnings = nil } }
            ),
            presenting: copyWarnings
        ) { _ in
            Button("OK", role: .cancel) {}
        } message: { warnings in
            Text(warnings.joined(separator: "\n"))
        }
    }

    private var sectionTitle: Text {
        let count = String(localized: "\(fittings.count) Fittings")
        guard let name = accounts.currentAccount?.characterName else { return Text(verbatim: count) }
        return Text(verbatim: "\(name) · \(count)")
    }

    private var footnote: HUDFootnote {
        HUDFootnote("Changes made in the game can take up to five minutes to appear here. Tap a fitting to open a copy of it; the copy is added to My Fits once you change or save it. Swipe a fitting to delete it from the game; touch and hold to copy it to My Fits right away.")
    }

    private var hasStatus: Bool {
        if case .failed = sheet.snapshot.state { return true }
        return sheet.snapshot.fetchedAt != nil
    }

    /// The snapshot's age, or the reason the last refresh failed. The data stays on screen.
    @ViewBuilder
    private var status: some View {
        if case let .failed(error) = sheet.snapshot.state {
            HUDStatusChip(text: Text(error.localizedDescription), color: .hudDanger, mark: .symbol("exclamationmark.triangle.fill"))
                .padding(.horizontal, 4)
        } else if let fetchedAt = sheet.snapshot.fetchedAt {
            HUDStatusChip(text: Text("Updated \(fetchedAt, format: .relative(presentation: .named))"),
                          color: .hudInkMuted, mark: .dot)
                .padding(.horizontal, 4)
        }
    }

    @ViewBuilder
    private func row(for fitting: ESIFitting, ship: ShipRow?) -> some View {
        HUDSwipeRow(title: "Delete", onRemove: { fitPendingDeletion = fitting }, inContextMenu: false) {
            Button {
                openInEditor(fitting)
            } label: {
                InGameFittingRow(fitting: fitting, ship: ship)
            }
            .hudRowButton(InGameFittingRow.rowStyle)
            .contextMenu {
                Button("Copy to My Fits", systemImage: "doc.on.doc") {
                    copyToMyFits(fitting)
                }
                Divider()
                Button("Delete", systemImage: "trash", role: .destructive) {
                    fitPendingDeletion = fitting
                }
            }
        }
    }

    /// Opens the game fitting as a draft, stored on its first change or "Save" and dropped when
    /// the editor closes without either (see `FittingStore.createDraft`). Not linked to the game
    /// fitting.
    private func openInEditor(_ fitting: ESIFitting) {
        if typeCatalog == nil { typeCatalog = try? TypeCatalog() }
        guard let typeCatalog else {
            actionError = CopyFittingError.catalogUnavailable
            return
        }
        let (newID, warnings) = fittingStore.createDraft(from: fitting, catalog: typeCatalog)
        if warnings.isEmpty {
            pushedRoute = .editor(newID)
        } else {
            pendingFitID = newID
            openWarnings = warnings
        }
    }

    private func performDelete(_ fitting: ESIFitting) {
        Task {
            do {
                try await sheet.delete(id: fitting.id)
            } catch {
                actionError = error
            }
        }
    }

    /// `FitDocument(fitting, catalog:warnings:)` never fails; `warnings` lists what could not be
    /// carried over (dropped cargo, an unrecognized flag).
    private func copyToMyFits(_ fitting: ESIFitting) {
        guard let typeCatalog else {
            actionError = CopyFittingError.catalogUnavailable
            return
        }
        var warnings: [String] = []
        let document = FitDocument(fitting, catalog: typeCatalog, warnings: &warnings)
        let shipTypeID = TypeID(rawValue: UInt32(clamping: fitting.shipTypeID))
        let newID = fittingStore.create(shipTypeID: shipTypeID,
                                        name: fitting.name,
                                        document: document,
                                        notes: fitting.fittingDescription)
        fittingStore.link(newID, esiFittingID: fitting.id, characterID: sheet.characterID)
        if !warnings.isEmpty {
            copyWarnings = warnings
        }
    }
}

/// One row of the "In Game" list; no "in game" badge, since every fitting here is one.
private struct InGameFittingRow: View {
    let fitting: ESIFitting
    let ship: ShipRow?

    var body: some View {
        HStack(spacing: 12) {
            HUDItemIcon(typeID: TypeID(rawValue: UInt32(clamping: fitting.shipTypeID)), size: 44)
            HUDRowTitle(title: Text(fitting.name), subtitle: subtitle,
                        font: HUDFont.display(15, weight: .semibold, relativeTo: .body))
            Spacer(minLength: 4)
            HUDChevron()
        }
        .hudRow(Self.rowStyle)
    }

    /// Same cell as `FittingRow`.
    static let rowStyle = HUDRowStyle(minHeight: 60)

    private var subtitle: Text {
        let itemCount = fitting.items.count
        let items = String(localized: "\(itemCount) items")
        return Text(verbatim: ship.map { "\($0.name) · \(items)" } ?? items)
    }
}

nonisolated enum CopyFittingError: LocalizedError {
    case catalogUnavailable

    var errorDescription: String? {
        switch self {
        case .catalogUnavailable:
            String(localized: "The type catalog could not be loaded, so this fitting cannot be copied or opened.")
        }
    }
}

#Preview {
    NavigationStack {
        InGameFittingsView()
    }
    .environment(AccountStore())
    .environment(SDEStore())
}
