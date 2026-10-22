import LiteRow
import LiteRowUI
import SDEKit
import SwiftUI

/// The ship the character is flying and the place they are in.
/// The station or structure is named by ESI when the profile is fetched, since the export has no
/// station rows; the solar system around it is named here from the SDE, in the player's language.
struct CharacterLocationSection: View {
    let shipTypeID: TypeID?
    let shipName: String?
    let location: CharacterProfile.Location?

    @LiteQuery private var shipNames: [TypeNameRow]
    @LiteQuery private var systems: [SolarSystemRow]

    init(shipTypeID: TypeID?, shipName: String?, location: CharacterProfile.Location?) {
        self.shipTypeID = shipTypeID
        self.shipName = shipName
        self.location = location
        _shipNames = LiteQuery(SDEBrowser.typeNames(of: shipTypeID.map { [$0] } ?? []))
        _systems = LiteQuery(CharacterBrowser.solarSystems(location?.solarSystemID.map { [$0] } ?? []))
    }

    var body: some View {
        // No ship and no location is what a character without the location scopes looks like; an
        // empty "Location" would read as lost data.
        if shipTypeID != nil || location != nil {
            HUDListSection("Location") {
                if let shipTypeID {
                    NavigationLink(value: DatabaseRoute.type(shipTypeID)) {
                        shipRow(shipTypeID)
                    }
                    .hudRowButton(HUDRowStyle(minHeight: 72, verticalPadding: 12))
                }

                if let location {
                    locationBlock(location)
                }
            }
        }
    }

    private func shipRow(_ shipTypeID: TypeID) -> some View {
        let typeName = shipNames.first { $0.id == shipTypeID }?.name

        return HStack(spacing: 12) {
            HUDItemIcon(typeID: shipTypeID, size: 48)
            // The ship's given name, with its type underneath.
            HUDRowTitle(title: Text(shipName ?? typeName ?? ""),
                        subtitle: typeName.flatMap { $0 == shipName ? nil : Text($0) },
                        font: .hudTileTitle)
            Spacer(minLength: 0)
            HUDChevron()
        }
        .hudRow(HUDRowStyle(minHeight: 72, verticalPadding: 12))
    }

    private func locationBlock(_ location: CharacterProfile.Location) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            // A name means a station or a structure, i.e. docked; no name means somewhere in the
            // system.
            if location.name == nil {
                HUDStatusChip(text: Text("In Space"), color: .hudAccent, mark: .dot)
            } else {
                HUDStatusChip(text: Text("Docked"), color: .hudOk, mark: .dot)
            }
            LocationLabel(location: location,
                          system: location.solarSystemID.flatMap { id in systems.first { $0.id == id } })
        }
        .hudRow(HUDRowStyle(verticalPadding: 12))
    }
}

/// A place: what it is called, and the system it sits in with its security and region underneath.
///
/// Internal: the clones below show places the same way.
struct LocationLabel: View {
    let location: CharacterProfile.Location
    /// `nil` when the system is unknown or not in the export; the place keeps its name without the
    /// line under it.
    let system: SolarSystemRow?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let name = location.name {
                Text(name)
                    .font(.hudBody)
                    .lineSpacing(2)
            }
            if let system {
                let security = Text(SecurityStatus.string(system.securityStatus))
                    .foregroundStyle(SecurityStatus.color(system.securityStatus))
                Text("\(Text(system.name + " "))\(security)\(Text(" · " + system.regionName))")
                    .font(.hudCaption)
                    .textCase(.uppercase)
                    .foregroundStyle(Color.hudInkMuted)
            }
        }
    }
}
