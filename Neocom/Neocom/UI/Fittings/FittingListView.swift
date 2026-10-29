import DogmaKit
import LiteRow
import LiteRowUI
import SDEKit
import SwiftUI

/// Reads the player's fits from the environment and hands the fixed list to `FittingListBody`;
/// `@LiteQuery` builds its query in `init`, so the ship ids must be known by then.
///
/// Also checks whether the pasteboard holds text, on appearing, on returning to the foreground and
/// when it changes, to offer "Paste from Clipboard"; the text itself is read only on the tap.
/// A failed paste is shown on the row until the screen reappears or the pasteboard changes.
struct FittingListView: View {
    /// Opens a fit created here in the editor.
    let open: (UUID) -> Void

    @State private var canPaste = false
    @State private var pasteFailure: PasteFailure?
    @State private var failedChangeCount = 0

    @Environment(FittingStore.self) private var fittings
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        FittingListBody(fits: fittings.fits, canPaste: canPaste, pasteFailure: $pasteFailure, open: open)
            .onAppear {
                pasteFailure = nil
                canPaste = FitPasteboard.hasText
            }
            .onChange(of: pasteFailure) { _, failure in
                if failure != nil { failedChangeCount = FitPasteboard.changeCount }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { refreshPasteboard() }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIPasteboard.changedNotification)) { _ in
                refreshPasteboard()
            }
    }

    private func refreshPasteboard() {
        if pasteFailure != nil, FitPasteboard.changeCount != failedChangeCount { pasteFailure = nil }
        canPaste = FitPasteboard.hasText
    }
}

/// Why the last paste produced no fit.
private enum PasteFailure {
    case denied
    case noFit

    var text: Text {
        switch self {
        case .denied: Text("Paste not allowed")
        case .noFit: Text("No fit in EFT or DNA format")
        }
    }

    var message: String {
        switch self {
        case .denied: String(localized: "Paste not allowed")
        case .noFit: String(localized: "No fit in EFT or DNA format")
        }
    }
}

enum FittingOrder: String, CaseIterable, Identifiable {
    case byShip
    case recent

    var id: Self { self }

    var title: LocalizedStringKey {
        switch self {
        case .byShip: "By Ship"
        case .recent: "Recent"
        }
    }
}

private struct FittingListBody: View {
    let fits: [FittingSummary]
    let canPaste: Bool
    @Binding var pasteFailure: PasteFailure?
    let open: (UUID) -> Void

    @State private var order: FittingOrder = .byShip
    @State private var searchText = ""
    @State private var renamingFit: FittingSummary?
    @State private var renameText = ""
    @State private var uploader = FitUploader()
    @State private var isReadingClipboard = false
    /// A pasted fit that lost something on import, created once the player confirms.
    @State private var lossyPaste: PastedFit?

    @Environment(FittingStore.self) private var fittings
    @Environment(AccountStore.self) private var accounts

    @LiteQuery private var ships: [ShipRow]

    init(fits: [FittingSummary], canPaste: Bool, pasteFailure: Binding<PasteFailure?>,
         open: @escaping (UUID) -> Void) {
        self.fits = fits
        self.canPaste = canPaste
        _pasteFailure = pasteFailure
        self.open = open
        let shipTypeIDs = Array(Set(fits.map(\.shipTypeID)))
        _ships = LiteQuery(FittingBrowser.ships(shipTypeIDs))
    }

