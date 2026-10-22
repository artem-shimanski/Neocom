import ESIKit
import Foundation

nonisolated enum ESIError: LocalizedError {
    case http(status: Int, message: String?)

    var errorDescription: String? {
        switch self {
        case let .http(status, message):
            message ?? String(localized: "ESI request failed with status \(status).")
        }
    }
}

/// Typed wrappers over the generated ESI operations, in the shapes the screens use.
nonisolated extension Client {
    /// Public information about a character.
    func character(id: Int64) async throws -> Components.Schemas.CharactersDetail {
        let output = try await getCharactersDetail(
            path: .init(characterId: id),
            headers: .init(xCompatibilityDate: ESIService.compatibilityDate)
        )
        switch output {
        case let .ok(ok):
            return try ok.body.json
        case let .default(status, response):
            throw ESIError.http(status: status, message: try? response.body.json.error)
        }
    }

    /// Public information about a corporation.
    func corporation(id: Int64) async throws -> Components.Schemas.CorporationsDetail {
        let output = try await getCorporationsCorporationId(
            path: .init(corporationId: id),
            headers: .init(xCompatibilityDate: ESIService.compatibilityDate)
        )
        switch output {
        case let .ok(ok):
            return try ok.body.json
        case let .default(status, response):
            throw ESIError.http(status: status, message: try? response.body.json.error)
        }
    }

    /// A character's attributes.
    func characterAttributes(id: Int64) async throws -> Components.Schemas.CharactersCharacterIdAttributesGet {
        let output = try await getCharactersCharacterIdAttributes(
            path: .init(characterId: id),
            headers: .init(xCompatibilityDate: ESIService.compatibilityDate)
        )
        switch output {
        case let .ok(ok):
            return try ok.body.json
        case let .default(status, response):
            throw ESIError.http(status: status, message: try? response.body.json.error)
        }
    }

    /// The implants on a character's active clone.
    func characterImplants(id: Int64) async throws -> [Int64] {
        let output = try await getCharactersCharacterIdImplants(
            path: .init(characterId: id),
            headers: .init(xCompatibilityDate: ESIService.compatibilityDate)
        )
        switch output {
        case let .ok(ok):
            return try ok.body.json
        case let .default(status, response):
            throw ESIError.http(status: status, message: try? response.body.json.error)
        }
    }

    /// All trained skills for a character.
    func characterSkills(id: Int64) async throws -> Components.Schemas.CharactersSkills {
        let output = try await getCharactersCharacterIdSkills(
            path: .init(characterId: id),
            headers: .init(xCompatibilityDate: ESIService.compatibilityDate)
        )
        switch output {
        case let .ok(ok):
            return try ok.body.json
        case let .default(status, response):
            throw ESIError.http(status: status, message: try? response.body.json.error)
        }
    }

    /// A character's skill training queue.
    func characterSkillQueue(id: Int64) async throws -> [Components.Schemas.CharactersSkillqueueSkill] {
        let output = try await getCharactersCharacterIdSkillqueue(
            path: .init(characterId: id),
            headers: .init(xCompatibilityDate: ESIService.compatibilityDate)
        )
        switch output {
        case let .ok(ok):
            return try ok.body.json
        case let .default(status, response):
            throw ESIError.http(status: status, message: try? response.body.json.error)
        }
    }

    /// A character's wallet balance, in ISK.
    func characterWallet(id: Int64) async throws -> Double {
        let output = try await getCharactersCharacterIdWallet(
            path: .init(characterId: id),
            headers: .init(xCompatibilityDate: ESIService.compatibilityDate)
        )
        switch output {
        case let .ok(ok):
            return try ok.body.json
        case let .default(status, response):
            throw ESIError.http(status: status, message: try? response.body.json.error)
        }
    }

    /// A character's home station and jump clones, with the implants in each of them.
    func characterClones(id: Int64) async throws -> Components.Schemas.CharactersCharacterIdClonesGet {
        let output = try await getCharactersCharacterIdClones(
            path: .init(characterId: id),
            headers: .init(xCompatibilityDate: ESIService.compatibilityDate)
        )
        switch output {
        case let .ok(ok):
            return try ok.body.json
        case let .default(status, response):
            throw ESIError.http(status: status, message: try? response.body.json.error)
        }
    }

    /// Where a character is right now: the solar system, and the station or structure they
    /// are docked in, if any.
    func characterLocation(id: Int64) async throws -> Components.Schemas.CharactersCharacterIdLocationGet {
        let output = try await getCharactersCharacterIdLocation(
            path: .init(characterId: id),
            headers: .init(xCompatibilityDate: ESIService.compatibilityDate)
        )
        switch output {
        case let .ok(ok):
            return try ok.body.json
        case let .default(status, response):
            throw ESIError.http(status: status, message: try? response.body.json.error)
        }
    }

    /// The ship a character is flying, and the name they gave it.
    func characterShip(id: Int64) async throws -> Components.Schemas.CharactersCharacterIdShipGet {
        let output = try await getCharactersCharacterIdShip(
            path: .init(characterId: id),
            headers: .init(xCompatibilityDate: ESIService.compatibilityDate)
        )
        switch output {
        case let .ok(ok):
            return try ok.body.json
        case let .default(status, response):
            throw ESIError.http(status: status, message: try? response.body.json.error)
        }
    }

    /// Public information about an alliance.
    func alliance(id: Int64) async throws -> Components.Schemas.AllianceDetail {
        let output = try await getAlliancesAllianceId(
            path: .init(allianceId: id),
            headers: .init(xCompatibilityDate: ESIService.compatibilityDate)
        )
        switch output {
        case let .ok(ok):
            return try ok.body.json
        case let .default(status, response):
            throw ESIError.http(status: status, message: try? response.body.json.error)
        }
    }

    /// An NPC station, by id. Public.
    ///
    /// The SDE has no station rows, so ESI is the only source of station names.
    func station(id: Int64) async throws -> Components.Schemas.UniverseStationsStationIdGet {
        let output = try await getUniverseStationsStationId(
            path: .init(stationId: id),
            headers: .init(xCompatibilityDate: ESIService.compatibilityDate)
        )
        switch output {
        case let .ok(ok):
            return try ok.body.json
        case let .default(status, response):
            throw ESIError.http(status: status, message: try? response.body.json.error)
        }
    }

    /// A player-owned structure, by id. Authenticated; `403` is the expected response for a
    /// character without docking access.
    func structure(id: Int64) async throws -> Components.Schemas.UniverseStructuresStructureIdGet {
        let output = try await getUniverseStructuresStructureId(
            path: .init(structureId: id),
            headers: .init(xCompatibilityDate: ESIService.compatibilityDate)
        )
        switch output {
        case let .ok(ok):
            return try ok.body.json
        case let .default(status, response):
            throw ESIError.http(status: status, message: try? response.body.json.error)
        }
    }

    /// The fittings a character has saved in the game client.
    func fittings(characterID: Int64) async throws -> Components.Schemas.CharactersCharacterIdFittingsGet {
        let output = try await getCharactersCharacterIdFittings(
            path: .init(characterId: characterID),
            headers: .init(xCompatibilityDate: ESIService.compatibilityDate)
        )
        switch output {
        case let .ok(ok):
            return try ok.body.json
        case let .default(status, response):
            throw ESIError.http(status: status, message: try? response.body.json.error)
        }
    }

    /// Saves a new fitting for a character. Answers the id the game gave it.
    func createFitting(characterID: Int64,
                        name: String,
                        description: String,
                        shipTypeID: Int64,
                        items: [Operations.PostCharactersCharacterIdFittings.Input.Body.JsonPayload.ItemsPayloadPayload]) async throws -> Int64 {
        let output = try await postCharactersCharacterIdFittings(
            path: .init(characterId: characterID),
            headers: .init(xCompatibilityDate: ESIService.compatibilityDate),
            body: .json(.init(description: description, items: items, name: name, shipTypeId: shipTypeID))
        )
        switch output {
        case let .created(created):
            return try created.body.json.fittingId
        case let .default(status, response):
            throw ESIError.http(status: status, message: try? response.body.json.error)
        }
    }

    /// Deletes one fitting. Answers nothing: ESI replies `204`.
    func deleteFitting(characterID: Int64, fittingID: Int64) async throws {
        let output = try await deleteCharactersCharacterIdFittingsFittingId(
            path: .init(characterId: characterID, fittingId: fittingID),
            headers: .init(xCompatibilityDate: ESIService.compatibilityDate)
        )
        switch output {
        case .noContent:
            return
        case let .default(status, response):
            throw ESIError.http(status: status, message: try? response.body.json.error)
        }
    }

    /// The planetary colonies of a character: one header per planet, with the moment the
    /// server last recomputed it.
    func planets(characterID: Int64) async throws -> Components.Schemas.CharactersCharacterIdPlanetsGet {
        let output = try await getCharactersCharacterIdPlanets(
            path: .init(characterId: characterID),
            headers: .init(xCompatibilityDate: ESIService.compatibilityDate)
        )
        switch output {
        case let .ok(ok):
            return try ok.body.json
        case let .default(status, response):
            throw ESIError.http(status: status, message: try? response.body.json.error)
        }
    }

    /// The layout of one colony — pins, links, routes — as of the header's `last_update`.
    func colonyLayout(characterID: Int64, planetID: Int64) async throws -> Components.Schemas.CharactersCharacterIdPlanetsPlanetIdGet {
        let output = try await getCharactersCharacterIdPlanetsPlanetId(
            path: .init(characterId: characterID, planetId: planetID),
            headers: .init(xCompatibilityDate: ESIService.compatibilityDate)
        )
        switch output {
        case let .ok(ok):
            return try ok.body.json
        case let .default(status, response):
            throw ESIError.http(status: status, message: try? response.body.json.error)
        }
    }

    /// One page of a character's assets (1000 records per page), with the page count and the
    /// page's `Last-Modified`, which is identical across the pages of one server-side cache
    /// snapshot. Page numbers start at 1.
    func assets(characterID: Int64, page: Int) async throws -> (records: Components.Schemas.CharactersCharacterIdAssetsGet,
                                                                  pages: Int,
                                                                  lastModified: String?) {
        let output = try await getCharactersCharacterIdAssets(
            path: .init(characterId: characterID),
            query: .init(page: Int32(clamping: page)),
            headers: .init(xCompatibilityDate: ESIService.compatibilityDate)
        )
        switch output {
        case let .ok(ok):
            return (try ok.body.json, max(Int(clamping: ok.headers.xPages ?? 1), 1), ok.headers.lastModified)
        case let .default(status, response):
            throw ESIError.http(status: status, message: try? response.body.json.error)
        }
    }

    /// Player-assigned names of items (ships and containers), by item id. At most 1000 ids per
    /// call. ESI returns `"None"` for an unnamed item.
    func assetNames(characterID: Int64, itemIDs: [Int64]) async throws -> Components.Schemas.CharactersCharacterIdAssetsNamesPost {
        let output = try await postCharactersCharacterIdAssetsNames(
            path: .init(characterId: characterID),
            headers: .init(xCompatibilityDate: ESIService.compatibilityDate),
            body: .json(itemIDs)
        )
        switch output {
        case let .ok(ok):
            return try ok.body.json
        case let .default(status, response):
            throw ESIError.http(status: status, message: try? response.body.json.error)
        }
    }

    /// Names of inventory types, by type id, for types missing from the bundled SDE
    /// (unpublished ones, such as the Asset Safety Wrap). Public. At most 1000 ids per call;
    /// ESI returns `404` for the whole call when any id is invalid.
    func typeNames(typeIDs: [Int64]) async throws -> [Int64: String] {
        try await universeNames(ids: typeIDs, category: .inventoryType)
    }

    /// Names of NPC stations, by station id. Public; same limits as `typeNames(typeIDs:)`.
    func stationNames(stationIDs: [Int64]) async throws -> [Int64: String] {
        try await universeNames(ids: stationIDs, category: .station)
    }

    private func universeNames(ids: [Int64],
                               category: Components.Schemas.UniverseNamesPostPayload.CategoryPayload) async throws -> [Int64: String] {
        let output = try await postUniverseNames(
            headers: .init(xCompatibilityDate: ESIService.compatibilityDate),
            body: .json(ids)
        )
        switch output {
        case let .ok(ok):
            var names: [Int64: String] = [:]
            for entry in try ok.body.json where entry.category == category && !entry.name.isEmpty {
                names[entry.id] = entry.name
            }
            return names
        case let .default(status, response):
            throw ESIError.http(status: status, message: try? response.body.json.error)
        }
    }

    /// Names and categories of arbitrary ids (characters, corporations, alliances, …). Public.
    /// At most 1000 ids per call; ESI returns `404` for the whole call when any id is invalid,
    /// so ids of unknown provenance go through `UniverseNameLookup`, which splits rejected
    /// calls.
    func entityNames(ids: [Int64]) async throws -> [Int64: ESIEntityName] {
        let output = try await postUniverseNames(
            headers: .init(xCompatibilityDate: ESIService.compatibilityDate),
            body: .json(ids)
        )
        switch output {
        case let .ok(ok):
            var names: [Int64: ESIEntityName] = [:]
            for entry in try ok.body.json where !entry.name.isEmpty {
                names[entry.id] = ESIEntityName(name: entry.name, category: ESIEntityName.Category(rawValue: entry.category.rawValue) ?? .other)
            }
            return names
        case let .default(status, response):
            throw ESIError.http(status: status, message: try? response.body.json.error)
        }
    }

    /// Tranquility's status: players online, VIP mode. Public; cached by ESI for 30 seconds.
    /// Fails (usually `503`) while the server is down, including daily downtime.
    func serverStatus() async throws -> Components.Schemas.StatusGet {
        let output = try await getStatus(
            headers: .init(xCompatibilityDate: ESIService.compatibilityDate)
        )
        switch output {
        case let .ok(ok):
            return try ok.body.json
        case let .default(status, response):
            throw ESIError.http(status: status, message: try? response.body.json.error)
        }
    }

    /// CCP's universe-wide average and adjusted prices of every type that has them. Public;
    /// cached by ESI for an hour.
    func marketPrices() async throws -> Components.Schemas.MarketsPricesGet {
        let output = try await getMarketsPrices(
            headers: .init(xCompatibilityDate: ESIService.compatibilityDate)
        )
        switch output {
        case let .ok(ok):
            return try ok.body.json
        case let .default(status, response):
            throw ESIError.http(status: status, message: try? response.body.json.error)
        }
    }

    /// One page of a type's buy and sell orders in a region, with the page count. Public;
    /// cached by ESI for five minutes. Page numbers start at 1.
    func marketOrders(regionID: Int64, typeID: Int64, page: Int) async throws -> (orders: Components.Schemas.MarketsRegionIdOrdersGet,
                                                                                 pages: Int) {
        let output = try await getMarketsRegionIdOrders(
            path: .init(regionId: regionID),
            query: .init(orderType: .all, page: Int32(clamping: page), typeId: typeID),
            headers: .init(xCompatibilityDate: ESIService.compatibilityDate)
        )
        switch output {
        case let .ok(ok):
            return (try ok.body.json, max(Int(clamping: ok.headers.xPages ?? 1), 1))
        case let .default(status, response):
            throw ESIError.http(status: status, message: try? response.body.json.error)
        }
    }

    /// A type's daily market statistics in a region, about 18 months. Public; refreshed by ESI
    /// daily at 11:05 UTC.
    func marketHistory(regionID: Int64, typeID: Int64) async throws -> Components.Schemas.MarketsRegionIdHistoryGet {
        let output = try await getMarketsRegionIdHistory(
            path: .init(regionId: regionID),
            query: .init(typeId: typeID),
            headers: .init(xCompatibilityDate: ESIService.compatibilityDate)
        )
        switch output {
        case let .ok(ok):
            return try ok.body.json
        case let .default(status, response):
            throw ESIError.http(status: status, message: try? response.body.json.error)
        }
    }

    /// The shortest gate route between two systems, both ends included, so the jump count is
    /// its length minus one. Public. ESI returns `404` when no route exists (wormhole space, or
    /// a system cut off from the gate network).
    func route(from origin: Int64, to destination: Int64) async throws -> [Int64] {
        let output = try await postRoute(
            path: .init(originSystemId: origin, destinationSystemId: destination),
            headers: .init(xCompatibilityDate: ESIService.compatibilityDate),
            body: .json(.init(preference: .shorter))
        )
        switch output {
        case let .ok(ok):
            return try ok.body.json.route
        case let .default(status, response):
            throw ESIError.http(status: status, message: try? response.body.json.error)
        }
    }

    /// A planet, by id. Public; the bundled SDE has no planets.
    func planet(id: Int64) async throws -> Components.Schemas.UniversePlanetsPlanetIdGet {
        let output = try await getUniversePlanetsPlanetId(
            path: .init(planetId: id),
            headers: .init(xCompatibilityDate: ESIService.compatibilityDate)
        )
        switch output {
        case let .ok(ok):
            return try ok.body.json
        case let .default(status, response):
            throw ESIError.http(status: status, message: try? response.body.json.error)
        }
    }

    /// A character's open market orders, personal and corporate. Not paged. Cached by ESI for
    /// 20 minutes.
    func characterOrders(characterID: Int64) async throws -> Components.Schemas.CharactersCharacterIdOrdersGet {
        let output = try await getCharactersCharacterIdOrders(
            path: .init(characterId: characterID),
            headers: .init(xCompatibilityDate: ESIService.compatibilityDate)
        )
        switch output {
        case let .ok(ok):
            return try ok.body.json
        case let .default(status, response):
            throw ESIError.http(status: status, message: try? response.body.json.error)
        }
    }

    /// One page of a character's expired and cancelled orders of the last 90 days, with the
    /// page count. Cached by ESI for an hour. Page numbers start at 1.
    func characterOrderHistory(characterID: Int64, page: Int) async throws -> (orders: Components.Schemas.CharactersCharacterIdOrdersHistoryGet,
                                                                              pages: Int) {
        let output = try await getCharactersCharacterIdOrdersHistory(
            path: .init(characterId: characterID),
            query: .init(page: Int32(clamping: page)),
            headers: .init(xCompatibilityDate: ESIService.compatibilityDate)
        )
        switch output {
        case let .ok(ok):
            return (try ok.body.json, max(Int(clamping: ok.headers.xPages ?? 1), 1))
        case let .default(status, response):
            throw ESIError.http(status: status, message: try? response.body.json.error)
        }
    }

    /// A character's industry jobs; with `includeCompleted`, also delivered, cancelled and
    /// reverted jobs of the last 90 days. Not paged. Cached by ESI for five minutes.
    func industryJobs(characterID: Int64, includeCompleted: Bool) async throws -> Components.Schemas.CharactersCharacterIdIndustryJobsGet {
        let output = try await getCharactersCharacterIdIndustryJobs(
            path: .init(characterId: characterID),
            query: .init(includeCompleted: includeCompleted),
            headers: .init(xCompatibilityDate: ESIService.compatibilityDate)
        )
        switch output {
        case let .ok(ok):
            return try ok.body.json
        case let .default(status, response):
            throw ESIError.http(status: status, message: try? response.body.json.error)
        }
    }

    /// One page of a character's contracts (active ones and 30 days of finished ones), with
    /// the page count. Cached by ESI for five minutes. Page numbers start at 1.
    func contracts(characterID: Int64, page: Int) async throws -> (contracts: Components.Schemas.CharactersCharacterIdContractsGet,
                                                                  pages: Int) {
        let output = try await getCharactersCharacterIdContracts(
            path: .init(characterId: characterID),
            query: .init(page: Int32(clamping: page)),
            headers: .init(xCompatibilityDate: ESIService.compatibilityDate)
        )
        switch output {
        case let .ok(ok):
            return (try ok.body.json, max(Int(clamping: ok.headers.xPages ?? 1), 1))
        case let .default(status, response):
            throw ESIError.http(status: status, message: try? response.body.json.error)
        }
    }

    /// The items of a character's contract, offered and requested. Contract items are
    /// immutable.
    func contractItems(characterID: Int64, contractID: Int64) async throws -> Components.Schemas.CharactersCharacterIdContractsContractIdItemsGet {
        let output = try await getCharactersCharacterIdContractsContractIdItems(
            path: .init(characterId: characterID, contractId: contractID),
            headers: .init(xCompatibilityDate: ESIService.compatibilityDate)
        )
        switch output {
        case let .ok(ok):
            return try ok.body.json
        case let .default(status, response):
            throw ESIError.http(status: status, message: try? response.body.json.error)
        }
    }

    /// The bids on one of a character's auctions. Cached by ESI for five minutes.
    func contractBids(characterID: Int64, contractID: Int64) async throws -> Components.Schemas.CharactersCharacterIdContractsContractIdBidsGet {
        let output = try await getCharactersCharacterIdContractsContractIdBids(
            path: .init(characterId: characterID, contractId: contractID),
            headers: .init(xCompatibilityDate: ESIService.compatibilityDate)
        )
        switch output {
        case let .ok(ok):
            return try ok.body.json
        case let .default(status, response):
            throw ESIError.http(status: status, message: try? response.body.json.error)
        }
    }

    // MARK: - Mail

    /// One page of a character's mail headers, newest first: at most 50, older than
    /// `lastMailID` when given, filtered by `labels` when given. Cached by ESI for 30 seconds.
    func mailHeaders(characterID: Int64, labels: [Int64]?, lastMailID: Int64?) async throws -> Components.Schemas.CharactersCharacterIdMailGet {
        let output = try await getCharactersCharacterIdMail(
            path: .init(characterId: characterID),
            query: .init(labels: labels, lastMailId: lastMailID),
            headers: .init(xCompatibilityDate: ESIService.compatibilityDate)
        )
        switch output {
        case let .ok(ok):
            return try ok.body.json
        case let .default(status, response):
            throw ESIError.http(status: status, message: try? response.body.json.error)
        }
    }

    /// One mail with its body. Mail bodies are immutable.
    func mail(characterID: Int64, mailID: Int64) async throws -> Components.Schemas.CharactersCharacterIdMailMailIdGet {
        let output = try await getCharactersCharacterIdMailMailId(
            path: .init(characterId: characterID, mailId: mailID),
            headers: .init(xCompatibilityDate: ESIService.compatibilityDate)
        )
        switch output {
        case let .ok(ok):
            return try ok.body.json
        case let .default(status, response):
            throw ESIError.http(status: status, message: try? response.body.json.error)
        }
    }

    /// Marks a mail read or unread and/or replaces its labels; `nil` leaves that part
    /// unchanged. ESI replies `204`.
    func updateMail(characterID: Int64, mailID: Int64, read: Bool?, labels: [Int64]?) async throws {
        let output = try await putCharactersCharacterIdMailMailId(
            path: .init(characterId: characterID, mailId: mailID),
            headers: .init(xCompatibilityDate: ESIService.compatibilityDate),
            body: .json(.init(labels: labels, read: read))
        )
        switch output {
        case .noContent:
            return
        case let .default(status, response):
            throw ESIError.http(status: status, message: try? response.body.json.error)
        }
    }

    /// Deletes a mail. ESI replies `204`.
    func deleteMail(characterID: Int64, mailID: Int64) async throws {
        let output = try await deleteCharactersCharacterIdMailMailId(
            path: .init(characterId: characterID, mailId: mailID),
            headers: .init(xCompatibilityDate: ESIService.compatibilityDate)
        )
        switch output {
        case .noContent:
            return
        case let .default(status, response):
            throw ESIError.http(status: status, message: try? response.body.json.error)
        }
    }

    /// Sends a mail and returns its id. A rejection is an `ESIError` carrying ESI's message and
    /// the messages of its details, where a CSPA rejection may add more.
    func sendMail(characterID: Int64,
                  recipients: [Operations.PostCharactersCharacterIdMail.Input.Body.JsonPayload.RecipientsPayloadPayload],
                  subject: String,
                  body: String,
                  approvedCost: Int64) async throws -> Int64 {
        let output = try await postCharactersCharacterIdMail(
            path: .init(characterId: characterID),
            headers: .init(xCompatibilityDate: ESIService.compatibilityDate),
            body: .json(.init(approvedCost: approvedCost, body: body, recipients: recipients, subject: subject))
        )
        switch output {
        case let .created(created):
            return try created.body.json
        case let .default(status, response):
            let error = try? response.body.json
            let parts = [error?.error] + (error?.details ?? []).map(\.message)
            let message = parts.compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ")
            throw ESIError.http(status: status, message: message.isEmpty ? nil : message)
        }
    }

    /// A character's mail labels with unread counts, and the unread total.
    func mailLabels(characterID: Int64) async throws -> Components.Schemas.CharactersCharacterIdMailLabelsGet {
        let output = try await getCharactersCharacterIdMailLabels(
            path: .init(characterId: characterID),
            headers: .init(xCompatibilityDate: ESIService.compatibilityDate)
        )
        switch output {
        case let .ok(ok):
            return try ok.body.json
        case let .default(status, response):
            throw ESIError.http(status: status, message: try? response.body.json.error)
        }
    }

    /// Creates a mail label and returns its id. `color` must be one of EVE's 18
    /// (`MailLabelColor`).
    func createMailLabel(characterID: Int64, name: String, color: String) async throws -> Int64 {
        let output = try await postCharactersCharacterIdMailLabels(
            path: .init(characterId: characterID),
            headers: .init(xCompatibilityDate: ESIService.compatibilityDate),
            body: .json(.init(color: .init(rawValue: color.lowercased()), name: name))
        )
        switch output {
        case let .created(created):
            return try created.body.json
        case let .default(status, response):
            throw ESIError.http(status: status, message: try? response.body.json.error)
        }
    }

    /// Deletes a mail label; its mail keeps its other labels. ESI replies `204`.
    func deleteMailLabel(characterID: Int64, labelID: Int64) async throws {
        let output = try await deleteCharactersCharacterIdMailLabelsLabelId(
            path: .init(characterId: characterID, labelId: labelID),
            headers: .init(xCompatibilityDate: ESIService.compatibilityDate)
        )
        switch output {
        case .noContent:
            return
        case let .default(status, response):
            throw ESIError.http(status: status, message: try? response.body.json.error)
        }
    }

    /// The mailing lists a character is on.
    func mailingLists(characterID: Int64) async throws -> Components.Schemas.CharactersCharacterIdMailListsGet {
        let output = try await getCharactersCharacterIdMailLists(
            path: .init(characterId: characterID),
            headers: .init(xCompatibilityDate: ESIService.compatibilityDate)
        )
        switch output {
        case let .ok(ok):
            return try ok.body.json
        case let .default(status, response):
            throw ESIError.http(status: status, message: try? response.body.json.error)
        }
    }

    /// The CSPA charge `characterID` would pay to mail `targets` (character ids), in ISK.
    func cspaCharge(characterID: Int64, targets: [Int64]) async throws -> Double {
        let output = try await postCharactersCharacterIdCspa(
            path: .init(characterId: characterID),
            headers: .init(xCompatibilityDate: ESIService.compatibilityDate),
            body: .json(targets)
        )
        switch output {
        case let .created(created):
            return try created.body.json
        case let .default(status, response):
            throw ESIError.http(status: status, message: try? response.body.json.error)
        }
    }

    /// One page of a character's contacts, with the page count. Page numbers start at 1.
    func contacts(characterID: Int64, page: Int) async throws -> (contacts: Components.Schemas.CharactersCharacterIdContactsGet,
                                                                 pages: Int) {
        let output = try await getCharactersCharacterIdContacts(
            path: .init(characterId: characterID),
            query: .init(page: Int32(clamping: page)),
            headers: .init(xCompatibilityDate: ESIService.compatibilityDate)
        )
        switch output {
        case let .ok(ok):
            return (try ok.body.json, max(Int(clamping: ok.headers.xPages ?? 1), 1))
        case let .default(status, response):
            throw ESIError.http(status: status, message: try? response.body.json.error)
        }
    }

    /// Characters, corporations and alliances whose names contain `text`, as the in-game
    /// search does. ESI requires at least three characters.
    func searchMailRecipients(characterID: Int64, text: String,
                              categories: Operations.GetCharactersCharacterIdSearch.Input.Query.CategoriesPayload = [.character, .corporation, .alliance])
        async throws -> Components.Schemas.CharactersCharacterIdSearchGet {
        let output = try await getCharactersCharacterIdSearch(
            path: .init(characterId: characterID),
            query: .init(categories: categories, search: text, strict: false),
            headers: .init(xCompatibilityDate: ESIService.compatibilityDate)
        )
        switch output {
        case let .ok(ok):
            return try ok.body.json
        case let .default(status, response):
            throw ESIError.http(status: status, message: try? response.body.json.error)
        }
    }

    // MARK: - Killmails

    /// One page of the character's recent kills and losses (ids and hashes only), with the
    /// page count. ESI lists about the last 90 days.
    func recentKillmails(characterID: Int64, page: Int) async throws -> (killmails: Components.Schemas.CharactersCharacterIdKillmailsRecentGet,
                                                                          pages: Int) {
        let output = try await getCharactersCharacterIdKillmailsRecent(
            path: .init(characterId: characterID),
            query: .init(page: Int32(clamping: page)),
            headers: .init(xCompatibilityDate: ESIService.compatibilityDate)
        )
        switch output {
        case let .ok(ok):
            return (try ok.body.json, max(Int(clamping: ok.headers.xPages ?? 1), 1))
        case let .default(status, response):
            throw ESIError.http(status: status, message: try? response.body.json.error)
        }
    }

    /// One killmail, public and addressed by id and hash. Killmails are immutable.
    func killmail(id: Int64, hash: String) async throws -> Components.Schemas.KillmailsKillmailIdKillmailHashGet {
        let output = try await getKillmailsKillmailIdKillmailHash(
            path: .init(killmailHash: hash, killmailId: id),
            headers: .init(xCompatibilityDate: ESIService.compatibilityDate)
        )
        switch output {
        case let .ok(ok):
            return try ok.body.json
        case let .default(status, response):
            throw ESIError.http(status: status, message: try? response.body.json.error)
        }
    }
}
