import DogmaPlanetary
import Foundation
import LiteRow
import SDEKit

// Where the report gets its names: the SDE for types and solar systems (planets themselves
// are not in it — their names come with the colony from ESI), and the bundled
// `planetary.bin` for the simulation.

extension PlanetaryReport {
    /// Simulates every colony from its last update to `now` and on to its horizon.
    ///
    /// Names are read first, in one database round trip; without a database (`nil`, or a
    /// failed read) the report is the same, only with placeholder names. The simulation runs
    /// off the main actor: a five-day program is a few thousand events per colony — cheap, but
    /// not something for a view's body.
    static func make(colonies: [ESIColony], database: SDEDatabase?, now: Date = .now) async throws -> PlanetaryReport {
        let catalog = try PlanetaryCatalog.shared()
        var names = PlanetaryNames()
        if let database {
            names = (try? await PlanetaryNames(loading: database, colonies: colonies, catalog: catalog)) ?? names
        }
        return await simulate(colonies: colonies, catalog: catalog, names: names, now: now)
    }

    @concurrent
    private static func simulate(colonies: [ESIColony], catalog: PlanetaryCatalog,
                                       names: PlanetaryNames, now: Date) async -> PlanetaryReport {
        PlanetaryAnalysis.report(colonies: colonies, catalog: catalog, names: names, now: now)
    }
}

nonisolated extension PlanetaryCatalog {
    private static let cache = Result { try PlanetaryCatalog.bundled() }

    /// `planetary.bin`, read once per process: ~10 KB, materialized whole on load.
    static func shared() throws -> PlanetaryCatalog {
        try cache.get()
    }
}

// Main-actor isolated because the query builders are; the read runs on the database's own
// connection.
extension PlanetaryNames {
    /// Every commodity any schematic makes or takes (all of P0…P4), every pin type of the
    /// colonies, and their solar systems.
    init(loading database: SDEDatabase, colonies: [ESIColony], catalog: PlanetaryCatalog) async throws {
        var typeIDs = Set<TypeID>()
        for id in catalog.schematicIDs {
            guard let schematic = catalog.schematic(id) else { continue }
            typeIDs.insert(schematic.output.typeID)
            typeIDs.formUnion(schematic.inputs.map(\.typeID))
        }
        for colony in colonies {
            for pin in colony.pins {
                typeIDs.insert(TypeID(rawValue: UInt32(clamping: pin.typeID)))
                if let product = pin.extractor?.productTypeID { typeIDs.insert(TypeID(rawValue: UInt32(clamping: product))) }
                typeIDs.formUnion(pin.contents.map { TypeID(rawValue: UInt32(clamping: $0.typeID)) })
            }
        }
        let typeQuery = SDEBrowser.typeNames(of: Array(typeIDs))
        let systemQuery = CharacterBrowser.solarSystems(
            Array(Set(colonies.map { SolarSystemID(rawValue: UInt32(clamping: $0.solarSystemID)) })))

        let (types, systems) = try await database.database.read { reader in
            var types: [TypeID: String] = [:]
            for row in try reader.fetchAll(typeQuery) { types[row.id] = row.name }
            var systems: [Int64: System] = [:]
            for row in try reader.fetchAll(systemQuery) {
                systems[Int64(row.id.rawValue)] = System(name: row.name, securityStatus: row.securityStatus,
                                                         regionName: row.regionName)
            }
            return (types, systems)
        }
        self.init(types: types, systems: systems)
    }
}
