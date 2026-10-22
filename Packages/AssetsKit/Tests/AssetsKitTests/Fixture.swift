import AssetsKit
import Foundation

/// Page 1 of a real `/characters/{id}/assets` answer (1000 records) and the SDE rows of every
/// type in it, plus a few placed by hand.
///
/// Some parents lie on other pages: the Thorax `1144` and the container `1083`
/// appear as roots. `withParents()` adds their records back in the Rens station hangar.
enum Fixture {
    static let rens: Int64 = 60004588
    static let structure: Int64 = 2014
    static let thorax: Int64 = 1144
    static let container: Int64 = 1083
    static let rensSystem: Int64 = 30002526

    private struct ESIRecord: Decodable {
        var item_id: Int64
        var type_id: Int64
        var location_id: Int64
        var location_flag: String
        var location_type: String
        var quantity: Int64
        var is_singleton: Bool
        var is_blueprint_copy: Bool?
    }

    static func records() throws -> [AssetRecord] {
        let data = try Data(contentsOf: resource("assets-page1"))
        return try JSONDecoder().decode([ESIRecord].self, from: data).map {
            AssetRecord(itemID: $0.item_id, typeID: $0.type_id, locationID: $0.location_id,
                        locationFlag: $0.location_flag, locationType: $0.location_type,
                        quantity: $0.quantity, isSingleton: $0.is_singleton,
                        isBlueprintCopy: $0.is_blueprint_copy ?? false)
        }
    }

    static func withParents() throws -> [AssetRecord] {
        try records() + [
            AssetRecord(itemID: thorax, typeID: 627, locationID: rens, locationFlag: "Hangar",
                        locationType: "station", quantity: 1, isSingleton: true),
            AssetRecord(itemID: container, typeID: 17366, locationID: rens, locationFlag: "Hangar",
                        locationType: "station", quantity: 1, isSingleton: true),
        ]
    }

    static func types() throws -> [Int64: AssetTypeInfo] {
        let data = try Data(contentsOf: resource("types"))
        let rows = try JSONDecoder().decode([AssetTypeInfo].self, from: data)
        return Dictionary(uniqueKeysWithValues: rows.map { ($0.typeID, $0) })
    }

    static let locations: [Int64: AssetLocationInfo] = [
        rens: AssetLocationInfo(id: rens, kind: .station, name: "Rens VI - Moon 8 - Brutor Tribe Treasury",
                                solarSystemID: rensSystem),
        structure: AssetLocationInfo(id: structure, kind: .structureNoAccess),
    ]

    static let systems: [Int64: AssetSolarSystem] = [
        rensSystem: AssetSolarSystem(name: "Rens", securityStatus: 0.9, regionName: "Heimatar"),
    ]

    static func index(records: [AssetRecord]? = nil, names: [Int64: String] = [:]) throws -> AssetIndex {
        AssetIndex(records: try records ?? withParents(),
                   customNames: names,
                   locations: locations,
                   systems: systems,
                   types: try types())
    }

    private static func resource(_ name: String) throws -> URL {
        guard let url = Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Resources") else {
            throw CocoaError(.fileNoSuchFile)
        }
        return url
    }
}
