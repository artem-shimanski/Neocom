import DogmaPlanetary
import Foundation

// ESI → `DogmaPlanetary`: a field-by-field copy; the snapshot is interpreted by
// `Colony.init(snapshot:catalog:)`.

nonisolated extension PlanetKind {
    init(esi: String) {
        self = PlanetKind(rawValue: esi) ?? .unknown
    }
}

nonisolated extension ColonySnapshot {
    /// - Parameter planetRadius: metres. Neither ESI nor the SDE carries it; `nil` leaves link
    ///   lengths unknown.
    init(_ colony: ESIColony, planetRadius: Double? = nil) {
        self.init(
            snapshotTime: colony.lastUpdate,
            planetTypeID: PlanetKind(esi: colony.planetType).typeID,
            upgradeLevel: colony.upgradeLevel,
            planetRadius: planetRadius,
            pins: colony.pins.map { pin in
                Pin(pinID: pin.pinID,
                    typeID: TypeID(rawValue: UInt32(clamping: pin.typeID)),
                    latitude: pin.latitude,
                    longitude: pin.longitude,
                    schematicID: pin.schematicID.map { SchematicID(rawValue: UInt16(clamping: $0)) },
                    installTime: pin.installTime,
                    expiryTime: pin.expiryTime,
                    lastCycleStart: pin.lastCycleStart,
                    contents: pin.contents.map {
                        Inventory.Item(typeID: TypeID(rawValue: UInt32(clamping: $0.typeID)), quantity: Int($0.amount))
                    },
                    extractor: pin.extractor.map {
                        Extractor(productTypeID: $0.productTypeID.map { TypeID(rawValue: UInt32(clamping: $0)) },
                                  cycleTime: $0.cycleTime.map(Int.init),
                                  quantityPerCycle: $0.quantityPerCycle.map(Int.init),
                                  headCount: $0.headCount)
                    })
            },
            routes: colony.routes.map {
                Route(routeID: $0.routeID,
                      sourcePinID: $0.sourcePinID,
                      destinationPinID: $0.destinationPinID,
                      typeID: TypeID(rawValue: UInt32(clamping: $0.typeID)),
                      quantity: $0.quantity,
                      waypoints: $0.waypoints)
            },
            links: colony.links.map {
                Link(sourcePinID: $0.sourcePinID, destinationPinID: $0.destinationPinID, level: $0.level)
            }
        )
    }
}
