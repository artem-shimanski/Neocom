import SwiftUI

/// Settings › Legal & Acknowledgements: what Neocom takes from CCP — the game, ESI, SSO, the
/// static data and the image server — each linked to its public page, with CCP's legal notice;
/// and zKillboard, the one service outside CCP it reads.
struct LegalView: View {
    @Environment(\.openURL) private var openURL

    var body: some View {
        HUDList {
            HUDListSection {
                link(SettingsLinks.eveOnline, title: Text(verbatim: "EVE Online"),
                     subtitle: Text("The game, its names, art and world"))
                link(SettingsLinks.esi, title: Text(verbatim: "ESI"),
                     subtitle: Text("Pilot, market and universe data"))
                link(SettingsLinks.sso, title: Text(verbatim: "EVE SSO"),
                     subtitle: Text("Signing in your pilots"))
                link(SettingsLinks.staticData, title: Text("Static Data Export"),
                     subtitle: Text("Items, ships, skills and the map"))
                link(SettingsLinks.imageServer, title: Text("Image Server"),
                     subtitle: Text("Portraits, icons and renders"))
            } header: {
                HUDSectionHeader(Text(verbatim: "Fenris Creations")) {
                    Text("The game and its services")
                }
                .withTitleCase(nil)
            } footer: {
                HUDFootnote(Text(verbatim: Self.ccpNotice))
            }

            HUDListSection {
                link(SettingsLinks.zKillboard, title: Text(verbatim: "zKillboard"),
                     subtitle: Text("Kill search and history · zkillboard.com"))
            } header: {
                HUDSectionHeader("Community")
            } footer: {
                HUDFootnote("An independent project, not part of Fenris Creations. Neocom only reads its public API.")
            }

            Section {
                HUDFootnote(Text(verbatim: "Neocom \(SettingsLinks.version)"))
                    .hudBareRow()
            }
        }
        .navigationTitle("Legal")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func link(_ url: URL, title: Text, subtitle: Text) -> some View {
        Button {
            openURL(url)
        } label: {
            HUDLinkRowLabel(systemImage: nil, title: title, subtitle: subtitle, destination: .external)
        }
        .hudRowButton()
    }

    /// CCP's notice, as its developer license asks third-party apps to carry it. Legal text, not
    /// translated.
    private static let ccpNotice = """
        EVE Online and the EVE logo are the registered trademarks of Fenris Creations (CCP hf.). All rights are \
        reserved worldwide. All other trademarks are the property of their respective owners. \
        EVE Online, the EVE logo, EVE and all associated logos and designs are the intellectual \
        property of Fenris Creations. All artwork, screenshots, characters, vehicles, storylines, world \
        facts or other recognizable features of the intellectual property relating to these \
        trademarks are likewise the intellectual property of Fenris Creations. Fenris Creations has granted \
        permission to Neocom to use EVE Online and all associated logos and designs for \
        promotional and information purposes but does not endorse, and is not in any way \
        affiliated with, Neocom. Fenris Creations is in no way responsible for the content on or functioning \
        of this app, nor can it be liable for any damage arising from the use of this app.
        """
}

#Preview {
    NavigationStack {
        LegalView()
    }
}
