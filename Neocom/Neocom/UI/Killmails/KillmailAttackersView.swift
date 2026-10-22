import KillmailKit
import LiteRowUI
import SDEKit
import SwiftUI

/// Everyone on a killmail, most damage first: who they are and fly for, their security, ship
/// and weapon, their share of the damage, and the final blow and top damage marked.
struct KillmailAttackersView: View {
    let sheet: KillmailsSheet
    let report: ESIKillmail

    var body: some View {
        let killmail = report.killmail
        let naming = KillmailNaming(names: report.names, sheet: sheet)
        let summary = killmail.attackerSummary
        let ranked = killmail.rankedAttackers
        KillmailStaticsReader(systemIDs: [killmail.solarSystemID], typeIDs: killmail.reportTypeIDs) { statics in
            let shipName = statics.typeName(killmail.victim.shipTypeID)
            HUDList {
                Section {
                    HUDPanel {
                        HUDStatStrip(items: [
                            .init(id: 0, label: Text("Involved"), value: Text(verbatim: "\(summary.involved)")),
                            .init(id: 1, label: Text("Pilots"), value: Text(verbatim: "\(summary.pilots)")),
                            .init(id: 2, label: Text(verbatim: "NPC"), value: Text(verbatim: "\(summary.npc)")),
                            .init(id: 3, label: Text("Damage"), value: Text(verbatim: KillmailText.figure(summary.damage))),
                        ])
                        HUDPanelRule()
                        Text(verbatim: [killmail.isSolo ? String(localized: "Solo") : String(localized: "Gang"),
                                        shipName, statics.system(killmail.solarSystemID)?.name,
                                        EVETime.dateTime(killmail.time)]
                                .compactMap { $0 }.joined(separator: " · "))
                            .font(.hudMicro)
                            .tracking(1)
                            .textCase(.uppercase)
                            .foregroundStyle(Color.hudInkMuted)
                            .lineLimit(1)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 9)
                    }
                    .hudBareRow()
                }

                HUDListSection(ranked, row: { row in
                    KillmailAttackerRowView(row: row,
                                            name: naming.attacker(row.attacker, statics: statics),
                                            organization: organization(of: row.attacker, naming: naming),
                                            isPilot: row.attacker.characterID == sheet.characterID,
                                            ship: [statics.typeName(row.attacker.shipTypeID),
                                                   statics.typeName(row.attacker.separateWeaponTypeID)]
                                                .compactMap { $0 }.joined(separator: " · "))
                }, header: {
                    HUDSectionHeader(Text("By Damage")) {
                        Text(verbatim: "\(KillmailText.figure(summary.damage)) HP")
                    }
                }, footer: {
                    HUDFootnote(Text("Share is each attacker's damage of the \(KillmailText.figure(summary.damage)) the \(shipName ?? String(localized: "ship")) took. NPCs have no pilot or security status. The small plate is the weapon; a pilot in a capsule fought with drones."))
                })
            }
        }
        .hudScreen()
        .navigationTitle("Attackers")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// `Corporation · Alliance · Faction` for a pilot, `NPC Corporation` for an NPC: its
    /// corporation is already its name.
    private func organization(of attacker: KillmailAttacker, naming: KillmailNaming) -> String {
        if attacker.isNPC { return String(localized: "NPC Corporation") }
        return naming.organization(corporationID: attacker.corporationID, allianceID: attacker.allianceID,
                                   factionID: attacker.factionID)
    }
}

private struct KillmailAttackerRowView: View {
    let row: KillmailAttackerRow
    let name: String
    let organization: String
    let isPilot: Bool
    let ship: String

    var body: some View {
        let attacker = row.attacker
        HStack(alignment: .top, spacing: 12) {
            HUDBadgedPlate(url: attacker.shipTypeID.map { EVEImage.icon(typeID: $0, size: 128) },
                           badgeURL: attacker.separateWeaponTypeID.map { EVEImage.icon(typeID: $0, size: 64) })
                .opacity(attacker.isNPC ? 0.8 : 1)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(verbatim: name)
                        .font(HUDFont.display(15, weight: .semibold, relativeTo: .body))
                        .foregroundStyle(isPilot ? Color.hudAccent : attacker.isNPC ? Color.hudInkBodyMuted : Color.hudInk)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    KillmailAttackerMarks(row: row)
                }
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(verbatim: organization)
                        .textCase(.uppercase)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if attacker.isNPC {
                        Text(verbatim: "—")
                    } else {
                        Text(verbatim: KillmailText.security(attacker.securityStatus))
                            .foregroundStyle(KillmailText.securityColor(attacker.securityStatus))
                            .fixedSize()
                    }
                }
                .font(HUDFont.mono(11, weight: .regular, relativeTo: .caption))
                .foregroundStyle(Color.hudInkMuted)
                Text(verbatim: ship)
                    .font(HUDFont.mono(11, weight: .regular, relativeTo: .caption))
                    .textCase(.uppercase)
                    .foregroundStyle(Color.hudInkMuted)
                    .lineLimit(1)
                HStack(spacing: 8) {
                    HUDJobProgressBar(fraction: row.share, color: attacker.isNPC ? .hudInkFaint : .hudAccent)
                    Text(verbatim: KillmailText.share(row.share))
                        .font(HUDFont.mono(11, weight: .regular, relativeTo: .caption))
                        .foregroundStyle(Color.hudInkMuted)
                        .frame(minWidth: 44, alignment: .trailing)
                    Text(verbatim: KillmailText.figure(attacker.damageDone))
                        .font(HUDFont.mono(13, weight: .semibold, relativeTo: .subheadline))
                        .frame(minWidth: 44, alignment: .trailing)
                }
                .lineLimit(1)
                .padding(.top, 2)
            }
        }
        .padding(.leading, 12)
        .padding(.trailing, 14)
        .accessibilityElement(children: .combine)
        .hudRow(HUDRowStyle(horizontalPadding: 0, minHeight: 0, verticalPadding: 12))
    }
}
