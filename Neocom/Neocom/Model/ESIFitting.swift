import ESIKit
import Foundation

/// An in-game fitting as stored in `ESICache`. A separate type from the generated one, so the
/// disk format does not change when the client is regenerated.
nonisolated struct ESIFitting: Codable, Sendable, Identifiable, Hashable {
    struct Item: Codable, Sendable, Hashable {
        var typeID: Int64
        /// The raw ESI flag (`"HiSlot0"`, `"DroneBay"`, …). A string, so a flag added by CCP
        /// does not break decoding of a cached file.
        var flag: String
        var quantity: Int64
    }

    var id: Int64          // fitting_id
    var name: String
    var fittingDescription: String
    var shipTypeID: Int64
    var items: [Item]

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case fittingDescription = "description"
        case shipTypeID
        case items
    }
}

nonisolated extension ESIFitting {
    init(_ payload: Components.Schemas.CharactersCharacterIdFittingsGetPayload) {
        id = payload.fittingId
        name = payload.name
        fittingDescription = payload.description
        shipTypeID = payload.shipTypeId
        items = payload.items.map { item in
            Item(typeID: item.typeId, flag: item.flag.rawValue, quantity: item.quantity)
        }
    }
}
