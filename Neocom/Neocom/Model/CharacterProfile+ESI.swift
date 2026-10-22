import ESIKit
import Foundation
import SDEKit

/// Builds a `CharacterProfile` from the ESI routes behind the Character Sheet.
///
/// The only conversion from the generated ESI types into `CharacterProfile`.
nonisolated extension CharacterProfile {
    /// A location to resolve over the network, and the route that resolves it.
    private enum Place {
        case station
        case structure
    }

    /// Fetches the whole profile.
    ///
    /// Only `/characters/{id}` is required; every other request is best effort and its failure
    /// leaves the corresponding field `nil`.
    static func load(characterID: Int64, client: Client) async throws -> CharacterProfile {
        let detail = try await client.character(id: characterID)

        // A local function, since `async let` cannot be conditional.
        func allianceDetail() async -> Components.Schemas.AllianceDetail? {
            guard let allianceID = detail.allianceId else { return nil }
            return try? await client.alliance(id: allianceID)
        }

        async let balance = try? client.characterWallet(id: characterID)
        async let clones = try? client.characterClones(id: characterID)
        async let location = try? client.characterLocation(id: characterID)
        async let ship = try? client.characterShip(id: characterID)
        async let corporation = try? client.corporation(id: detail.corporationId)
        async let alliance = allianceDetail()

        let (walletBalance, cloneList, whereabouts, currentShip, corporationDetail, allianceDetailResult) =
            await (balance, clones, location, ship, corporation, alliance)

        // Deduplicated: the same location can appear in several responses.
        var places: [Int64: Place] = [:]
        if let whereabouts {
            if let stationID = whereabouts.stationId { places[stationID] = .station }
            if let structureID = whereabouts.structureId { places[structureID] = .structure }
        }
        if let home = cloneList?.homeLocation, let locationID = home.locationId {
            places[locationID] = home.locationType == .structure ? .structure : .station
        }
        for clone in cloneList?.jumpClones ?? [] {
            places[clone.locationId] = clone.locationType == .structure ? .structure : .station
        }

        let named = await names(of: places, client: client)

        return CharacterProfile(
            name: detail.name,
            birthday: detail.birthday,
            securityStatus: detail.securityStatus,
            raceID: UInt16(exactly: detail.raceId).map(RaceID.init(rawValue:)),
            bloodlineID: UInt16(exactly: detail.bloodlineId).map(BloodlineID.init(rawValue:)),
            factionID: detail.factionId.flatMap(UInt32.init(exactly:)).map(FactionID.init(rawValue:)),
            corporationID: detail.corporationId,
            corporationName: corporationDetail?.name,
            corporationTicker: corporationDetail?.ticker,
            allianceID: detail.allianceId,
            allianceName: allianceDetailResult?.name,
            allianceTicker: allianceDetailResult?.ticker,
            balance: walletBalance,
            location: whereabouts.map { current(at: $0, named: named) },
            shipTypeID: currentShip.flatMap { UInt32(exactly: $0.shipTypeId) }.map(TypeID.init(rawValue:)),
            shipName: currentShip?.shipName,
            homeLocation: cloneList?.homeLocation?.locationId.flatMap { named[$0] },
            lastCloneJumpDate: cloneList?.lastCloneJumpDate,
            jumpClones: (cloneList?.jumpClones ?? []).map { clone in
                JumpClone(
                    id: clone.jumpCloneId,
                    name: clone.name.flatMap { $0.isEmpty ? nil : $0 },
                    location: named[clone.locationId] ?? Location(),
                    implants: clone.implants.compactMap(typeID(from:))
                )
            }
        )
    }

    /// Resolves every station and structure in `places` in parallel. A location that fails to
    /// resolve becomes a `Location` with only its id.
    private static func names(of places: [Int64: Place], client: Client) async -> [Int64: Location] {
        guard !places.isEmpty else { return [:] }

        return await withTaskGroup(of: (Int64, Location).self) { group in
            for (id, place) in places {
                group.addTask {
                    switch place {
                    case .station:
                        guard let station = try? await client.station(id: id) else {
                            return (id, Location(locationID: id))
                        }
                        return (id, Location(solarSystemID: solarSystemID(from: station.systemId),
                                             name: station.name,
                                             locationID: id))
                    case .structure:
                        guard let structure = try? await client.structure(id: id) else {
                            return (id, Location(locationID: id))
                        }
                        return (id, Location(solarSystemID: solarSystemID(from: structure.solarSystemId),
                                             name: structure.name,
                                             locationID: id))
                    }
                }
            }

            var result: [Int64: Location] = [:]
            for await (id, location) in group {
                result[id] = location
            }
            return result
        }
    }

    /// The character's current location; the solar system from `/location` is kept even when
    /// the station or structure could not be resolved.
    private static func current(at whereabouts: Components.Schemas.CharactersCharacterIdLocationGet,
                                named: [Int64: Location]) -> Location {
        let system = solarSystemID(from: whereabouts.solarSystemId)
        let place = whereabouts.stationId.flatMap { named[$0] } ?? whereabouts.structureId.flatMap { named[$0] }
        return Location(solarSystemID: place?.solarSystemID ?? system,
                        name: place?.name,
                        locationID: whereabouts.stationId ?? whereabouts.structureId)
    }

    private static func solarSystemID(from rawValue: Int64) -> SolarSystemID? {
        UInt32(exactly: rawValue).map(SolarSystemID.init(rawValue:))
    }

    private static func typeID(from rawValue: Int64) -> TypeID? {
        UInt32(exactly: rawValue).map(TypeID.init(rawValue:))
    }
}
