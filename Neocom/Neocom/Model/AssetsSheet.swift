import AssetsKit
import ESIKit
import Foundation
import Observation

/// A character's or a corporation's assets as stored in `ESICache`: asset records, custom item
/// names and resolved root locations.
nonisolated struct ESIAssets: Codable, Sendable, Hashable {
    var records: [AssetRecord]
    /// Custom names by item id. Unnamed items are omitted (ESI answers `"None"` for them).
    var names: [Int64: String]
    /// Root locations (a `locationID` that is not an item) that could be resolved.
    var locations: [Int64: AssetLocationInfo]
    /// ESI names of types missing from the SDE (unpublished ones, such as the Asset Safety
    /// Wrap). Filled by the owner's `resolveTypeNames(missing:)` and carried over to later
    /// fetches.
    var typeNames: [Int64: String] = [:]

    private enum CodingKeys: String, CodingKey {
        case records, names, locations, typeNames
    }
}

nonisolated extension ESIAssets {
    /// Decodes files without `typeNames`.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        records = try container.decode([AssetRecord].self, forKey: .records)
        names = try container.decode([Int64: String].self, forKey: .names)
        locations = try container.decode([Int64: AssetLocationInfo].self, forKey: .locations)
        typeNames = try container.decodeIfPresent([Int64: String].self, forKey: .typeNames) ?? [:]
    }
}

/// The asset list changed on the server during paging, twice in a row.
nonisolated struct AssetsListChangedError: LocalizedError {
    var errorDescription: String? {
        String(localized: "EVE updated the asset list while it was being downloaded. Pull to refresh in a minute.")
    }
}

/// Progress of an assets fetch.
nonisolated struct AssetsLoadProgress: Sendable, Hashable {
    enum Phase: Sendable, Hashable {
        case pages
        case names
        case locations
    }

    var phase: Phase
    var pagesLoaded: Int
    /// `nil` until the first page arrives.
    var pageCount: Int?

    /// 0…1 across the whole fetch.
    var fraction: Double {
        let pages = pageCount.map { Double(pagesLoaded) / Double(max($0, 1)) } ?? 0
        switch phase {
        case .pages: return pages * 0.85
        case .names: return 0.9
        case .locations: return 0.95
        }
    }
}

/// A character's assets.
///
/// The only owner of `/characters/{id}/assets` and `/characters/{id}/assets/names`. Records,
/// names and locations share one snapshot so they always describe the same fetch.
@Observable
@MainActor
final class AssetsSheet {
    /// ESI's cache time for the route.
    private static let ttl: TimeInterval = 3600

    let characterID: Int64
    private(set) var snapshot: ESISnapshot<ESIAssets>

    /// Progress of the fetch in flight; meaningful only while `state` is `.loading`.
    var progress: AssetsLoadProgress? { context.progress }

    var value: ESIAssets? { snapshot.value }
    var fetchedAt: Date? { snapshot.fetchedAt }
    var state: ESISnapshot<ESIAssets>.State { snapshot.state }
    var revision: Int { snapshot.revision }

    @ObservationIgnored private let context: AssetsFetch.Context
    @ObservationIgnored private let client: Client

    init(characterID: Int64, client: Client) {
        self.characterID = characterID
        self.client = client
        let context = AssetsFetch.Context()
        self.context = context
        let routes = AssetsRoutes(
            page: { number in
                let answer = try await client.assets(characterID: characterID, page: number)
                return (answer.records.map(AssetRecord.init), answer.pages, answer.lastModified)
            },
            names: { itemIDs in
                try await client.assetNames(characterID: characterID, itemIDs: itemIDs).map { ($0.itemId, $0.name) }
            }
        )
        snapshot = ESISnapshot(kind: "assets",
                               characterID: characterID,
                               ttl: Self.ttl,
                               cache: ESICache()) {
            try await AssetsFetch.fetch(routes: routes, client: client, context: context)
        }
        context.seed(from: snapshot.value)
    }

    /// Cancels the fetch in flight and stops all disk writes; called by `AccountStore`.
    func invalidate() {
        snapshot.invalidate()
    }

    /// Resolves through ESI the names of types missing from the SDE and amends the value with
    /// them. Best effort, each id requested once per sheet. Returns whether any name was added.
    func resolveTypeNames(missing: Set<Int64>) async -> Bool {
        await context.resolveTypeNames(missing: missing, in: snapshot, client: client)
    }

    /// Refreshes the assets if missing or past the TTL.
    func ensureFresh() async {
        await snapshot.ensureFresh()
    }

    func refresh() async {
        await snapshot.refresh()
    }
}

extension AssetsSheet: AssetsSource {
    var corporationID: Int64? { nil }
    var access: BusinessAccess { .granted }
}

nonisolated extension AssetRecord {
    init(_ payload: Components.Schemas.CharactersCharacterIdAssetsGetPayload) {
        self.init(itemID: payload.itemId,
                  typeID: payload.typeId,
                  locationID: payload.locationId,
                  locationFlag: payload.locationFlag.rawValue,
                  locationType: payload.locationType.rawValue,
                  quantity: payload.quantity,
                  isSingleton: payload.isSingleton,
                  isBlueprintCopy: payload.isBlueprintCopy ?? false)
    }
}
