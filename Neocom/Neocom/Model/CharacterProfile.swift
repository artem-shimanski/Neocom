import Foundation
import SDEKit

/// The Character Sheet's non-training data: identity, affiliation, wallet, location and clones.
///
/// Stored in `ESICache`. Everything but `name`, `birthday` and `corporationID` is optional:
/// a field whose request failed is `nil`.
nonisolated struct CharacterProfile: Codable, Sendable, Hashable {
    /// A station or player-owned structure.
    ///
    /// The name comes from ESI (station names are not in the SDE); the solar system is named
    /// from the SDE.
    struct Location: Codable, Sendable, Hashable {
        var solarSystemID: SolarSystemID?
        /// `nil` when ESI does not resolve it, e.g. `403` for a structure without docking access.
        var name: String?
        /// Optional for decoding profiles cached without it.
        var locationID: Int64?

        init(solarSystemID: SolarSystemID? = nil, name: String? = nil, locationID: Int64? = nil) {
            self.solarSystemID = solarSystemID
            self.name = name
            self.locationID = locationID
        }
    }

    struct JumpClone: Codable, Sendable, Hashable, Identifiable {
        var id: Int64
        /// The player-assigned name.
        var name: String?
        var location: Location
        var implants: [TypeID]
    }

    var name: String
    var birthday: Date
    var securityStatus: Double?
    var raceID: RaceID?
    var bloodlineID: BloodlineID?
    var factionID: FactionID?

    var corporationID: Int64
    var corporationName: String?
    var corporationTicker: String?
    var allianceID: Int64?
    var allianceName: String?
    var allianceTicker: String?

    var balance: Double?

    /// The current location; `location.name` is `nil` when the character is in space.
    var location: Location?
    var shipTypeID: TypeID?
    /// The player-assigned ship name.
    var shipName: String?

    var homeLocation: Location?
    var lastCloneJumpDate: Date?
    var jumpClones: [JumpClone]
}
