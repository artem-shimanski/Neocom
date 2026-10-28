import AssetsKit
import Foundation
import LiteRow
import Observation
import SDEKit

/// The character's `AssetIndex`, rebuilt whenever the sheet brings a new fetch, plus the sheet's
/// loading state. The index is built off the main actor, once per snapshot revision; the screens
/// share one model.
@Observable
@MainActor
final class AssetsModel {
    let sheet: any AssetsSource

    /// `nil` until the first build finishes or when assets were never fetched. The previous index
    /// stays while a newer build runs.
    private(set) var index: AssetIndex?
    /// Bumped each time `index` is replaced; views deriving state from the index key their task on it.
    private(set) var indexRevision = 0
    private(set) var isBuilding = false
    /// The SDE read failed; the index, if any, is the previous one.
    private(set) var buildError: (any Error)?

    var state: ESISnapshot<ESIAssets>.State { sheet.state }
    var progress: AssetsLoadProgress? { sheet.progress }
    var fetchedAt: Date? { sheet.fetchedAt }
    /// The snapshot revision; a view can `.task(id:)` on it and call `rebuildIfNeeded()`.
    var revision: Int { sheet.revision }

    /// The character's home station or structure; `nil` until the profile is loaded with location ids.
    var homeLocationID: Int64? {
        isCorporation ? nil : characterSheet?.profile?.homeLocation?.locationID
    }
    var isCorporation: Bool { sheet.corporationID != nil }
    var access: BusinessAccess { sheet.access }
    /// The station or structure the character is docked in; `nil` in space or when unknown.
    var dockedLocationID: Int64? { characterSheet?.profile?.location?.locationID }

    @ObservationIgnored private let database: SDEDatabase
    @ObservationIgnored private let characterSheet: CharacterSheet?
    /// The snapshot revision `index` was built from.
    @ObservationIgnored private var builtRevision: Int?
    /// The build in flight and its revision; callers of the same revision join it. The result of an
    /// older revision is dropped.
    @ObservationIgnored private var building: (revision: Int, task: Task<[Int64], Never>)?
    @ObservationIgnored private var buildsRunning = 0

    @ObservationIgnored let corporation: CorporationSheet?

    init(sheet: any AssetsSource, database: SDEDatabase, characterSheet: CharacterSheet? = nil,
         corporation: CorporationSheet? = nil) {
        self.sheet = sheet
        self.database = database
        self.characterSheet = characterSheet
        self.corporation = corporation
    }

    func ensureDivisionsFresh() async {
        await corporation?.ensureDivisionsFresh()
    }

    func refreshRoles() async {
        await corporation?.refresh()
    }

    /// The corporation's name of a hangar division.
    func divisionName(_ number: Int) -> String {
        corporation?.hangarName(number) ?? ESICorporationDivisions.hangarName(number, in: [:])
    }

    /// Brings the assets up to date if they are older than the TTL, then the index.
    func ensureFresh() async {
        // The cached value can be indexed while the network is still being asked.
        async let cached: Void = rebuildIfNeeded()
        await sheet.ensureFresh()
        await cached
        await rebuildIfNeeded()
    }

    /// Pull-to-refresh.
    func refresh() async {
        await sheet.refresh()
        await rebuildIfNeeded()
    }

    /// Builds the index if the snapshot changed. Concurrent callers of the same revision share one
    /// build; the index ends up built from the newest revision.
    ///
    /// Types unknown to the static data are named from ESI once; if any are found, the index is
    /// rebuilt with them.
    func rebuildIfNeeded() async {
        guard let value = sheet.value else { return }
        let revision = sheet.revision
        if let builtRevision, builtRevision >= revision { return }
        if let building, building.revision == revision {
            _ = await building.task.value
            return
        }

        let task = Task { [database] () -> [Int64] in
            buildsRunning += 1
            isBuilding = true
            defer {
                buildsRunning -= 1
                isBuilding = buildsRunning > 0
            }
            do {
                let (index, missing) = try await Self.build(value, database: database)
                // A build of a newer revision finished first: this one is out of date.
                if let builtRevision, builtRevision >= revision { return [] }
                self.index = index
                builtRevision = revision
                indexRevision += 1
                buildError = nil
                return missing
            } catch {
                if builtRevision.map({ $0 < revision }) ?? true { buildError = error }
                return []
            }
        }
        building = (revision, task)
        let missing = await task.value
        if building?.task == task { building = nil }

        if !missing.isEmpty, await sheet.resolveTypeNames(missing: Set(missing)) {
            await rebuildIfNeeded()
        }
    }

