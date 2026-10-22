import AssetsKit
import ESIKit
import Foundation

// Id-to-name resolution and bounded parallel requests shared by the per-character sheets. Only
// non-character routes are called here: `/universe/names`, `/universe/stations`,
// `/universe/structures`.

/// A name from `/universe/names` and its category.
nonisolated struct ESIEntityName: Codable, Sendable, Hashable {
    enum Category: String, Codable, Sendable, Hashable {
        case character
        case corporation
        case alliance
        case faction
        case inventoryType = "inventory_type"
        case station
        case solarSystem = "solar_system"
        case constellation
        case region
        case other
    }

    var name: String
    var category: Category
}

extension Error {
    /// ESI answered `403`: the token lacks the route's scope, or, for a structure, the
    /// character has no docking access.
    nonisolated var isESIForbidden: Bool {
        guard case let .http(status, _)? = self as? ESIError else { return false }
        return status == 403
    }
}

nonisolated enum ESIParallel {
    /// Maximum concurrent requests; stays under ESI's per-route rate limit.
    static let width = 5

    /// Maps `body` over `items` with at most `width` running at once; results are in completion
    /// order. The first error cancels the rest and is rethrown.
    static func boundedMap<Item: Sendable, Answer: Sendable>(
        _ items: [Item],
        width: Int = ESIParallel.width,
        _ body: @escaping @Sendable (Item) async throws -> Answer,
        progress: (@Sendable (Int) async -> Void)? = nil
    ) async throws -> [Answer] {
        try await withThrowingTaskGroup(of: Answer.self) { group in
            var next = 0
            for _ in 0..<min(width, items.count) {
                let item = items[next]
                group.addTask { try await body(item) }
                next += 1
            }
            var answers: [Answer] = []
            answers.reserveCapacity(items.count)
            while let answer = try await group.next() {
                answers.append(answer)
                await progress?(answers.count)
                if next < items.count {
                    let item = items[next]
                    group.addTask { try await body(item) }
                    next += 1
                }
            }
            return answers
        }
    }

    /// All pages of a paged route, records in page order. Page 1 provides the page count; the
    /// rest are fetched `width` at a time. A `404` on a later page counts as empty (the list
    /// shrank); any other failure fails the whole run. Records may repeat if the list shifts
    /// during paging; callers deduplicate by id.
    static func allPages<Record: Sendable>(
        _ page: @escaping @Sendable (Int) async throws -> (records: [Record], pages: Int)
    ) async throws -> [Record] {
        let first = try await page(1)
        guard first.pages > 1 else { return first.records }
        let rest = try await boundedMap(Array(2...first.pages)) { number -> (Int, [Record]) in
            do {
                return (number, try await page(number).records)
            } catch let ESIError.http(status, _) where status == 404 {
                return (number, [])
            }
        }
        let byNumber = Dictionary(rest, uniquingKeysWith: { first, _ in first })
        return first.records + (2...first.pages).flatMap { byNumber[$0] ?? [] }
    }
}

/// Names of ids from the public `/universe/names`, any category.
nonisolated enum UniverseNameLookup {
    /// Requests in chunks of 1000, the route's limit. ESI rejects a whole chunk with `404` for
    /// one unknown id, so a rejected chunk is bisected down to that id; other failures leave
    /// the chunk unnamed. Ids of 0 and below are never sent.
    static func names(of ids: some Sequence<Int64>, client: Client) async -> [Int64: ESIEntityName] {
        await lookup(ids, client: client).names
    }

    /// The names, and the ids that are settled: answered by ESI or rejected individually as
    /// unknown. Ids whose request failed otherwise (offline, timeout, 5xx) are not settled.
    static func lookup(_ ids: some Sequence<Int64>,
                       client: Client) async -> (names: [Int64: ESIEntityName], settled: Set<Int64>) {
        let unique = Array(Set(ids.filter { $0 > 0 })).sorted()
        guard !unique.isEmpty else { return ([:], []) }

        typealias Answer = (names: [Int64: ESIEntityName], settled: Set<Int64>)
        @Sendable func ask(_ ids: [Int64]) async -> Answer {
            do {
                return (try await client.entityNames(ids: ids), Set(ids))
            } catch let ESIError.http(status, _) where status == 404 {
                guard ids.count > 1 else { return ([:], Set(ids)) }
                let half = ids.count / 2
                let left = await ask(Array(ids[..<half]))
                let right = await ask(Array(ids[half...]))
                return (left.names.merging(right.names) { _, new in new }, left.settled.union(right.settled))
            } catch {
                return ([:], [])
            }
        }
        let chunks = stride(from: 0, to: unique.count, by: 1000).map {
            Array(unique[$0..<min($0 + 1000, unique.count)])
        }
        let answers = (try? await ESIParallel.boundedMap(chunks) { await ask($0) }) ?? []
        return answers.reduce(into: ([:], [])) { result, answer in
            result.names.merge(answer.names) { _, new in new }
            result.settled.formUnion(answer.settled)
        }
    }
}

