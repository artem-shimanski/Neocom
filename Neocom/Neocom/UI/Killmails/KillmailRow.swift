import KillmailKit
import SDEKit
import SwiftUI

/// One killmail of a list: the hull, the victim, kill or loss, where, how many, its worth and
/// when — and, under it, whatever the list adds (`footer`): zKillboard's `SOLO` / `NPC` /
/// `AWOX` and points.
///
/// The pilot's Killmails list and the zKillboard results draw their rows with it.
struct KillmailRow<Footer: View>: View {
    static var rowStyle: HUDRowStyle { HUDRowStyle(horizontalPadding: 0, minHeight: 0, verticalPadding: 12) }

    let killmail: Killmail
    /// `nil` where a killmail has no side — a zKillboard search of a place.
    let side: KillmailSide?
    let isVictimPilot: Bool
    let victim: String
    let shipName: String?
    let place: Text?
    let value: Double?
    /// What the value is: `EST. ISK` (Neocom's estimate), `ZKB ISK` (zKillboard's).
    let valueCaption: Text
    @ViewBuilder var footer: Footer

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            HUDItemIcon(typeID: TypeID(rawValue: UInt32(clamping: killmail.victim.shipTypeID)), size: 44)
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(verbatim: shipName ?? String(localized: "Unknown Ship"))
                        .font(HUDFont.display(15, weight: .semibold, relativeTo: .body))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(verbatim: value.map { KillmailText.isk($0) } ?? "—")
                        .font(HUDFont.mono(14, weight: .semibold, relativeTo: .subheadline))
                        .lineLimit(1)
                        .fixedSize()
                }
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(verbatim: victim)
                        .foregroundStyle(isVictimPilot ? Color.hudAccent : Color.hudInkMuted)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    valueCaption
                        .textCase(.uppercase)
                        .lineLimit(1)
                        .fixedSize()
                }
                .font(HUDFont.mono(11, weight: .regular, relativeTo: .caption))
                .foregroundStyle(Color.hudInkMuted)
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    if let side {
                        HUDStatusChip(text: Text(verbatim: KillmailText.title(of: side)),
                                      color: KillmailText.color(of: side), mark: .dot)
                            .lineLimit(1)
                            .fixedSize()
                    }
                    (place ?? Text(verbatim: KillmailText.involved(killmail).uppercased()))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(verbatim: EVETime.time(killmail.time))
                        .lineLimit(1)
                        .fixedSize()
                }
                .font(HUDFont.mono(11, weight: .regular, relativeTo: .caption))
                .foregroundStyle(Color.hudInkMuted)
                footer
            }
        }
        .padding(.leading, 12)
        .padding(.trailing, 14)
        .hudRow(Self.rowStyle)
    }
}

extension KillmailRow where Footer == EmptyView {
    init(killmail: Killmail, side: KillmailSide?, isVictimPilot: Bool, victim: String, shipName: String?,
         place: Text?, value: Double?, valueCaption: Text = Text("Est. ISK")) {
        self.init(killmail: killmail, side: side, isVictimPilot: isVictimPilot, victim: victim, shipName: shipName,
                  place: place, value: value, valueCaption: valueCaption, footer: { EmptyView() })
    }
}

extension View {
    /// A killmail row's context menu: the report's own share item, and the link itself — the
    /// same zKillboard URL the report's toolbar shares, without opening the report first.
    @ViewBuilder
    func killmailContextMenu(killID: Int64) -> some View {
        if let url = KillmailText.zKillboard(killID: killID) {
            contextMenu {
                ShareLink(item: url) {
                    Label("Share zKillboard Link", systemImage: "square.and.arrow.up")
                }
                HUDCopyButton("Copy zKillboard Link", value: url.absoluteString, systemImage: "link")
            }
        } else {
            self
        }
    }
}
