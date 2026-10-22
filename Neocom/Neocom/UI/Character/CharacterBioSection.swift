import LiteRow
import LiteRowUI
import SDEKit
import SwiftUI

/// Where the character comes from: born, standing, race, bloodline and militia.
/// Everything here is public data from `/characters/{id}`; the SDE turns the three ids in it into
/// names.
struct CharacterBioSection: View {
    let profile: CharacterProfile

    var body: some View {
        HUDListSection("Bio") {
            HUDReadoutRow("Date of Birth") {
                Text(profile.birthday, format: .dateTime.year().month(.twoDigits).day(.twoDigits))
            }

            if let securityStatus = profile.securityStatus {
                HUDReadoutRow("Security") {
                    Text(SecurityStatus.string(securityStatus, fractionLength: 2, signed: true))
                        .foregroundStyle(SecurityStatus.color(securityStatus))
                }
            }

            // Both rows come from one query, which needs an id in `init`, hence a view of their
            // own.
            if let bloodlineID = profile.bloodlineID {
                CharacterOriginRows(bloodlineID: bloodlineID)
            }

            if let factionID = profile.factionID {
                CharacterFactionRow(factionID: factionID)
            }
        }
    }
}

/// Race and bloodline. The bloodline knows its race, so one id names both.
private struct CharacterOriginRows: View {
    @LiteQuery private var origin: CharacterOriginRow?

    init(bloodlineID: BloodlineID) {
        _origin = LiteQuery(CharacterBrowser.origin(ofBloodline: bloodlineID))
    }

    var body: some View {
        if let origin {
            HUDReadoutRow("Race", value: origin.raceName)
            HUDReadoutRow("Bloodline", value: origin.bloodlineName)
        }
    }
}

/// Militia membership, for the characters who have one.
private struct CharacterFactionRow: View {
    @LiteQuery private var faction: FactionNameRow?

    init(factionID: FactionID) {
        _faction = LiteQuery(CharacterBrowser.name(ofFaction: factionID))
    }

    var body: some View {
        if let faction {
            HUDReadoutRow("Faction", value: faction.name)
        }
    }
}
