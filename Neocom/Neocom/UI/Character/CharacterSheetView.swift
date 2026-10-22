import SwiftUI
import TrainingKit

/// The Character Sheet section: who the pilot is, what they own, where they are, and what they have
/// trained.
///
/// Wrapped in `SDESectionView`: implants, the ship, the bloodline and the solar system are named
/// out of the SDE.
struct CharacterSheetView: View {
    var body: some View {
        SDESectionView { _ in
            CharacterSheetBody()
        }
        .hudScreen()
        .navigationTitle("Character Sheet")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// The screen once the database is open: the list, or what stands in for it while there is nothing
/// to list.
private struct CharacterSheetBody: View {
    @Environment(AccountStore.self) private var accounts
    @Environment(\.trainingContext) private var trainingContext

    var body: some View {
        let sheet = accounts.currentSheet

        Group {
            if sheet?.profile != nil {
                list(sheet)
            } else if case let .failed(error)? = sheet?.profileState {
                // Nothing on disk and nothing from the network: the screen shows the reason.
                ContentUnavailableView {
                    Label("Character Unavailable", systemImage: "person.crop.circle.badge.exclamationmark")
                } description: {
                    Text(error.localizedDescription)
                } actions: {
                    Button("Retry") {
                        Task { await sheet?.refresh() }
                    }
                }
            } else {
                ProgressView()
                    .controlSize(.large)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        // The home card asks for the profile too; the sheet coalesces the two.
        .task(id: accounts.currentAccountID) {
            // Skills, attributes and implants come from the training snapshot, the rest from the
            // profile.
            async let training: Void? = sheet?.ensureFresh()
            async let profile: Void? = sheet?.ensureProfileFresh()
            _ = await (training, profile)
        }
        .refreshableCommand {
            await sheet?.refresh()
        }
    }

    /// Every section is its own view: `@LiteQuery` builds its query in `init`, so a section that
    /// needs names is handed what it names as an argument.
    @ViewBuilder
    private func list(_ sheet: CharacterSheet?) -> some View {
        HUDList {
            if let account = accounts.currentAccount {
                Section {
                    CharacterSheetHeader(account: account, profile: sheet?.profile)
                        .hudBareRow()
                }
            }

            if let profile = sheet?.profile {
                CharacterBioSection(profile: profile)
                CharacterLocationSection(shipTypeID: profile.shipTypeID,
                                         shipName: profile.shipName,
                                         location: profile.location)
                CharacterWalletSection(balance: profile.balance)
            }

            if let snapshot = sheet?.snapshot {
                CharacterSkillsSection(snapshot: snapshot, pilot: trainingContext?.pilot)
            }

            if let pilot = trainingContext?.pilot {
                CharacterAttributesSection(pilot: pilot)
            }

            if let snapshot = sheet?.snapshot {
                CharacterImplantsSection(implants: snapshot.implants)
            }

            if let profile = sheet?.profile {
                CharacterClonesSection(homeLocation: profile.homeLocation,
                                       lastCloneJumpDate: profile.lastCloneJumpDate,
                                       clones: profile.jumpClones)
            }

            // The last refresh failed but the disk had data: show it with its age rather than an
            // error over readable numbers.
            if case .failed? = sheet?.profileState, let fetchedAt = sheet?.profileFetchedAt {
                Section {
                    HUDFootnote(Text("Updated \(fetchedAt, format: .relative(presentation: .named))"))
                        .hudBareRow()
                }
            }
        }
    }
}

/// Portrait, name, corporation and alliance.
private struct CharacterSheetHeader: View {
    let account: Account
    let profile: CharacterProfile?

    var body: some View {
        HStack(alignment: .bottom, spacing: 16) {
            HUDImagePlate(url: account.portraitURL, size: 112, radius: 20, framed: true)

            VStack(alignment: .leading, spacing: 8) {
                // The name from the profile, falling back to the one the token was issued for: a
                // newly added character has a name before a profile.
                Text(profile?.name ?? account.characterName)
                    .font(.hudPilotName)
                    .tracking(0.5)
                    .textCase(.uppercase)
                    .lineLimit(3)

                if let profile, let corporationName = profile.corporationName {
                    affiliation(logo: EVEImage.logo(corporationID: profile.corporationID),
                                name: corporationName,
                                ticker: profile.corporationTicker)
                }

                if let profile, let allianceID = profile.allianceID, let allianceName = profile.allianceName {
                    affiliation(logo: EVEImage.logo(allianceID: allianceID),
                                name: allianceName,
                                ticker: profile.allianceTicker)
                }
            }
            .padding(.bottom, 4)

            Spacer(minLength: 0)
        }
    }

    private func affiliation(logo: URL, name: String, ticker: String?) -> some View {
        HStack(spacing: 6) {
            HUDImagePlate(url: logo, size: 18, radius: 4)
            Text(ticker.map { "\(name) [\($0)]" } ?? name)
                .font(.hudCaption)
                .foregroundStyle(Color.hudInkMuted)
                .lineLimit(1)
        }
    }
}

#Preview {
    NavigationStack {
        CharacterSheetView()
    }
    .environment(AccountStore())
    .environment(SDEStore())
}
