import LiteRow
import SDEKit

/// Race and bloodline in one row; ESI's `bloodline_id` is enough to name both.
@Projection
struct CharacterOriginRow: Sendable {
    var bloodlineName: String
    var raceName: String
}

/// A named faction, for militia membership.
@Projection
struct FactionNameRow: Sendable {
    var name: String
}

/// A solar system as the location rows show it.
@Projection
struct SolarSystemRow: Sendable, Identifiable {
    var id: SolarSystemID
    var name: String
    var securityStatus: Double
    var regionName: String
}

/// Queries behind the Character Sheet.
///
/// Built outside the views because `@LiteQuery` treats the query as the identity of a fetch, so it
/// has to be an argument of the view.
enum CharacterBrowser {

    static func origin(ofBloodline bloodline: BloodlineID) -> SQLQuery<CharacterOriginRow> {
        let withName = BloodlineInfo.all()
            .join(NameRow.self) { row, name in row.nameID == name.id }
        let withRace = withName
            .join(RaceInfo.self) { row, _, race in row.raceID == race.id }
        let withRaceName = withRace
            .join(NameRow.self) { _, _, race, raceName in race.nameID == raceName.id }
        return withRaceName
            .filter { row, _, _, _ in row.id == bloodline }
            .select { _, name, _, raceName in
                CharacterOriginRow.projection(bloodlineName: name.text, raceName: raceName.text)
            }
            .limit(1)
            .query()
    }

    static func name(ofFaction faction: FactionID) -> SQLQuery<FactionNameRow> {
        let withName = FactionInfo.all()
            .join(NameRow.self) { row, name in row.nameID == name.id }
        return withName
            .filter { row, _ in row.id == faction }
            .select { _, name in
                FactionNameRow.projection(name: name.text)
            }
            .limit(1)
            .query()
    }

    /// Named systems for a set of ids.
    static func solarSystems(_ systems: [SolarSystemID]) -> SQLQuery<SolarSystemRow> {
        let withName = SolarSystemInfo.all()
            .join(NameRow.self) { row, name in row.nameID == name.id }
        let withRegion = withName
            .join(RegionInfo.self) { row, _, region in row.regionID == region.id }
        let withRegionName = withRegion
            .join(NameRow.self) { _, _, region, regionName in region.nameID == regionName.id }
        return withRegionName
            .filter { row, _, _, _ in row.id.in(systems) }
            .select { row, name, _, regionName in
                SolarSystemRow.projection(
                    id: row.id,
                    name: name.text,
                    securityStatus: row.securityStatus,
                    regionName: regionName.text
                )
            }
            .query()
    }
}