    // MARK: - Building

    /// The index, and the types of `value` the static data does not know and `value` has no
    /// name for either.
    private static func build(_ value: ESIAssets, database: SDEDatabase) async throws -> (AssetIndex, missing: [Int64]) {
        let typeIDs = Array(Set(value.records.map(\.typeID)))
        let systemIDs = Array(Set(value.locations.values.compactMap(\.solarSystemID)))

        // Query builders are main-actor isolated; the reads run on the database's connection.
        let typeQueries = stride(from: 0, to: typeIDs.count, by: chunk).map { start in
            AssetsBrowser.types(typeIDs[start..<min(start + chunk, typeIDs.count)].map { TypeID(rawValue: UInt32(clamping: $0)) })
        }
        let typeRows = try await database.database.read { reader in
            try typeQueries.flatMap { try reader.fetchAll($0) }
        }

        let groupIDs = Array(Set(typeRows.map(\.groupID)))
        let groupQueries = stride(from: 0, to: groupIDs.count, by: chunk).map { start in
            AssetsBrowser.groups(Array(groupIDs[start..<min(start + chunk, groupIDs.count)]))
        }
        let systemQueries = stride(from: 0, to: systemIDs.count, by: chunk).map { start in
            CharacterBrowser.solarSystems(systemIDs[start..<min(start + chunk, systemIDs.count)].map { SolarSystemID(rawValue: UInt32(clamping: $0)) })
        }
        let (groupRows, systemRows) = try await database.database.read { reader in
            (try groupQueries.flatMap { try reader.fetchAll($0) },
             try systemQueries.flatMap { try reader.fetchAll($0) })
        }

        var groups: [GroupID: GroupHeader] = [:]
        for row in groupRows { groups[row.id] = row }
        var types: [Int64: AssetTypeInfo] = [:]
        for row in typeRows {
            let group = groups[row.groupID]
            types[Int64(row.id.rawValue)] = AssetTypeInfo(
                typeID: Int64(row.id.rawValue),
                name: row.name,
                groupID: Int64(row.groupID.rawValue),
                groupName: group?.name ?? "",
                categoryID: group.map { Int64($0.categoryID.rawValue) } ?? -1,
                categoryName: group?.categoryName ?? "Other",
                volume: row.volume,
                capacity: row.capacity)
        }
        // Unpublished types, under the name ESI gave them and in no known group.
        var missing: [Int64] = []
        for typeID in typeIDs where types[typeID] == nil {
            if let name = value.typeNames[typeID] {
                types[typeID] = AssetTypeInfo(typeID: typeID, name: name, groupID: -1, groupName: "",
                                              categoryID: -1, categoryName: "Other")
            } else {
                missing.append(typeID)
            }
        }
        var systems: [Int64: AssetSolarSystem] = [:]
        for row in systemRows {
            systems[Int64(row.id.rawValue)] = AssetSolarSystem(name: row.name,
                                                               securityStatus: row.securityStatus,
                                                               regionName: row.regionName)
        }
        return (await index(value, types: types, systems: systems), missing)
    }

    /// Ids per `IN (…)`, below SQLite's bound-parameter limit.
    private static let chunk = 500

    @concurrent
    private static func index(_ value: ESIAssets,
                                types: [Int64: AssetTypeInfo],
                                systems: [Int64: AssetSolarSystem]) async -> AssetIndex {
        AssetIndex(records: value.records,
                   customNames: value.names,
                   locations: value.locations,
                   systems: systems,
                   types: AssetTypeInfo.addingSlots(to: types))
    }
}

nonisolated extension ESIFitting {
    /// An assembled hangar ship as a game fitting for `FitDocument(_:catalog:warnings:)`. The id is
    /// the ship's item id, not a saved fitting's id.
    init(_ fitting: AssetFitting) {
        self.init(id: fitting.shipItemID,
                  name: fitting.name,
                  fittingDescription: "",
                  shipTypeID: fitting.shipTypeID,
                  items: fitting.items.map { Item(typeID: $0.typeID, flag: $0.flag, quantity: $0.quantity) })
    }
}
