import AssetsKit
import SDEKit
import SwiftUI

/// One root location: what lies in its hangar and anything else EVE files under it, by section.
/// A structure without access (or a place nobody could name) gets its own header that says why
/// it has no name.
struct AssetsLocationView: View {
    let model: AssetsModel
    let locationID: Int64

    var body: some View {
        AssetsIndexContent(model: model) { index in
            if let location = index.location(locationID) {
                AssetsLocationList(model: model, index: index, location: location)
                    .navigationTitle(location.isUnknown ? location.displayName : location.shortName)
            } else {
                AssetsGoneList()
            }
        }
        .assetsRefresh(model)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct AssetsLocationList: View {
    let model: AssetsModel
    let index: AssetIndex
    let location: AssetLocation

    var body: some View {
        let sections = index.contents(of: location.id)
        HUDList {
            Section {
                Group {
                    if location.isUnknown {
                        AssetsUnknownHeader(location: location, sections: sections)
                    } else {
                        AssetsLocationHeader(location: location,
                                             isHome: location.id == model.homeLocationID,
                                             isDocked: location.id == model.dockedLocationID)
                    }
                }
                .hudBareRow()
            }

            let divisions = index.divisions(at: location.id)
            if !divisions.isEmpty {
                HUDListSection(divisions, row: { division in
                    NavigationLink(value: AssetsRoute.division(locationID: location.id, number: division.number)) {
                        AssetsDivisionRow(name: model.divisionName(division.number), division: division)
                    }
                    .hudRowButton(AssetsDivisionRow.rowStyle)
                }, header: {
                    HUDSectionHeader(Text("Hangar Divisions"))
                })
            }

            AssetsSections(sections: sections)

            Section {
                HUDFootnote(location.isUnknown
                            ? "Identical blueprint copies are counted as one row. Runs and research levels are not part of the asset list."
                            : "Stacks of the same item are added together. Tap a ship or a container to see what is inside; tap an item for its info.")
                    .hudBareRow()
            }
        }
    }
}

/// One hangar division of a corporation: its name and what lies in it.
private struct AssetsDivisionRow: View {
    static let rowStyle = HUDRowStyle(horizontalPadding: 0, minHeight: 56, verticalPadding: 10)

    let name: String
    let division: AssetDivision

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: name)
                    .font(.hudBody)
                    .foregroundStyle(Color.hudInk)
                    .multilineTextAlignment(.leading)
                Text(verbatim: AssetsFormat.items(division.itemCount))
                    .font(HUDFont.mono(11, weight: .regular, relativeTo: .caption))
                    .foregroundStyle(Color.hudInkMuted)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .trailing, spacing: 5) {
                if division.shipCount > 0 {
                    HUDMetaBadge(text: Text(verbatim: AssetsFormat.ships(division.shipCount)))
                }
                if division.containerCount > 0 {
                    HUDMetaBadge(text: Text(verbatim: String(localized: "\(division.containerCount) containers")))
                }
            }
            .fixedSize()
            HUDChevron()
        }
        .padding(.leading, HUDMetrics.gutter)
        .padding(.trailing, 14)
        .hudRow(Self.rowStyle)
    }
}

/// The location's card: name, system and region, home and docked, and the counts.
private struct AssetsLocationHeader: View {
    let location: AssetLocation
    let isHome: Bool
    let isDocked: Bool

