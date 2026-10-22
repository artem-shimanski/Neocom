import LiteRow
import SDEKit

// Queries behind the Market section: regions and the systems of orders.
//
// The export has no station or stargate rows; those come from `MarketSheet.resolveStationNames(_:)`
// and `MarketSheet.resolveJumps(from:to:)`.

/// A region as the region picker shows it.
@Projection
struct MarketRegionRow: Sendable, Identifiable {
    var id: RegionID
    var name: String
}

/// A solar system with its region: the trade hubs, a search hit, an order's system.
@Projection
struct MarketSystemRow: Sendable, Identifiable {
    var id: SolarSystemID
    var name: String
    var securityStatus: Double
    var regionID: RegionID
    var regionName: String
}

enum MarketBrowser {
    /// K-space regions start at this id; wormhole space and the abyss start at 11000000 and have no market.
    static let firstKSpaceRegion: RegionID = 10_000_000
    static let firstNonKSpaceRegion: RegionID = 11_000_000

    /// Jove regions no gate leads to: UUA-F4, J7HZ-F, A821-A.
    static let unreachableRegions: [RegionID] = [10_000_004, 10_000_017, 10_000_019]

    /// Every region the market can be read in (k-space without the unreachable ones, Pochven
    /// included), alphabetically.
    static func regions() -> SQLQuery<MarketRegionRow> {
        RegionInfo.all()
            .join(NameRow.self) { row, name in row.nameID == name.id }
            .filter { row, _ in
                row.id >= firstKSpaceRegion && row.id < firstNonKSpaceRegion && row.id.notIn(unreachableRegions)
            }
            .select { row, name in MarketRegionRow.projection(id: row.id, name: name.text) }
            .order(by: { _, name in name.ordinal })
            .query()
    }

    /// Regions for a set of ids, in no particular order.
    static func regions(_ regions: [RegionID]) -> SQLQuery<MarketRegionRow> {
        RegionInfo.all()
            .join(NameRow.self) { row, name in row.nameID == name.id }
            .filter { row, _ in row.id.in(regions) }
            .select { row, name in MarketRegionRow.projection(id: row.id, name: name.text) }
            .query()
    }

    /// Market regions whose name matches, by relevance.
    static func searchRegions(_ pattern: FTS5Pattern, limit: Int = 20) -> SQLQuery<MarketRegionRow> {
        let withRegion = NameSearchIndex.all()
            .join(RegionInfo.self) { fts, region in fts.rowID(as: NameID.self) == region.nameID }
        let withName = withRegion
            .join(NameRow.self) { _, region, name in region.nameID == name.id }
        return withName
            .filter { fts, _, _ in fts.match(pattern) && fts.ranked(by: SDEDatabase.searchRanking) }
            .filter { _, region, _ in
                region.id >= firstKSpaceRegion && region.id < firstNonKSpaceRegion
                    && region.id.notIn(unreachableRegions)
            }
            .select { _, region, name in MarketRegionRow.projection(id: region.id, name: name.text) }
            .order(by: { fts, _, _ in fts.rank })
            .limit(limit)
            .query()
    }

    /// Systems of market regions whose name matches, by relevance, each with its region.
    static func searchSystems(_ pattern: FTS5Pattern, limit: Int = 20) -> SQLQuery<MarketSystemRow> {
        let withSystem = NameSearchIndex.all()
            .join(SolarSystemInfo.self) { fts, system in fts.rowID(as: NameID.self) == system.nameID }
        let withName = withSystem
            .join(NameRow.self) { _, system, name in system.nameID == name.id }
        let withRegion = withName
            .join(RegionInfo.self) { _, system, _, region in system.regionID == region.id }
        let withRegionName = withRegion
            .join(NameRow.self) { _, _, _, region, regionName in region.nameID == regionName.id }
        return withRegionName
            .filter { fts, _, _, _, _ in fts.match(pattern) && fts.ranked(by: SDEDatabase.searchRanking) }
            .filter { _, system, _, _, _ in
                system.regionID >= firstKSpaceRegion && system.regionID < firstNonKSpaceRegion
                    && system.regionID.notIn(unreachableRegions)
            }
            .select { _, system, name, _, regionName in
                MarketSystemRow.projection(id: system.id, name: name.text, securityStatus: system.securityStatus,
                                           regionID: system.regionID, regionName: regionName.text)
            }
            .order(by: { fts, _, _, _, _ in fts.rank })
            .limit(limit)
            .query()
    }

    /// Named systems for a set of ids. The caller chunks large sets: SQLite caps bound parameters.
    static func systems(_ systems: [SolarSystemID]) -> SQLQuery<MarketSystemRow> {
        let withName = SolarSystemInfo.all()
            .join(NameRow.self) { row, name in row.nameID == name.id }
        let withRegion = withName
            .join(RegionInfo.self) { row, _, region in row.regionID == region.id }
        let withRegionName = withRegion
            .join(NameRow.self) { _, _, region, regionName in region.nameID == regionName.id }
        return withRegionName
            .filter { row, _, _, _ in row.id.in(systems) }
            .select { row, name, _, regionName in
                MarketSystemRow.projection(id: row.id, name: name.text, securityStatus: row.securityStatus,
                                           regionID: row.regionID, regionName: regionName.text)
            }
            .query()
    }
}
