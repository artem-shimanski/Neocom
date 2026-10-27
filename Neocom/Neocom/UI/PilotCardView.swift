import ESIKit
import SwiftUI
import TrainingKit

/// The pilot card at the top of the home screen: portrait, name, corporation, and a strip of
/// wallet, security status and skill points.
///
/// Figures come from the character sheet's snapshots and are left out until they arrive.
struct PilotCardView: View {
    let account: Account?
    let sheet: CharacterSheet?

    @State private var corporationName: String?

    var body: some View {
        HUDPanel {
            HStack(spacing: 14) {
                portrait
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(account?.characterName ?? String(localized: "No Character"))
                            .font(.hudCardTitle)
                            .tracking(0.5)
                            .textCase(.uppercase)
                            .foregroundStyle(Color.hudInk)
                            .lineLimit(2)
                        if account?.isDemo == true {
                            HUDOutlineTag.demo
                        }
                    }
                    Text(subtitle)
                        .font(.hudCaption)
                        .foregroundStyle(Color.hudInkMuted)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(14)

            if account != nil {
                HUDPanelRule()
                HUDStatStrip(items: stats)
            }
        }
        .task(id: account?.id) { await loadCorporation() }
    }

    @ViewBuilder private var portrait: some View {
        if let account {
            HUDImagePlate(url: account.portraitURL, size: 64, radius: 12, framed: true)
        } else {
            Image(systemName: "person.fill")
                .font(.title)
                .foregroundStyle(Color.hudInkMuted)
                .frame(width: 64, height: 64)
                .background(Color.hudSurfaceRaised, in: .rect(cornerRadius: 12))
        }
    }

    private var subtitle: String {
        guard account != nil else { return String(localized: "Tap to sign in with EVE Online") }
        if let profile = sheet?.profile, let name = profile.corporationName {
            return profile.corporationTicker.map { "[\($0)] \(name)" } ?? name
        }
        return corporationName ?? String(localized: "Loading…")
    }

    private var stats: [HUDStatStrip.Item] {
        let profile = sheet?.profile
        let securityStatus = profile?.securityStatus
        return [
            HUDStatStrip.Item(id: 0,
                              label: Text("ISK"),
                              value: Text(verbatim: profile?.balance.map { Self.compact($0) } ?? "—")),
            HUDStatStrip.Item(id: 1,
                              label: Text("Sec"),
                              value: Text(verbatim: securityStatus.map { SecurityStatus.string($0, fractionLength: 2, signed: true) } ?? "—"),
                              color: securityStatus.map { SecurityStatus.color($0) } ?? .hudInk),
            HUDStatStrip.Item(id: 2,
                              label: Text("SP"),
                              value: Text(verbatim: sheet?.snapshot.map { Self.compact(Double($0.totalSkillPoints)) } ?? "—")),
        ]
    }

    /// Four significant digits: "30.27M", "176.8M".
    private static func compact(_ value: Double) -> String {
        value.formatted(.number.notation(.compactName).precision(.significantDigits(1...4)))
    }

    private func loadCorporation() async {
        corporationName = nil
        // The demo pilot has no public record; its profile comes from the sheet.
        guard let account, !account.isDemo else { return }
        // Public data only: the card must render before a token is refreshed or the profile has
        // been fetched.
        guard let character = try? await ESIService.publicClient.character(id: account.characterID),
              let corporation = try? await ESIService.publicClient.corporation(id: character.corporationId)
        else { return }
        corporationName = corporation.name
    }
}