    var body: some View {
        HUDPanel {
            HStack(alignment: .center, spacing: 12) {
                HUDSymbolPlate(systemImage: location.systemImage, size: 48)
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: location.displayName)
                        .font(HUDFont.display(16, weight: .semibold, relativeTo: .headline))
                        .foregroundStyle(Color.hudInk)
                    if let line = location.systemRegionText {
                        line
                            .font(.hudCaption)
                            .foregroundStyle(Color.hudInkMuted)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .trailing, spacing: 5) {
                    if isDocked {
                        HUDStatusChip(text: Text("Docked"), color: .hudOk, mark: .dot)
                    }
                    if isHome {
                        Text("Home")
                            .font(.hudMicro)
                            .tracking(1)
                            .textCase(.uppercase)
                            .foregroundStyle(Color.hudInkMuted)
                    }
                }
                .fixedSize()
                .frame(maxHeight: .infinity, alignment: .top)
                .padding(.top, 3)
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, HUDMetrics.gutter)
            .padding(.vertical, 14)
            HUDPanelRule()
            HUDStatStrip(items: [
                .init(id: 0, label: Text("Items"), value: Text(verbatim: AssetsFormat.count(location.itemCount))),
                .init(id: 1, label: Text("Ships"), value: Text(verbatim: AssetsFormat.quantity(location.shipCount))),
                .init(id: 2, label: Text("Containers"), value: Text(verbatim: AssetsFormat.count(location.containerCount))),
            ])
        }
    }
}

/// A structure EVE will not name, or a place nobody could: what is known, and why the rest
/// is not.
private struct AssetsUnknownHeader: View {
    let location: AssetLocation
    let sections: [AssetSection]

    var body: some View {
        HUDPanel {
            HStack(spacing: 14) {
                HUDSymbolPlate(systemImage: "questionmark", size: 56)
                VStack(alignment: .leading, spacing: 6) {
                    Text(verbatim: location.displayName)
                        .font(HUDFont.display(22, weight: .bold, relativeTo: .title2))
                        .tracking(0.5)
                        .textCase(.uppercase)
                        .foregroundStyle(Color.hudInk)
                    Text(verbatim: idLine)
                        .font(HUDFont.mono(11, weight: .regular, relativeTo: .caption))
                        .tracking(1)
                        .textCase(.uppercase)
                        .foregroundStyle(Color.hudInkMuted)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, HUDMetrics.gutter)
            .padding(.top, 16)
            .padding(.bottom, 14)
            HUDPanelRule()
            Text(explanation)
                .font(HUDFont.mono(11, weight: .regular, relativeTo: .caption))
                .lineSpacing(3)
                .foregroundStyle(Color.hudInkBodyMuted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, HUDMetrics.gutter)
                .padding(.top, 10)
                .padding(.bottom, 12)
            HUDPanelRule()
            HUDStatStrip(items: [
                .init(id: 0, label: Text("Items"), value: Text(verbatim: AssetsFormat.count(location.itemCount))),
                .init(id: 1, label: Text("Types"), value: Text(verbatim: AssetsFormat.count(typeCount))),
                .init(id: 2, label: Text("BPC"), value: Text(verbatim: AssetsFormat.quantity(blueprintCopies))),
            ])
        }
    }

    private var idLine: String {
        let state = location.kind == .structureNoAccess ? String(localized: "No access") : String(localized: "Unknown")
        return "ID \(location.id) · \(state)"
    }

    private var explanation: LocalizedStringKey {
        location.kind == .structureNoAccess
            ? "Your items are in a player-owned structure that does not give you docking access, so EVE does not tell Neocom its name or system. Its contents are shown as EVE reports them. Once you can dock there again, its name appears here."
            : "EVE lists items at this place but does not say what it is. Its contents are shown as EVE reports them."
    }

    private var typeCount: Int {
        Set(sections.flatMap(\.rows).map(\.typeID)).count
    }

    private var blueprintCopies: Int64 {
        sections.flatMap(\.rows).filter(\.isBlueprintCopy).reduce(0) { $0 + $1.quantity }
    }
}

// MARK: - Shared by the location, container and ship screens

/// The sections of a location, container or ship, each a card under its header. A ship's racks
/// show slots or m³; an empty rack stays, with a line saying so.
struct AssetsSections: View {
    let sections: [AssetSection]
    /// Whether these are a ship's racks, where a loaded charge is said to be loaded.
    var isShip = false