/// Location names: NPC stations from `/universe/stations/{id}`, Upwell structures from
/// `/universe/structures/{id}`.
nonisolated enum LocationLookup {
    /// Resolves every id in `ids` (id → ESI's `location_type`, or `""` to classify by id range).
    ///
    /// Stations in `known` are reused, since they never change. Structures are requested again
    /// unless in `reuseStructures`: they get renamed and access changes. A structure answering
    /// `403` is `structureNoAccess`; any other failure keeps the `known` value.
    static func resolve(_ ids: [Int64: String],
                        known: [Int64: AssetLocationInfo],
                        reuseStructures: Set<Int64> = [],
                        client: Client) async -> [Int64: AssetLocationInfo] {
        var result: [Int64: AssetLocationInfo] = [:]
        var toAsk: [(Int64, AssetIDRange)] = []
        for (id, locationType) in ids {
            switch AssetIDRange.classify(id, locationType: locationType) {
            case .station:
                if let station = known[id], station.kind == .station, station.name != nil {
                    result[id] = station
                } else {
                    toAsk.append((id, .station))
                }
            case .structure:
                if reuseStructures.contains(id), let structure = known[id], structure.kind != .unknown {
                    result[id] = structure
                } else {
                    toAsk.append((id, .structure))
                }
            case .solarSystem:
                result[id] = AssetLocationInfo(id: id, kind: .solarSystem, solarSystemID: id)
            case .other:
                result[id] = AssetLocationInfo(id: id, kind: .unknown)
            }
        }

        let asked = (try? await ESIParallel.boundedMap(toAsk) { id, range in
            await resolve(id, as: range, previous: known[id], client: client)
        }) ?? []
        for location in asked { result[location.id] = location }
        return result
    }

    private static func resolve(_ id: Int64, as range: AssetIDRange,
                                previous: AssetLocationInfo?, client: Client) async -> AssetLocationInfo {
        do {
            if range == .station {
                let station = try await client.station(id: id)
                return AssetLocationInfo(id: id, kind: .station, name: station.name,
                                         solarSystemID: station.systemId, typeID: station.typeId)
            } else {
                let structure = try await client.structure(id: id)
                return AssetLocationInfo(id: id, kind: .structure, name: structure.name,
                                         solarSystemID: structure.solarSystemId, typeID: structure.typeId)
            }
        } catch let error where error.isESIForbidden && range == .structure {
            return AssetLocationInfo(id: id, kind: .structureNoAccess)
        } catch {
            return previous ?? AssetLocationInfo(id: id, kind: range == .station ? .station : .unknown)
        }
    }
}

/// Locations and names already resolved by a sheet, so refreshes request only new ids. Seeded
/// from the cached value.
///
/// Structures are requested once per sheet lifetime, then reused.
@MainActor
final class LookupMemory {
    private(set) var locations: [Int64: AssetLocationInfo]
    private(set) var names: [Int64: ESIEntityName]
    private var askedStructures: Set<Int64> = []
    /// Ids `/universe/names` has settled, named or rejected as unknown; not requested again.
    private var askedNames: Set<Int64> = []

    init(locations: [Int64: AssetLocationInfo] = [:], names: [Int64: ESIEntityName] = [:]) {
        self.locations = locations
        self.names = names
    }

    /// Adds entries from a cached value, keeping existing ones.
    func seed(locations: [Int64: AssetLocationInfo] = [:], names: [Int64: ESIEntityName] = [:]) {
        self.locations.merge(locations) { current, _ in current }
        self.names.merge(names) { current, _ in current }
    }

    /// Resolves the locations of `ids`, from memory where allowed and from ESI otherwise.
    nonisolated static func locations(_ ids: some Sequence<Int64>, memory: LookupMemory,
                                      client: Client) async -> [Int64: AssetLocationInfo] {
        let wanted = Dictionary(ids.filter { $0 > 0 }.map { ($0, "") }, uniquingKeysWith: { first, _ in first })
        guard !wanted.isEmpty else { return [:] }
        let (known, reuse) = await MainActor.run { (memory.locations, memory.askedStructures) }
        let found = await LocationLookup.resolve(wanted, known: known, reuseStructures: reuse, client: client)
        await MainActor.run {
            memory.locations.merge(found) { _, new in new }
            memory.askedStructures.formUnion(found.values.filter { $0.kind != .station && $0.kind != .solarSystem }.map(\.id))
        }
        return found
    }

    /// Resolves the names of `ids`, from memory where known and from `/universe/names`
    /// otherwise. Unknown ids are omitted.
    nonisolated static func names(_ ids: some Sequence<Int64>, memory: LookupMemory,
                                  client: Client) async -> [Int64: ESIEntityName] {
        let wanted = Set(ids.filter { $0 > 0 })
        guard !wanted.isEmpty else { return [:] }
        let (known, asked) = await MainActor.run { (memory.names, memory.askedNames) }
        let missing = wanted.subtracting(known.keys).subtracting(asked)
        let (found, settled) = await UniverseNameLookup.lookup(missing, client: client)
        await MainActor.run {
            memory.askedNames.formUnion(settled)
            memory.names.merge(found) { _, new in new }
        }
        return known.filter { wanted.contains($0.key) }.merging(found) { _, new in new }
    }
}
