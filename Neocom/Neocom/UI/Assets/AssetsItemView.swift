import AssetsKit
import DogmaKit
import LiteRowUI
import SDEKit
import SwiftUI

/// A ship or a container from the asset list: what it is, where it is, and what is in it. A
/// ship's contents are its racks and bays, and it can be copied into a new fit.
struct AssetsItemView: View {
    let model: AssetsModel
    let database: SDEDatabase
    let itemID: Int64

    var body: some View {
        AssetsIndexContent(model: model) { index in
            if let row = index.item(itemID), row.opens {
                AssetsItemList(model: model, database: database, index: index, row: row)
                    .navigationTitle(row.name)
            } else {
                AssetsGoneList()
            }
        }
        .assetsRefresh(model)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct AssetsItemList: View {
    let model: AssetsModel
    let database: SDEDatabase
    let index: AssetIndex
    let row: AssetRow

    @Environment(FittingStore.self) private var fittingStore

    /// Read once in `.task`; opening it reads a file.
    @State private var typeCatalog: TypeCatalog?
    /// The fit just created, pushed into the editor.
    @State private var pushedRoute: FittingRoute?
    /// Warnings of a copy that lost data; the editor opens once the player has read them.
    @State private var copyWarnings: [String]?
    @State private var pendingFitID: UUID?
    @State private var actionError: (any Error)?

    private var isShip: Bool { row.kind == .ship }

    var body: some View {
        let path = index.path(to: row.id)
        HUDList {
            HUDListSection {
                header.hudRow(HUDRowStyle(horizontalPadding: HUDMetrics.gutter, minHeight: 0, verticalPadding: 0))
                if let parent = path?.parents.last {
                    AssetsParentRow(parent: parent)
                }
                if let location = path?.location {
                    AssetsPlaceRow(location: location,
                                   label: placeLabel(path: path, location: location),
                                   isDocked: location.id == model.dockedLocationID)
                }
            }

            if isShip {
                Section {
                    Button(action: openInFittingTool) {
                        Label("Open in Fitting Tool", systemImage: "wrench.and.screwdriver")
                            .frame(maxWidth: .infinity)
                    }
                    .hudProminentButton()
                    .hudBareRow()
                }
            }

            AssetsSections(sections: index.contents(of: row.id), isShip: isShip)

            Section {
                HUDFootnote(isShip
                            ? "Open in Fitting Tool opens a copy of this ship. It is added to My Fits once you change or save it. The ship in the hangar does not change."
                            : "The container's name is the one given to it in game. Stacks of the same item are added together.")
                    .hudBareRow()
            }
        }
        .task {
            if isShip, typeCatalog == nil { typeCatalog = try? TypeCatalog() }
        }
        .navigationDestination(item: $pushedRoute) { route in
            route.destination
                .liteDatabase(database.database)
        }
        .alert(
            "Not Everything Was Copied",
            isPresented: Binding(
                get: { copyWarnings != nil },
                set: { isPresented in if !isPresented { copyWarnings = nil } }
            ),
            presenting: copyWarnings
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
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 14) {
            if isShip {
                HUDImagePlate(url: EVEImage.render(typeID: row.typeID),
                              size: 72,
                              fallbackURL: EVEImage.icon(typeID: row.typeID, size: 128))
            } else {
                HUDItemIcon(typeID: row.typeIDValue, size: 56)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(verbatim: isShip ? row.typeName : row.name)
                    .font(HUDFont.display(isShip ? 24 : 22, weight: .bold, relativeTo: .title2))
                    .tracking(0.5)
                    .textCase(.uppercase)
                    .foregroundStyle(Color.hudInk)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                Text(verbatim: headerSubtitle)
                    .font(HUDFont.mono(11, weight: .regular, relativeTo: .caption))
                    .tracking(1)
                    .textCase(.uppercase)
                    .foregroundStyle(Color.hudInkMuted)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.top, 16)
        .padding(.bottom, 14)
    }

    /// The ship's hull is the title, so its line is the class: `CRUISER · ASSEMBLED`. A
    /// container's line is the row's own.
    private var headerSubtitle: String {
        guard isShip else { return row.subtitle }
        let group = row.groupName.isEmpty ? row.categoryName : row.groupName
        return "\(group) · \(String(localized: "Assembled"))"
    }

    /// `IN HANGAR AT` for what lies in a station hangar, either itself or inside the ship or
    /// container that does; `IN SPACE AT` for a ship out in a system; `AT` for anything filed
    /// elsewhere — Deliveries, Asset Safety.
    private func placeLabel(path: AssetPath?, location: AssetLocation) -> Text {
        if location.kind == .solarSystem { return Text("In space at") }
        let outermost = path?.parents.first ?? row
        return ["Hangar", "HangarAll"].contains(outermost.flag) ? Text("In hangar at") : Text("At")
    }

    // MARK: Fitting Tool

    /// Copies the ship as fitted into a draft and opens it in the editor. The draft is stored on the
    /// first change or "Save" and dropped when the editor closes without either.
    private func openInFittingTool() {
        guard let fitting = index.fitting(ofShip: row.id) else { return }
        if typeCatalog == nil { typeCatalog = try? TypeCatalog() }
        guard let typeCatalog else {
            actionError = CopyFittingError.catalogUnavailable
            return
        }
        var warnings: [String] = []
        let document = FitDocument(ESIFitting(fitting), catalog: typeCatalog, warnings: &warnings)
        let newID = fittingStore.createDraft(shipTypeID: TypeID(rawValue: UInt32(clamping: fitting.shipTypeID)),
                                             name: fitting.name,
                                             document: document)
        if warnings.isEmpty {
            pushedRoute = .editor(newID)
        } else {
            pendingFitID = newID
            copyWarnings = warnings
        }
    }
}

/// The ship or container an item is in, leading to it.
private struct AssetsParentRow: View {
    let parent: AssetRow

    var body: some View {
        NavigationLink(value: AssetsRoute.item(parent.id)) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Inside")
                        .font(.hudMicro)
                        .tracking(2)
                        .textCase(.uppercase)
                        .foregroundStyle(Color.hudInkMuted)
                    Text(verbatim: parent.name)
                        .font(.hudBody)
                        .foregroundStyle(Color.hudInk)
                        .multilineTextAlignment(.leading)
                    Text(verbatim: parent.subtitle)
                        .font(.hudCaption)
                        .textCase(.uppercase)
                        .foregroundStyle(Color.hudInkMuted)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                HUDChevron()
            }
            .hudRow(AssetsPlaceRow.rowStyle)
        }
        .hudRowButton(AssetsPlaceRow.rowStyle)
    }
}