    var body: some View {
        // Built once per pass: a per-row lookup would rebuild it for every row on each keystroke
        // in the search field.
        let shipByID = Dictionary(ships.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let visibleFits = filteredFits(shipByID)
        let showsPaste = canPaste && searchText.isEmpty
        return Group {
            if fits.isEmpty {
                HUDList {
                    if showsPaste { pasteSection }
                    Section {
                        HUDEmptyPanel(title: Text("No Fits"), message: Text("Tap ＋ to create a fit."))
                            .hudBareRow()
                    }
                }
            } else if visibleFits.isEmpty {
                ContentUnavailableView.search(text: searchText)
                    .hudScreen()
            } else {
                HUDList {
                    if showsPaste { pasteSection }
                    switch order {
                    case .byShip:
                        ForEach(sections(of: visibleFits, shipByID)) { section in
                            HUDListSection(section.fits, row: { fit in
                                row(for: fit, ship: shipByID[fit.shipTypeID])
                            }, header: {
                                HUDSectionHeader(Text(verbatim: section.title))
                            })
                        }
                    case .recent:
                        HUDListSection(visibleFits, row: { fit in
                            row(for: fit, ship: shipByID[fit.shipTypeID])
                        }, header: {
                            HUDSectionHeader(Text("Recent"))
                        })
                    }
                    Section {
                        HUDFootnote("Swipe a fit to delete it; touch and hold to rename, duplicate, upload or delete it.")
                            .hudBareRow()
                    }
                }
            }
        }
        .searchable(text: $searchText, prompt: Text("Fit or ship name"))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Picker("Order", selection: $order) {
                        ForEach(FittingOrder.allCases) { order in
                            Text(order.title).tag(order)
                        }
                    }
                } label: {
                    Label("Order", systemImage: "arrow.up.arrow.down")
                }
            }
        }
        .alert(
            "Rename Fit",
            isPresented: Binding(
                get: { renamingFit != nil },
                set: { isPresented in if !isPresented { renamingFit = nil } }
            ),
            presenting: renamingFit
        ) { fit in
            TextField("Name", text: $renameText)
            Button("Cancel", role: .cancel) {}
            Button("Rename") {
                let trimmed = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return }
                fittings.rename(fit.id, to: trimmed)
            }
        }
        .fitUploadFlow(uploader)
        .alert(
            "Not Everything Was Copied",
            isPresented: Binding(
                get: { lossyPaste != nil },
                set: { isPresented in if !isPresented { lossyPaste = nil } }
            ),
            presenting: lossyPaste
        ) { pasted in
            Button("Open Fit") {
                create(pasted)
            }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("Some items of this fitting are not in the database, are cargo or did not fit, and were left out.")
        }
    }

    private var pasteSection: some View {
        Section {
            HUDLoadMoreRow(title: Text("Paste from Clipboard"),
                           detail: pasteFailure?.text,
                           detailColor: .hudWarnNoteInk,
                           systemImage: "doc.on.clipboard",
                           isLoading: isReadingClipboard) {
                isReadingClipboard = true
                pasteFailure = nil
                let feedback = UINotificationFeedbackGenerator()
                feedback.prepare()
                Task {
                    let result = await FitPasteboard.read()
                    isReadingClipboard = false
                    await Self.becomeActive()
                    switch result {
                    case .fit: feedback.notificationOccurred(.success)
                    case .denied, .noFit: feedback.notificationOccurred(.error)
                    }
                    switch result {
                    case .fit(let pasted):
                        if pasted.warnings.isEmpty {
                            create(pasted)
                        } else {
                            lossyPaste = pasted
                        }
                    case .denied:
                        fail(.denied)
                    case .noFit:
                        fail(.noFit)
                    }
                }
            }
            .accessibilityValue(pasteFailure?.message ?? "")
        }
    }

    /// The "Allow Paste" prompt deactivates the app, and haptics are dropped while it is inactive.
    private static func becomeActive() async {
        guard UIApplication.shared.applicationState != .active else { return }
        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                for await _ in NotificationCenter.default.notifications(named: UIApplication.didBecomeActiveNotification) {
                    return
                }
            }
            group.addTask { try? await Task.sleep(for: .seconds(1)) }
            await group.next()
            group.cancelAll()
        }
    }

    private func fail(_ failure: PasteFailure) {
        pasteFailure = failure
        AccessibilityNotification.Announcement(failure.message).post()
    }

    private func create(_ pasted: PastedFit) {
        let name = PickedShip(typeID: pasted.shipTypeID, name: pasted.name).name
        var document = pasted.document
        document.name = name
        open(fittings.create(shipTypeID: pasted.shipTypeID, name: name, document: document))
    }

    @ViewBuilder
    private func row(for fit: FittingSummary, ship: ShipRow?) -> some View {
        HUDSwipeRow(title: "Delete", onRemove: { fittings.delete(fit.id) }, inContextMenu: false, allowsFullSwipe: true) {
            fitLink(fit, ship: ship)
        }
    }

    private func fitLink(_ fit: FittingSummary, ship: ShipRow?) -> some View {
        NavigationLink(value: FittingRoute.editor(fit.id)) {
            FittingRow(fit: fit,
                       ship: ship,
                       knownGameFittingIDs: knownGameFittingIDs(for: fit),
                       isUploading: uploader.isUploading(fit.id))
        }
        .contextMenu {
            Button("Rename") {
                renameText = fit.name
                renamingFit = fit
            }
            Button("Duplicate") {
                fittings.duplicate(fit.id)
            }
            if accounts.currentAccount != nil {
                Button(fit.esiFittingID == nil ? "Upload to EVE" : "Upload Again") {
                    uploader.upload(fit.id, fittings: fittings, accounts: accounts) {
                        fittings.document(of: fit.id)
                    }
                }
                .disabled(uploader.isUploading(fit.id))
            }
            Divider()
            Button("Delete", systemImage: "trash", role: .destructive) {
                fittings.delete(fit.id)
            }
        }
        .hudRowButton(FittingRow.rowStyle)
    }

    /// The fitting ids ESI returned for `fit`'s linked character, or `nil` (trust the stored link)
    /// unless that character is signed in and its list is already loaded.
    private func knownGameFittingIDs(for fit: FittingSummary) -> Set<Int64>? {
        guard let esiCharacterID = fit.esiCharacterID,
              esiCharacterID == accounts.currentAccount?.id,
              let fittings = accounts.currentFittings?.snapshot.value else { return nil }
        return Set(fittings.map(\.id))
    }

    private func filteredFits(_ shipByID: [TypeID: ShipRow]) -> [FittingSummary] {
        guard !searchText.isEmpty else { return fits }
        return fits.filter { fit in
            fit.name.localizedCaseInsensitiveContains(searchText)
                || (shipByID[fit.shipTypeID]?.name.localizedCaseInsensitiveContains(searchText) ?? false)
        }
    }

    /// One heading of the "By Ship" order: fits whose ships share an inventory group.
    private struct ShipSection: Identifiable {
        /// `nil` for the trailing section of fits whose ship is missing from the SDE.
        var id: GroupID?
        var title: String
        var ordinal: UInt32
        var fits: [FittingSummary]
    }

    /// Sections by `groupOrdinal`, fits by name; fits without a ship trail the real groups.
    private func sections(of fits: [FittingSummary], _ shipByID: [TypeID: ShipRow]) -> [ShipSection] {
        var byGroup: [GroupID: ShipSection] = [:]
        var orphaned: [FittingSummary] = []
        for fit in fits {
            if let ship = shipByID[fit.shipTypeID] {
                byGroup[ship.groupID, default: ShipSection(id: ship.groupID,
                                                            title: ship.groupName,
                                                            ordinal: ship.groupOrdinal,
                                                            fits: [])]
                    .fits.append(fit)
            } else {
                orphaned.append(fit)
            }
        }
        var result = byGroup.values.sorted { $0.ordinal < $1.ordinal }
        for index in result.indices {
            result[index].fits.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        }
        if !orphaned.isEmpty {
            orphaned.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            result.append(ShipSection(id: nil, title: String(localized: "Other"), ordinal: .max, fits: orphaned))
        }
        return result
    }
}
