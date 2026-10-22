import LiteRow
import SDEKit

// Queries behind the zKillboard subject picker: all regions, including wormhole space and the
// abyss, and factions.

/// A constellation with its region.
@Projection
struct KillboardConstellationRow: Sendable, Identifiable {
    var id: ConstellationID
    var name: String
    var regionName: String
}

/// A faction.
@Projection
struct KillboardFactionRow: Sendable, Identifiable {
    var id: FactionID
    var name: String
}

enum KillboardBrowser {
    /// Every region, alphabetically; filtered by name in the picker.
    static func regions() -> SQLQuery<MarketRegionRow> {
        RegionInfo.all()
            .join(NameRow.self) { row, name in row.nameID == name.id }
            .select { row, name in MarketRegionRow.projection(id: row.id, name: name.text) }
            .order(by: { _, name in name.ordinal })
            .query()
    }

    /// Every faction, alphabetically; filtered by name in the picker.
    static func factions() -> SQLQuery<KillboardFactionRow> {
        FactionInfo.all()
            .join(NameRow.self) { row, name in row.nameID == name.id }
            .select { row, name in KillboardFactionRow.projection(id: row.id, name: name.text) }
            .order(by: { _, name in name.ordinal })
            .query()
    }

    /// Systems whose name matches, by relevance, each with its region and security.
    static func searchSystems(_ pattern: FTS5Pattern, limit: Int = 50) -> SQLQuery<MarketSystemRow> {
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
            .select { _, system, name, _, regionName in
                MarketSystemRow.projection(id: system.id, name: name.text, securityStatus: system.securityStatus,
                                           regionID: system.regionID, regionName: regionName.text)
            }
            .order(by: { fts, _, _, _, _ in fts.rank })
            .limit(limit)
            .query()
    }

    /// Constellations whose name matches, by relevance, each with its region.
    static func searchConstellations(_ pattern: FTS5Pattern, limit: Int = 50) -> SQLQuery<KillboardConstellationRow> {
        let withConstellation = NameSearchIndex.all()
            .join(ConstellationInfo.self) { fts, row in fts.rowID(as: NameID.self) == row.nameID }
        let withName = withConstellation
            .join(NameRow.self) { _, row, name in row.nameID == name.id }
        let withRegion = withName
            .join(RegionInfo.self) { _, row, _, region in row.regionID == region.id }
        let withRegionName = withRegion
            .join(NameRow.self) { _, _, _, region, regionName in region.nameID == regionName.id }
        return withRegionName
            .filter { fts, _, _, _, _ in fts.match(pattern) && fts.ranked(by: SDEDatabase.searchRanking) }
            .select { _, row, name, _, regionName in
                KillboardConstellationRow.projection(id: row.id, name: name.text, regionName: regionName.text)
            }
            .order(by: { fts, _, _, _, _ in fts.rank })
            .limit(limit)
            .query()
    }
}
