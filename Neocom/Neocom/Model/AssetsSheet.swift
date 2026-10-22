import AssetsKit
import DogmaKit
import ESIKit
import Foundation
import Observation

/// A character's assets as stored in `ESICache`: asset records, custom item names and resolved
/// root locations.
nonisolated struct ESIAssets: Codable, Sendable, Hashable {
    var records: [AssetRecord]
    /// Custom names by item id. Unnamed items are omitted (ESI answers `"None"` for them).
    var names: [Int64: String]
    /// Root locations (a `locationID` that is not an item) that could be resolved.
    var locations: [Int64: AssetLocationInfo]
    /// ESI names of types missing from the SDE (unpublished ones, such as the Asset Safety
    /// Wrap). Filled by `AssetsSheet.resolveTypeNames(missing:)` and carried over to later
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

    /// State shared with the fetch: progress, and names resolved by earlier fetches.
    @ObservationIgnored private let context: FetchContext
    @ObservationIgnored private let client: Client
    /// Type ids already requested by `resolveTypeNames(missing:)`, each once per sheet.
    @ObservationIgnored private var askedTypeIDs: Set<Int64> = []

    init(characterID: Int64, client: Client) {
        self.characterID = characterID
        self.client = client
        let context = FetchContext()
        self.context = context
        snapshot = ESISnapshot(kind: "assets",
                               characterID: characterID,
                               ttl: Self.ttl,
                               cache: ESICache()) {
            try await Self.fetch(characterID: characterID, client: client, context: context)
        }
        context.knownLocations = snapshot.value?.locations ?? [:]
        context.knownTypeNames = snapshot.value?.typeNames ?? [:]
    }

    /// Cancels the fetch in flight and stops all disk writes; called by `AccountStore`.
    func invalidate() {
        snapshot.invalidate()
    }

    /// Resolves through ESI the names of types missing from the SDE and amends the value with
    /// them. Best effort, each id requested once per sheet. Returns whether any name was added.
    func resolveTypeNames(missing: Set<Int64>) async -> Bool {
        guard let known = snapshot.value?.typeNames else { return false }
        let ask = missing.subtracting(askedTypeIDs).subtracting(known.keys)
        guard !ask.isEmpty else { return false }
        askedTypeIDs.formUnion(ask)

        let found = await Self.typeNames(of: ask.sorted(), client: client)
        guard !found.isEmpty, var value = snapshot.value else { return false }
        context.knownTypeNames.merge(found) { _, new in new }
        value.typeNames.merge(found) { _, new in new }
        snapshot.amend(value)
        return true
    }

    /// Refreshes the assets if missing or past the TTL.
    func ensureFresh() async {
        await snapshot.ensureFresh()
    }

    func refresh() async {
        await snapshot.refresh()
    }

    // MARK: - Fetch

    @Observable
    @MainActor
    final class FetchContext {
        var progress: AssetsLoadProgress?
        @ObservationIgnored var knownLocations: [Int64: AssetLocationInfo] = [:]
        /// Type names found earlier; kept across fetches.
        @ObservationIgnored var knownTypeNames: [Int64: String] = [:]
    }

    /// The pages belong to different server-side snapshots: `Last-Modified` or the page count
    /// changed, or a later page answered `404`.
    nonisolated private struct PageRunChanged: Error {}

    nonisolated private static let width = ESIParallel.width

    /// Fetches all pages, then custom names, then locations.
    ///
    /// A page that fails twice fails the whole fetch; names and locations are best effort.
    nonisolated private static func fetch(characterID: Int64, client: Client, context: FetchContext) async throws -> ESIAssets {
        // ESI serves all pages from one cache snapshot; a run that spans a cache renewal mixes
        // two snapshots and is restarted once.
        var run: (records: [AssetRecord], pages: Int)?
        for attempt in 1...2 where run == nil {
            do {
                run = try await pageRun(characterID: characterID, client: client, context: context)
            } catch is PageRunChanged {
                if attempt == 2 { throw AssetsListChangedError() }
            }
        }
        guard let (records, pageCount) = run else { throw AssetsListChangedError() }

        await MainActor.run { context.progress = AssetsLoadProgress(phase: .names, pagesLoaded: pageCount, pageCount: pageCount) }
        let names = await customNames(of: records, characterID: characterID, client: client)

        await MainActor.run { context.progress = AssetsLoadProgress(phase: .locations, pagesLoaded: pageCount, pageCount: pageCount) }
        let known = await MainActor.run { context.knownLocations }
        let locations = await resolveLocations(of: records, known: known, client: client)
        await MainActor.run { context.knownLocations = locations }

        let typeIDs = Set(records.map(\.typeID))
        let typeNames = await MainActor.run { context.knownTypeNames }.filter { typeIDs.contains($0.key) }

        return ESIAssets(records: records, names: names, locations: locations, typeNames: typeNames)
    }

    /// All pages of one server-side snapshot, deduplicated by item id. Throws `PageRunChanged`
    /// when the pages come from different snapshots.
    nonisolated private static func pageRun(characterID: Int64, client: Client,
                                            context: FetchContext) async throws -> (records: [AssetRecord], pages: Int) {
        await MainActor.run { context.progress = AssetsLoadProgress(phase: .pages, pagesLoaded: 0, pageCount: nil) }

        /// One page, retried once. A `404` past page 1 means the list shrank.
        @Sendable func page(_ number: Int) async throws -> (records: Components.Schemas.CharactersCharacterIdAssetsGet, pages: Int, lastModified: String?) {
            func ask() async throws -> (records: Components.Schemas.CharactersCharacterIdAssetsGet, pages: Int, lastModified: String?) {
                do {
                    return try await client.assets(characterID: characterID, page: number)
                } catch let ESIError.http(status, _) where status == 404 && number > 1 {
                    throw PageRunChanged()
                }
            }
            do {
                return try await ask()
            } catch let error as PageRunChanged {
                throw error
            } catch {
                try Task.checkCancellation()
                return try await ask()
            }
        }

        let first = try await page(1)
        let pageCount = first.pages
        let stamp = first.lastModified
        await MainActor.run { context.progress = AssetsLoadProgress(phase: .pages, pagesLoaded: 1, pageCount: pageCount) }

        var pages: [Int: Components.Schemas.CharactersCharacterIdAssetsGet] = [1: first.records]
        if pageCount > 1 {
            let rest = try await ESIParallel.boundedMap(Array(2...pageCount), width: width) { number in
                let answer = try await page(number)
                // A page without `Last-Modified` is accepted.
                if answer.pages != pageCount { throw PageRunChanged() }
                if let stamp, let other = answer.lastModified, other != stamp { throw PageRunChanged() }
                return (number, answer.records)
            } progress: { done in
                await MainActor.run {
                    context.progress = AssetsLoadProgress(phase: .pages, pagesLoaded: 1 + done, pageCount: pageCount)
                }
            }
            for (number, records) in rest { pages[number] = records }
        }

        // An item can appear on two pages if the list shifted during paging.
        var seen: Set<Int64> = []
        let records = (1...pageCount)
            .flatMap { pages[$0] ?? [] }
            .map(AssetRecord.init)
            .filter { seen.insert($0.itemID).inserted }
        return (records, pageCount)
    }

    nonisolated private static func typeNames(of typeIDs: [Int64], client: Client) async -> [Int64: String] {
        await UniverseNameLookup.names(of: typeIDs, client: client)
            .compactMapValues { $0.category == .inventoryType ? $0.name : nil }
    }

    /// Custom names of assembled ships, containers and other items that hold items. Requested
    /// in chunks of 1000, the route's limit, each best effort.
    nonisolated private static func customNames(of records: [AssetRecord], characterID: Int64, client: Client) async -> [Int64: String] {
        let parents = Set(records.map(\.locationID))
        let catalog = try? TypeCatalog()
        var seen: Set<Int64> = []
        let candidates = records.filter { record in
            guard seen.insert(record.itemID).inserted else { return false }
            guard record.isSingleton else { return false }
            if parents.contains(record.itemID) { return true }
            guard let catalog else { return false }
            let typeID = TypeID(rawValue: UInt32(clamping: record.typeID))
            if catalog.categoryID(of: typeID) == .ship { return true }
            return catalog.groupID(of: typeID).map { AssetCategory.containerGroups.contains(Int64($0.rawValue)) } ?? false
        }.map(\.itemID)
        guard !candidates.isEmpty else { return [:] }

        let chunks = stride(from: 0, to: candidates.count, by: 1000).map {
            Array(candidates[$0..<min($0 + 1000, candidates.count)])
        }
        let answers = (try? await ESIParallel.boundedMap(chunks, width: width) { chunk in
            (try? await client.assetNames(characterID: characterID, itemIDs: chunk)) ?? []
        }) ?? []

        var names: [Int64: String] = [:]
        for answer in answers {
            for entry in answer where !entry.name.isEmpty && entry.name != "None" {
                names[entry.itemId] = entry.name
            }
        }
        return names
    }

    /// Resolves every root location. Known stations are reused; structures are requested every
    /// time.
    nonisolated private static func resolveLocations(of records: [AssetRecord],
                                                     known: [Int64: AssetLocationInfo],
                                                     client: Client) async -> [Int64: AssetLocationInfo] {
        let items = Set(records.map(\.itemID))
        var roots: [Int64: String] = [:]
        for record in records where !items.contains(record.locationID) && roots[record.locationID] == nil {
            roots[record.locationID] = record.locationType
        }
        return await LocationLookup.resolve(roots, known: known, client: client)
    }
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
