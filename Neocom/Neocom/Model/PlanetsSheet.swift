import ESIKit
import Foundation
import Observation

/// The planetary colonies of one character.
///
/// The only owner of `/characters/{id}/planets` and `/characters/{id}/planets/{planet_id}`.
/// Both routes share one snapshot: a layout is valid only at its header's `last_update`.
@Observable
@MainActor
final class PlanetsSheet {
    /// ESI's cache time for the routes.
    private static let ttl: TimeInterval = 600

    let characterID: Int64
    private(set) var snapshot: ESISnapshot<[ESIColony]>

    // `ESICache()` is created in the body: default arguments are not evaluated on the main actor.
    init(characterID: Int64, client: Client) {
        self.characterID = characterID
        snapshot = ESISnapshot(kind: "planets",
                               characterID: characterID,
                               ttl: Self.ttl,
                               cache: ESICache()) {
            try await Self.fetch(characterID: characterID, client: client)
        }
    }

    /// Refreshes the colonies if missing or past the TTL.
    func ensureFresh() async {
        await snapshot.ensureFresh()
    }

    /// Cancels the fetch in flight and stops all disk writes; called by `AccountStore`.
    func invalidate() {
        snapshot.invalidate()
    }

    func refresh() async {
        await snapshot.refresh()
    }

    /// Fetches the header list, then every colony's layout and planet name in parallel.
    ///
    /// A failed layout fails the whole fetch; a failed planet name only leaves it `nil`.
    nonisolated private static func fetch(characterID: Int64, client: Client) async throws -> [ESIColony] {
        let headers = try await client.planets(characterID: characterID)
        return try await withThrowingTaskGroup(of: (Int, ESIColony).self) { group in
            for (offset, header) in headers.enumerated() {
                group.addTask {
                    async let layout = client.colonyLayout(characterID: characterID, planetID: header.planetId)
                    async let name = try? client.planet(id: header.planetId).name
                    return (offset, ESIColony(header: header, layout: try await layout, planetName: await name))
                }
            }
            var colonies: [(Int, ESIColony)] = []
            for try await colony in group {
                colonies.append(colony)
            }
            return colonies.sorted { $0.0 < $1.0 }.map(\.1)
        }
    }
}

nonisolated extension ESIColony {
    init(header: Components.Schemas.CharactersCharacterIdPlanetsGetPayload,
         layout: Components.Schemas.CharactersCharacterIdPlanetsPlanetIdGet,
         planetName: String?) {
        planetID = header.planetId
        self.planetName = planetName
        planetType = header.planetType.rawValue
        solarSystemID = header.solarSystemId
        upgradeLevel = Int(header.upgradeLevel)
        numberOfPins = Int(header.numPins)
        lastUpdate = header.lastUpdate
        pins = layout.pins.map { pin in
            Pin(pinID: pin.pinId,
                typeID: pin.typeId,
                latitude: pin.latitude,
                longitude: pin.longitude,
                // ESI documents both spellings; the factory one is the newer.
                schematicID: pin.factoryDetails?.schematicId ?? pin.schematicId,
                installTime: pin.installTime,
                expiryTime: pin.expiryTime,
                lastCycleStart: pin.lastCycleStart,
                contents: (pin.contents ?? []).map { Item(typeID: $0.typeId, amount: $0.amount) },
                extractor: pin.extractorDetails.map { details in
                    Extractor(productTypeID: details.productTypeId,
                              cycleTime: details.cycleTime,
                              quantityPerCycle: details.qtyPerCycle,
                              headCount: details.heads.count)
                })
        }
        links = layout.links.map {
            Link(sourcePinID: $0.sourcePinId, destinationPinID: $0.destinationPinId, level: Int($0.linkLevel))
        }
        routes = layout.routes.map {
            Route(routeID: $0.routeId,
                  sourcePinID: $0.sourcePinId,
                  destinationPinID: $0.destinationPinId,
                  typeID: $0.contentTypeId,
                  quantity: $0.quantity,
                  waypoints: $0.waypoints ?? [])
        }
    }
}