    var body: some View {
        ForEach(sections) { section in
            if section.rows.isEmpty {
                HUDListSection {
                    Text("Empty")
                        .font(.hudCaption)
                        .textCase(.uppercase)
                        .foregroundStyle(Color.hudInkFaint)
                        .hudRow(HUDRowStyle(minHeight: 44))
                } header: {
                    header(section)
                }
            } else {
                HUDListSection(section.rows, row: { row in
                    AssetsRowLink(row: row, isLoadedCharge: isShip && row.isCharge && isRack(section.kind))
                }, header: {
                    header(section)
                })
            }
        }
    }

    private func header(_ section: AssetSection) -> HUDSectionHeader<Text> {
        let trailing = section.capacity.map { AssetsFormat.capacity($0) } ?? AssetsFormat.count(section.rows.count)
        return HUDSectionHeader(Text(verbatim: section.localizedTitle)) {
            Text(verbatim: trailing)
        }
    }

    private func isRack(_ kind: AssetSection.Kind) -> Bool {
        switch kind {
        case .highSlots, .mediumSlots, .lowSlots: true
        default: false
        }
    }
}

/// One row of a section: a ship or container opens its own screen, anything else the item's
/// info.
struct AssetsRowLink: View {
    let row: AssetRow
    var subtitle: String?
    var isLoadedCharge = false

    var body: some View {
        if row.opens {
            NavigationLink(value: AssetsRoute.item(row.id)) {
                label(showsChevron: true)
            }
            .hudRowButton(HUDTypeRow.rowStyle)
            .hudTypeContextMenu(typeID: row.typeIDValue, name: row.name)
        } else {
            NavigationLink(value: DatabaseRoute.type(row.typeIDValue)) {
                label(showsChevron: false)
            }
            .hudRowButton(HUDTypeRow.rowStyle)
            .hudTypeContextMenu(typeID: row.typeIDValue, name: row.name)
        }
    }

    private func label(showsChevron: Bool) -> some View {
        var line = subtitle ?? row.subtitle
        if isLoadedCharge { line += " · " + String(localized: "Loaded") }
        return HUDTypeRow(typeID: row.typeIDValue,
                          name: row.name,
                          subtitle: Text(verbatim: line),
                          quantity: row.quantityText,
                          showsChevron: showsChevron,
                          iconSize: 36,
                          lineLimit: 1)
    }
}

/// A row that leads back to a root location: its name, its system, and docked when it is
/// where the character is. `label` stands above the name — `IN HANGAR AT` on a ship's screen —
/// or is left out, as on the search results.
struct AssetsPlaceRow: View {
    let location: AssetLocation
    var label: Text?
    var isDocked = false

    var body: some View {
        NavigationLink(value: AssetsRoute.location(location.id)) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    if let label {
                        label
                            .font(.hudMicro)
                            .tracking(2)
                            .textCase(.uppercase)
                            .foregroundStyle(Color.hudInkMuted)
                    }
                    Text(verbatim: location.displayName)
                        .font(.hudBody)
                        .foregroundStyle(Color.hudInk)
                        .multilineTextAlignment(.leading)
                    if let line = location.systemRegionText {
                        line
                            .font(.hudCaption)
                            .foregroundStyle(Color.hudInkMuted)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if isDocked {
                    HUDStatusChip(text: Text("Docked"), color: .hudOk, mark: .dot)
                        .fixedSize()
                }
                HUDChevron()
            }
            .hudRow(Self.rowStyle)
        }
        .hudRowButton(Self.rowStyle)
    }

    static let rowStyle = HUDRowStyle(minHeight: 56, verticalPadding: 12)
}

/// Shown when the item a pushed screen was opened on is no longer in the list.
struct AssetsGoneList: View {
    var body: some View {
        HUDList {
            Section {
                HUDEmptyPanel(title: Text("Not in Assets"),
                              message: Text("This is no longer in the asset list. It may have been moved, repackaged or sold since the last update."))
                    .hudBareRow()
            }
        }
    }
}
