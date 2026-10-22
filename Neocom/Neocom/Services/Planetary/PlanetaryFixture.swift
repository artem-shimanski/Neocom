#if DEBUG
import DogmaPlanetary
import Foundation

/// A real colony, for previews: the answers of `GET /characters/{id}/planets` and
/// `/characters/{id}/planets/{planet_id}`, recorded on 2026-10-15: a Barren planet, Biocells from
/// three extractors. The planet name is not part of either answer and is set separately.
nonisolated enum PlanetaryFixture {
    static let planetsJSON = #"""
[{"last_update":"2026-10-15T08:20:47Z","num_pins":9,"owner_id":0,"planet_id":40159291,"planet_type":"barren","solar_system_id":30002506,"upgrade_level":4}]
"""#

    static let colonyJSON = #"""
{"links":[{"destination_pin_id":1,"link_level":0,"source_pin_id":2},{"destination_pin_id":3,"link_level":0,"source_pin_id":2},{"destination_pin_id":4,"link_level":0,"source_pin_id":5},{"destination_pin_id":6,"link_level":0,"source_pin_id":2},{"destination_pin_id":7,"link_level":0,"source_pin_id":2},{"destination_pin_id":8,"link_level":0,"source_pin_id":2},{"destination_pin_id":9,"link_level":0,"source_pin_id":2},{"destination_pin_id":5,"link_level":0,"source_pin_id":2}],"pins":[{"contents":[{"amount":40,"type_id":2396},{"amount":20,"type_id":2399}],"last_cycle_start":"2020-04-04T13:53:34Z","latitude":1.5032544136047363,"longitude":3.3328778743743896,"pin_id":8,"schematic_id":79,"type_id":2474},{"contents":[{"amount":870,"type_id":2329}],"latitude":1.4498237371444702,"longitude":3.367450714111328,"pin_id":9,"type_id":2544},{"contents":[],"expiry_time":"2026-10-20T08:20:46Z","extractor_details":{"cycle_time":7200,"head_radius":0.02442057803273201,"heads":[{"head_id":0,"latitude":1.1461316347122192,"longitude":3.228414297103882},{"head_id":5,"latitude":1.1780385971069336,"longitude":3.1866812705993652}],"product_type_id":2270,"qty_per_cycle":689},"install_time":"2026-10-15T08:20:46Z","last_cycle_start":"2026-10-15T08:20:46Z","latitude":1.1654142141342163,"longitude":3.2065632343292236,"pin_id":4,"type_id":2848},{"contents":[],"latitude":1.5000149011611938,"longitude":3.3656702041625977,"pin_id":2,"type_id":2524},{"contents":[{"amount":209063,"type_id":2267},{"amount":1480,"type_id":2396}],"latitude":1.4830513000488281,"longitude":3.3515877723693848,"pin_id":5,"type_id":2541},{"contents":[],"expiry_time":"2026-10-20T08:20:46Z","extractor_details":{"cycle_time":7200,"head_radius":0.024401959031820297,"heads":[{"head_id":0,"latitude":1.6261909008026123,"longitude":3.2499911785125732},{"head_id":5,"latitude":1.596855878829956,"longitude":3.2902746200561523}],"product_type_id":2288,"qty_per_cycle":1430},"install_time":"2026-10-15T08:20:46Z","last_cycle_start":"2026-10-15T08:20:46Z","latitude":1.6215156316757202,"longitude":3.253805160522461,"pin_id":6,"type_id":2848},{"contents":[{"amount":1465,"type_id":2288}],"last_cycle_start":"2020-04-04T13:23:34Z","latitude":1.5084550380706787,"longitude":3.401848554611206,"pin_id":1,"schematic_id":134,"type_id":2473},{"contents":[],"expiry_time":"2026-10-20T08:20:46Z","extractor_details":{"cycle_time":7200,"head_radius":0.024238821119070053,"heads":[{"head_id":0,"latitude":1.384714961051941,"longitude":3.4746904373168945},{"head_id":1,"latitude":1.4178682565689087,"longitude":3.43711519241333},{"head_id":2,"latitude":1.4337655305862427,"longitude":3.484583854675293},{"head_id":5,"latitude":1.3696039915084839,"longitude":3.4260668754577637},{"head_id":6,"latitude":1.3358781337738037,"longitude":3.464784622192383}],"product_type_id":2270,"qty_per_cycle":1642},"install_time":"2026-10-15T08:20:46Z","last_cycle_start":"2026-10-15T08:20:46Z","latitude":1.3720144033432007,"longitude":3.446371078491211,"pin_id":3,"type_id":2848},{"contents":[{"amount":944,"type_id":2270}],"last_cycle_start":"2020-04-04T13:23:34Z","latitude":1.5296248197555542,"longitude":3.3748626708984375,"pin_id":7,"schematic_id":127,"type_id":2473}],"routes":[{"content_type_id":2399,"destination_pin_id":5,"quantity":20.0,"route_id":101,"source_pin_id":7,"waypoints":[2]},{"content_type_id":2288,"destination_pin_id":1,"quantity":3000.0,"route_id":102,"source_pin_id":5,"waypoints":[2]},{"content_type_id":2396,"destination_pin_id":5,"quantity":20.0,"route_id":103,"source_pin_id":1,"waypoints":[2]},{"content_type_id":2270,"destination_pin_id":7,"quantity":3000.0,"route_id":104,"source_pin_id":5,"waypoints":[2]},{"content_type_id":2329,"destination_pin_id":9,"quantity":5.0,"route_id":105,"source_pin_id":8,"waypoints":[2]},{"content_type_id":2396,"destination_pin_id":8,"quantity":40.0,"route_id":106,"source_pin_id":5,"waypoints":[2]},{"content_type_id":2399,"destination_pin_id":8,"quantity":40.0,"route_id":107,"source_pin_id":5,"waypoints":[2]},{"content_type_id":2270,"destination_pin_id":5,"quantity":23640.0,"route_id":108,"source_pin_id":3,"waypoints":[2]},{"content_type_id":2288,"destination_pin_id":5,"quantity":20592.0,"route_id":109,"source_pin_id":6,"waypoints":[2]},{"content_type_id":2270,"destination_pin_id":5,"quantity":9920.0,"route_id":110,"source_pin_id":4,"waypoints":[]}]}
"""#

    /// The fixture's `last_update` — simulate from here to see what the game would show.
    static var lastUpdate: Date { colonies[0].lastUpdate }

    static var colonies: [ESIColony] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        // swiftlint:disable:next force_try
        let headers = try! decoder.decode([Header].self, from: Data(planetsJSON.utf8))
        // swiftlint:disable:next force_try
        let layout = try! decoder.decode(Layout.self, from: Data(colonyJSON.utf8))
        return headers.map { header in
            ESIColony(planetID: header.planet_id,
                      planetName: "Osoggur I",
                      planetType: header.planet_type,
                      solarSystemID: header.solar_system_id,
                      upgradeLevel: header.upgrade_level,
                      numberOfPins: header.num_pins,
                      lastUpdate: header.last_update,
                      pins: layout.pins.map { pin in
                          ESIColony.Pin(pinID: pin.pin_id, typeID: pin.type_id,
                                        latitude: pin.latitude, longitude: pin.longitude,
                                        schematicID: pin.schematic_id,
                                        installTime: pin.install_time, expiryTime: pin.expiry_time,
                                        lastCycleStart: pin.last_cycle_start,
                                        contents: (pin.contents ?? []).map { .init(typeID: $0.type_id, amount: $0.amount) },
                                        extractor: pin.extractor_details.map {
                                            .init(productTypeID: $0.product_type_id, cycleTime: $0.cycle_time,
                                                  quantityPerCycle: $0.qty_per_cycle, headCount: $0.heads.count)
                                        })
                      },
                      links: layout.links.map {
                          .init(sourcePinID: $0.source_pin_id, destinationPinID: $0.destination_pin_id, level: $0.link_level)
                      },
                      routes: layout.routes.map {
                          .init(routeID: $0.route_id, sourcePinID: $0.source_pin_id,
                                destinationPinID: $0.destination_pin_id, typeID: $0.content_type_id,
                                quantity: $0.quantity, waypoints: $0.waypoints ?? [])
                      })
        }
    }

    private struct Header: Decodable {
        var last_update: Date
        var num_pins: Int
        var planet_id: Int64
        var planet_type: String
        var solar_system_id: Int64
        var upgrade_level: Int
    }

    private struct Layout: Decodable {
        struct Item: Decodable { var amount: Int64; var type_id: Int64 }
        struct Head: Decodable { var head_id: Int }
        struct Extractor: Decodable {
            var cycle_time: Int64?
            var heads: [Head]
            var product_type_id: Int64?
            var qty_per_cycle: Int64?
        }
        struct Pin: Decodable {
            var pin_id: Int64
            var type_id: Int64
            var latitude: Double
            var longitude: Double
            var schematic_id: Int64?
            var install_time: Date?
            var expiry_time: Date?
            var last_cycle_start: Date?
            var contents: [Item]?
            var extractor_details: Extractor?
        }
        struct Route: Decodable {
            var route_id: Int64
            var source_pin_id: Int64
            var destination_pin_id: Int64
            var content_type_id: Int64
            var quantity: Double
            var waypoints: [Int64]?
        }
        struct Link: Decodable { var source_pin_id: Int64; var destination_pin_id: Int64; var link_level: Int }
        var pins: [Pin]
        var routes: [Route]
        var links: [Link]
    }
}
nonisolated extension PlanetaryFixture {
    /// The SDE names the fixture's types and solar system have, fixed so a preview
    /// reads like the app without opening the database.
    static var names: PlanetaryNames {
        let types: [UInt32: String] = [
            2267: "Base Metals", 2270: "Noble Metals", 2288: "Carbon Compounds",
            2396: "Biofuels", 2399: "Precious Metals", 2329: "Biocells",
            2473: "Barren Basic Industry Facility", 2474: "Barren Advanced Industry Facility",
            2524: "Barren Command Center", 2541: "Barren Storage Facility",
            2544: "Barren Launchpad", 2848: "Barren Extractor Control Unit",
        ]
        return PlanetaryNames(
            types: Dictionary(uniqueKeysWithValues: types.map { (TypeID(rawValue: $0.key), $0.value) }),
            systems: [30002506: .init(name: "Osoggur", securityStatus: 0.531568, regionName: "Heimatar")])
    }
}

nonisolated extension PlanetaryReport {
    /// The fixture colony simulated `elapsed` past its last update, with the SDE names of its
    /// types (`PlanetaryFixture.names`).
    static func fixture(simulatedFor elapsed: TimeInterval = 55 * 3600) -> PlanetaryReport {
        // swiftlint:disable:next force_try
        PlanetaryAnalysis.report(colonies: PlanetaryFixture.colonies,
                                 catalog: try! PlanetaryCatalog.bundled(),
                                 names: PlanetaryFixture.names,
                                 now: PlanetaryFixture.lastUpdate.addingTimeInterval(elapsed))
    }
}
#endif
