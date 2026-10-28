import AssetsKit
import DogmaKit
import ESIKit
import Foundation
import Observation

/// The two asset routes of one owner: a character's or a corporation's.
nonisolated struct AssetsRoutes: Sendable {
    /// One page of records, with the page count and `Last-Modified`.
    var page: @Sendable (Int) async throws -> (records: [AssetRecord], pages: Int, lastModified: String?)
    /// Custom names of at most 1000 items.
    var names: @Sendable ([Int64]) async throws -> [(itemID: Int64, name: String)]
}

/// The assets fetch shared by `AssetsSheet` and `CorporationAssetsSheet`: all pages, then
/// custom names, then root locations.
nonisolated enum AssetsFetch {
    /// State shared between an owner and its fetches: progress, and names resolved by earlier
    /// fetches.
    @Observable
    @MainActor
    final class Context {
        var progress: AssetsLoadProgress?
        @ObservationIgnored var knownLocations: [Int64: AssetLocationInfo] = [:]
        /// Type names found earlier; kept across fetches.
        @ObservationIgnored var knownTypeNames: [Int64: String] = [:]
        /// Type ids already requested by `resolveTypeNames(missing:in:client:)`, each once.
        @ObservationIgnored private var askedTypeIDs: Set<Int64> = []

        /// Seeds the known names from a cached value.
        func seed(from value: ESIAssets?) {
            knownLocations = value?.locations ?? [:]
            knownTypeNames = value?.typeNames ?? [:]
        }

        /// Resolves through ESI the names of types missing from the SDE and amends the
        /// snapshot's value with them. Best effort, each id requested once. Returns whether any
        /// name was added.
        func resolveTypeNames(missing: Set<Int64>, in snapshot: ESISnapshot<ESIAssets>, client: Client) async -> Bool {
            guard let known = snapshot.value?.typeNames else { return false }
            let ask = missing.subtracting(askedTypeIDs).subtracting(known.keys)
            guard !ask.isEmpty else { return false }
            askedTypeIDs.formUnion(ask)

            let found = await AssetsFetch.typeNames(of: ask.sorted(), client: client)
            guard !found.isEmpty, var value = snapshot.value else { return false }
            knownTypeNames.merge(found) { _, new in new }
            value.typeNames.merge(found) { _, new in new }
            snapshot.amend(value)
            return true
        }
    }

    /// The pages belong to different server-side snapshots: `Last-Modified` or the page count
    /// changed, or a later page answered `404`.
    private struct PageRunChanged: Error {}

    private static let width = ESIParallel.width

    /// Fetches all pages, then custom names, then locations.
    ///
    /// A page that fails twice fails the whole fetch; names and locations are best effort.
    static func fetch(routes: AssetsRoutes, client: Client, context: Context) async throws -> ESIAssets {
        // ESI serves all pages from one cache snapshot; a run that spans a cache renewal mixes
        // two snapshots and is restarted once.
        var run: (records: [AssetRecord], pages: Int)?
        for attempt in 1...2 where run == nil {
            do {
                run = try await pageRun(routes: routes, context: context)
            } catch is PageRunChanged {
                if attempt == 2 { throw AssetsListChangedError() }
            }
        }
        guard let (records, pageCount) = run else { throw AssetsListChangedError() }

        await MainActor.run { context.progress = AssetsLoadProgress(phase: .names, pagesLoaded: pageCount, pageCount: pageCount) }
        let names = await customNames(of: records, routes: routes)

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
    private static func pageRun(routes: AssetsRoutes, context: Context) async throws -> (records: [AssetRecord], pages: Int) {
        await MainActor.run { context.progress = AssetsLoadProgress(phase: .pages, pagesLoaded: 0, pageCount: nil) }

        /// One page, retried once. A `404` past page 1 means the list shrank.
        @Sendable func page(_ number: Int) async throws -> (records: [AssetRecord], pages: Int, lastModified: String?) {
            func ask() async throws -> (records: [AssetRecord], pages: Int, lastModified: String?) {
                do {
                    return try await routes.page(number)
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

        var pages: [Int: [AssetRecord]] = [1: first.records]
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
            .filter { seen.insert($0.itemID).inserted }
        return (records, pageCount)
    }

    static func typeNames(of typeIDs: [Int64], client: Client) async -> [Int64: String] {
        await UniverseNameLookup.names(of: typeIDs, client: client)
            .compactMapValues { $0.category == .inventoryType ? $0.name : nil }
    }

    /// Custom names of assembled ships, containers and other items that hold items. Requested
    /// in chunks of 1000, the route's limit, each best effort. Offices are never asked: one
    /// can fail its whole chunk.
    private static func customNames(of records: [AssetRecord], routes: AssetsRoutes) async -> [Int64: String] {
        let parents = Set(records.map(\.locationID))
        let catalog = try? TypeCatalog()
        var seen: Set<Int64> = []
        let candidates = records.filter { record in
            guard seen.insert(record.itemID).inserted else { return false }
            guard record.isSingleton, !record.isOffice else { return false }
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
            (try? await routes.names(chunk)) ?? []
        }) ?? []

        var names: [Int64: String] = [:]
        for answer in answers {
            for entry in answer where !entry.name.isEmpty && entry.name != "None" {
                names[entry.itemID] = entry.name
            }
        }
        return names
    }

    /// Resolves every root location. Known stations are reused; structures are requested every
    /// time.
    private static func resolveLocations(of records: [AssetRecord],
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
