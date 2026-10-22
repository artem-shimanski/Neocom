import LiteRow
import LiteRowUI
import SDEKit
import SwiftUI

/// Where the character respawns, when they last jumped, and what is waiting in every jump clone
/// they own.
///
/// One section for the home station and the jump date, then a section per clone. Every system named
/// here comes out of a single query rather than one per clone.
struct CharacterClonesSection: View {
    let homeLocation: CharacterProfile.Location?
    let lastCloneJumpDate: Date?
    let clones: [CharacterProfile.JumpClone]

    @LiteQuery private var systems: [SolarSystemRow]
    @LiteQuery private var names: [TypeNameRow]

    init(homeLocation: CharacterProfile.Location?,
         lastCloneJumpDate: Date?,
         clones: [CharacterProfile.JumpClone]) {
        self.homeLocation = homeLocation
        self.lastCloneJumpDate = lastCloneJumpDate
        self.clones = clones

        let ids = ([homeLocation] + clones.map { $0.location }).compactMap { $0?.solarSystemID }
        _systems = LiteQuery(CharacterBrowser.solarSystems(Array(Set(ids))))
        _names = LiteQuery(SDEBrowser.typeNames(of: Array(Set(clones.flatMap { $0.implants }))))
    }

    var body: some View {
        if homeLocation != nil || lastCloneJumpDate != nil || !clones.isEmpty {
            HUDListSection("Clones") {
                if let homeLocation {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Home Station")
                            .font(.hudMicro)
                            .tracking(2)
                            .textCase(.uppercase)
                            .foregroundStyle(Color.hudInkMuted)
                        LocationLabel(location: homeLocation, system: system(of: homeLocation))
                    }
                    .hudRow(HUDRowStyle(verticalPadding: 12))
                }

                if let lastCloneJumpDate {
                    HUDReadoutRow("Last Clone Jump") {
                        Text(lastCloneJumpDate, format: .dateTime.year().month(.twoDigits).day(.twoDigits).hour().minute())
                    }
                }
            }

            ForEach(clones) { clone in
                cloneSection(clone)
            }
        }
    }

    private func cloneSection(_ clone: CharacterProfile.JumpClone) -> some View {
        HUDListSection {
            LocationLabel(location: clone.location, system: system(of: clone.location))
                .hudRow(HUDRowStyle(verticalPadding: 12))
            if !clone.implants.isEmpty {
                ForEach(clone.implants, id: \.self) { implant in
                    ImplantRow(implant: implant, name: names.first { $0.id == implant }?.name)
                }
            }
        } header: {
            // The name the player gave the clone, if any; not the place, which is the row below.
            HUDSectionHeader(Text(clone.name ?? String(localized: "Jump Clone"))) {
                Text(clone.implants.isEmpty ? "No Implants" : "\(clone.implants.count) Implants")
            }
        }
    }

    private func system(of location: CharacterProfile.Location) -> SolarSystemRow? {
        location.solarSystemID.flatMap { id in systems.first { $0.id == id } }
    }
}
