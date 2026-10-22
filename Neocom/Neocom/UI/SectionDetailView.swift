import SwiftUI

/// Destination for every section.
///
/// The switch has no `default`, so a new section stops the compiler here.
struct SectionDetailView: View {
    let section: MainMenuSection

    @Environment(AccountStore.self) private var accounts

    var body: some View {
        if section.requiresAccount, accounts.currentAccount == nil {
            ContentUnavailableView(
                "No Character",
                systemImage: "person.crop.circle.badge.exclamationmark",
                description: Text("Sign in with EVE Online to use this section.")
            )
            .hudScreen()
            .navigationTitle(section.title)
        } else {
            switch section {
            case .database:
                // Sets its own title: the browser renames itself as it descends.
                DatabaseView()
            case .trainingQueue:
                TrainingQueueView()
            case .certificates:
                CertificatesView()
            case .skills:
                SkillsView()
            case .characterSheet:
                CharacterSheetView()
            case .fittingTool:
                FittingsView()
            case .zKillboard:
                ZKillboardSearchView()
            case .planetaryInteraction:
                PlanetaryColoniesView()
            case .assets:
                AssetsView()
            case .mail:
                MailView()
            case .killmails:
                KillmailsView()
            case .marketOrders:
                OrdersView()
            case .industry:
                IndustryJobsView()
            case .contracts:
                ContractsView()
            case .support:
                SupportView()
            case .settings:
                SettingsView()
            }
        }
    }
}

#Preview {
    NavigationStack {
        SectionDetailView(section: .trainingQueue)
    }
    .environment(AccountStore())
    .environment(SDEStore())
}
