import ESIKit
import Foundation
import Observation

/// A character's in-game fittings.
///
/// The only owner of `/characters/{id}/fittings` (read, create and delete).
@Observable
@MainActor
final class FittingsSheet {
    /// ESI's cache time for the route.
    private static let ttl: TimeInterval = 300

    let characterID: Int64
    private(set) var snapshot: ESISnapshot<[ESIFitting]>

    @ObservationIgnored private let client: Client

    // `ESICache()` is created in the body: default arguments are not evaluated on the main actor.
    init(characterID: Int64, client: Client) {
        self.characterID = characterID
        self.client = client
        snapshot = ESISnapshot(kind: "fittings",
                               characterID: characterID,
                               ttl: Self.ttl,
                               cache: ESICache()) {
            try await client.fittings(characterID: characterID).map(ESIFitting.init)
        }
    }

    /// Refreshes the list if missing or past the TTL.
    func ensureFresh() async {
        await snapshot.ensureFresh()
    }

    /// Cancels the fetch in flight and stops all disk writes; called by `AccountStore`.
    func invalidate() {
        snapshot.invalidate()
    }

    /// Within five minutes of the last fetch ESI answers from its own cache.
    func refresh() async {
        await snapshot.refresh()
    }

    /// Uploads a fit and returns its in-game id.
    ///
    /// The snapshot is patched locally instead of refetched: ESI caches `GET /fittings` for five
    /// minutes and would return the list without the new fit. On error the snapshot is unchanged.
    @discardableResult
    func create(name: String,
                description: String,
                shipTypeID: Int64,
                items: [ESIFitting.Item]) async throws -> Int64 {
        let payload = items.compactMap(Self.payload(for:))
        let id = try await client.createFitting(characterID: characterID,
                                               name: name,
                                               description: description,
                                               shipTypeID: shipTypeID,
                                               items: payload)

        // Built from the sent payload, so items dropped from the request are absent here too.
        let created = ESIFitting(id: id,
                                 name: name,
                                 fittingDescription: description,
                                 shipTypeID: shipTypeID,
                                 items: payload.map { ESIFitting.Item(typeID: $0.typeId,
                                                                     flag: $0.flag.rawValue,
                                                                     quantity: $0.quantity) })
        snapshot.replace((snapshot.value ?? []) + [created])
        return id
    }

    /// Deletes an in-game fitting and removes it from the snapshot without refetching (see
    /// `create`). On error the snapshot is unchanged.
    func delete(id: Int64) async throws {
        try await client.deleteFitting(characterID: characterID, fittingID: id)
        snapshot.replace((snapshot.value ?? []).filter { $0.id != id })
    }

    /// `ESIFitting.Item` as the generated POST body type; `nil` for a flag the generated enum
    /// does not know.
    private static func payload(for item: ESIFitting.Item)
        -> Operations.PostCharactersCharacterIdFittings.Input.Body.JsonPayload.ItemsPayloadPayload? {
        guard let flag = Operations.PostCharactersCharacterIdFittings.Input.Body.JsonPayload
            .ItemsPayloadPayload.FlagPayload(rawValue: item.flag) else { return nil }
        return .init(flag: flag, quantity: item.quantity, typeId: item.typeID)
    }
}
