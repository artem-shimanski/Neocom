import SDEKit
import SwiftUI

/// Settings › Notifications: what the app tells the player about, for every pilot on the device.
///
/// Training and Planetary Interaction lead to screens of their own; the kinds only a check with EVE
/// can learn about, and industry (scheduled from the jobs' end times), are a switch each. Offered
/// only with a pilot signed in.
///
/// While iOS does not allow notifications the section says so above itself and dims, but the
/// choices stay editable.
struct SettingsNotificationsSection: View {
    #if targetEnvironment(macCatalyst)
    private static let scheduleNote = Text("Training, planets and industry end at known times, so they are scheduled on this Mac. Orders, contracts and mail need a check with EVE, which macOS lets Neocom make only now and then: those may come late.")
    #else
    private static let scheduleNote = Text("Training, planets and industry end at known times, so they are scheduled on this iPhone. Orders, contracts and mail need a check with EVE, which iOS runs in the background when it sees fit: those may come late.")
    #endif

    @Environment(AccountStore.self) private var accounts
    @Environment(LocalNotifications.self) private var notifications

    @AppStorage(PlanetaryNotificationSettings.enabledKey(.extractorsFinish)) private var notifyExtractors = true
    @AppStorage(PlanetaryNotificationSettings.enabledKey(.storageFull)) private var notifyFull = true
    @AppStorage(PlanetaryNotificationSettings.enabledKey(.factoryStarved)) private var notifyStarved = true
    @AppStorage(PlanetaryNotificationSettings.enabledKey(.outputLost)) private var notifyLost = true

    @AppStorage(NotificationSettings.skillTrainedKey) private var skillTrained = NotificationSettings.defaultSkillTrained
    @AppStorage(NotificationSettings.queueEndingKey) private var queueEnding = NotificationSettings.defaultQueueEnding
    @AppStorage(NotificationSettings.industryKey) private var industry = NotificationSettings.defaultIndustry
    @AppStorage(NotificationSettings.contractsKey) private var contracts = NotificationSettings.defaultContracts
    @AppStorage(NotificationSettings.ordersKey) private var orders = NotificationSettings.defaultOrders
    @AppStorage(NotificationSettings.mailKey) private var mail = NotificationSettings.defaultMail

    private var isDenied: Bool { notifications.status == .denied }
    private var dim: Double { isDenied ? 0.55 : 1 }

    var body: some View {
        if accounts.currentAccount != nil {
            if isDenied {
                Section {
                    HUDNotificationsOffPanel(note: Text("Your choices are kept and start working once you allow them."))
                        .hudBareRow()
                }
            }
            HUDListSection {
                NavigationLink {
                    TrainingNotificationsView()
                } label: {
                    HUDLinkRowLabel(systemImage: MainMenuSection.trainingQueue.systemImage,
                                    title: Text("Training"),
                                    subtitle: Text("Skill trained · queue ending"),
                                    value: Text("\([skillTrained, queueEnding].filter { $0 }.count) of 2"))
                        .opacity(dim)
                }
                .hudRowButton()

                NavigationLink {
                    SettingsPlanetaryNotifications()
                } label: {
                    HUDLinkRowLabel(systemImage: MainMenuSection.planetaryInteraction.systemImage,
                                    title: Text("Planetary Interaction"),
                                    subtitle: Text("Extractors · storage · factories"),
                                    value: Text("\(planetaryEnabled) of \(ColonyEvent.Kind.allCases.count)"))
                        .opacity(dim)
                }
                .hudRowButton()

                toggle(systemImage: "hammer", title: Text("Industry Jobs"),
                       subtitle: Text("Job ready to deliver"), isOn: $industry)
                toggle(systemImage: "doc.text", title: Text("Contracts"),
                       subtitle: Text("Finished or about to expire"), isOn: $contracts)
                toggle(systemImage: "tag", title: Text("Market Orders"),
                       subtitle: Text("Filled or expired"), isOn: $orders)
                toggle(systemImage: "envelope", title: Text("Mail"),
                       subtitle: Text("New mail in the inbox"), isOn: $mail)
            } header: {
                HUDSectionHeader(Text("Notifications")) {
                    Text("All pilots")
                }
            } footer: {
                HUDFootnote(Self.scheduleNote)
            }
            .onChange(of: [industry, contracts, orders, mail]) { old, new in
                NotificationPlanner.shared.settingsChanged()
                // The first switch turned on is when iOS is asked.
                if zip(old, new).contains(where: { !$0 && $1 }) {
                    Task { await notifications.requestIfUndetermined() }
                }
            }
        }
    }

    private func toggle(systemImage: String, title: Text, subtitle: Text, isOn: Binding<Bool>) -> some View {
        HUDIconRow(systemImage: systemImage, title: title, subtitle: subtitle) {
            Toggle(isOn: isOn) { title }
                .labelsHidden()
                .tint(Color.hudAccentFill)
        }
        .opacity(dim)
    }

    /// The planetary events the player is told about, out of the four.
    private var planetaryEnabled: Int {
        [notifyExtractors, notifyFull, notifyStarved, notifyLost].filter { $0 }.count
    }
}

/// The Planetary Interaction schedule reached from Settings: the same screen, on a model of its own
/// over the current character's colonies.
private struct SettingsPlanetaryNotifications: View {
    @Environment(AccountStore.self) private var accounts

    var body: some View {
        SDESectionView { database in
            if let sheet = accounts.currentPlanets {
                Screen(sheet: sheet, database: database)
                    .id(ObjectIdentifier(sheet))
            }
        }
        .hudScreen()
    }

    private struct Screen: View {
        @State private var model: PlanetaryModel

        init(sheet: PlanetsSheet, database: SDEDatabase) {
            _model = State(initialValue: PlanetaryModel(sheet: sheet, database: database))
        }

        var body: some View {
            PlanetaryNotificationsView(model: model)
        }
    }
}
