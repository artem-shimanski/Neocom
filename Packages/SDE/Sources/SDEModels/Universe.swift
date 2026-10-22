//
//  Universe.swift
//  SDE
//
//  Created by Artem Shimanski on 04.09.2026.
//

import LiteRow

// The map stores hierarchy and names; no coordinates, luminosity, radii, nebulae or lists of
// planets, stars and gates, and no planets, moons or belts at all (284 MB of JSONL). The exception
// is `securityStatus`.

@Table("regions")
public struct RegionInfo: Identifiable {
    @PrimaryKey public var id: RegionID
    public var nameID: NameID
    public var descriptionID: DescriptionID? = nil
    public var factionID: FactionID? = nil
    public var wormholeClassID: Int? = nil
}

@Table("constellations")
public struct ConstellationInfo: Identifiable {
    @PrimaryKey public var id: ConstellationID
    @Index public var regionID: RegionID
    public var nameID: NameID
    public var factionID: FactionID? = nil
    public var wormholeClassID: Int? = nil
}

@Table("solarSystems")
public struct SolarSystemInfo: Identifiable {
    @PrimaryKey public var id: SolarSystemID
    @Index public var constellationID: ConstellationID
    /// Duplicates the path through the constellation: "all systems of a region" is a frequent query
    /// without an extra join.
    @Index public var regionID: RegionID
    public var nameID: NameID
    public var securityStatus: Double = 0
    public var securityClass: String? = nil
    public var factionID: FactionID? = nil
    public var wormholeClassID: Int? = nil
}

// MARK: - Factions

@Table("factions")
public struct FactionInfo: Identifiable {
    @PrimaryKey public var id: FactionID
    public var nameID: NameID
    public var descriptionID: DescriptionID? = nil
    public var shortDescriptionID: DescriptionID? = nil
    public var iconID: IconID? = nil
    public var corporationID: CorporationID? = nil
    public var militiaCorporationID: CorporationID? = nil
    public var solarSystemID: SolarSystemID
    public var flatLogo: String? = nil
    public var flatLogoWithName: String? = nil
    public var sizeFactor: Int = 0
    public var uniqueName: Bool = false
}

@Table("factionMemberRaces")
public struct FactionMemberRace {
    @PrimaryKey public var factionID: FactionID
    @PrimaryKey public var raceID: RaceID
}
