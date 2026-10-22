import SwiftUI
import UIKit
import UserNotifications

/// The notification schedule of every colony (`PlanetaryReport.schedule`), pushed by
/// `PlanetaryRoute.notifications` from the bell in the section's toolbar: what to be told about,
/// which colonies, and what is scheduled on this iPhone because of it.
///
/// The settings live in `UserDefaults` under `PlanetaryNotificationSettings`' keys; every change
/// reschedules at once from the report at hand. The list is the same plan the scheduler hands to
/// iOS, so it shows what will arrive — dimmed, and said so, while iOS does not allow it.
struct PlanetaryNotificationsView: View {
    let model: PlanetaryModel

    @Environment(\.scenePhase) private var scenePhase
    @State private var status: UNAuthorizationStatus?

    @AppStorage(PlanetaryNotificationSettings.enabledKey(.extractorsFinish)) private var notifyExtractors = true
    @AppStorage(PlanetaryNotificationSettings.enabledKey(.storageFull)) private var notifyFull = true
    @AppStorage(PlanetaryNotificationSettings.enabledKey(.factoryStarved)) private var notifyStarved = true
    @AppStorage(PlanetaryNotificationSettings.enabledKey(.outputLost)) private var notifyLost = true
    @AppStorage(PlanetaryNotificationSettings.leadKey(.extractorsFinish))
    private var extractorLead = PlanetaryNotificationSettings.defaultLead
    @AppStorage(PlanetaryNotificationSettings.leadKey(.storageFull))
    private var fullLead = PlanetaryNotificationSettings.defaultLead
    @AppStorage(PlanetaryNotificationSettings.mutedKey) private var muted = ""

    private static let rowStyle = HUDRowStyle(minHeight: 56, verticalPadding: 12)
    private static let eventStyle = HUDRowStyle(minHeight: 0, verticalPadding: 12)

    private var characterID: Int64 { model.sheet.characterID }

    private var settings: PlanetaryNotificationSettings {
        var enabled: Set<ColonyEvent.Kind> = []
        if notifyExtractors { enabled.insert(.extractorsFinish) }
        if notifyFull { enabled.insert(.storageFull) }
        if notifyStarved { enabled.insert(.factoryStarved) }
        if notifyLost { enabled.insert(.outputLost) }
        return PlanetaryNotificationSettings(
            enabled: enabled,
            leadHours: [.extractorsFinish: extractorLead, .storageFull: fullLead],
            muted: PlanetaryNotificationSettings.mutedPlanets(muted, characterID: characterID))
    }

    private var isAllowed: Bool {
        status.map(PlanetaryNotifications.isAllowed) ?? true
    }

    var body: some View {
        PlanetaryReportContent(model: model) { report in
            TimelineView(.everyMinute) { context in
                content(report: report, now: max(context.date, report.now))
            }
        }
        .hudScreen()
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.inline)
        .task { await refreshStatus() }
        .onChange(of: scenePhase) { _, phase in
            // Back from Settings, the answer may have changed.
            if phase == .active { Task { await refreshStatus() } }
        }
        .onChange(of: settings) { _, _ in
            model.rescheduleNotifications()
        }
    }

    private func refreshStatus() async {
        let previous = status
        status = await PlanetaryNotifications.authorizationStatus()
        if previous != nil, previous != status {
            model.rescheduleNotifications()
        }
    }

    private func content(report: PlanetaryReport, now: Date) -> some View {
        let alerts = PlanetaryNotifications.plan(report: report, settings: settings, now: now)
        return HUDList {
            permission
            kinds
            if !report.colonies.isEmpty {
                colonies(report)
            }
            scheduled(alerts, now: now)
        }
    }

    // MARK: Permission

    @ViewBuilder
    private var permission: some View {
        switch status {
        case .notDetermined?:
            Section {
                HUDEmptyPanel(title: Text("Notifications"),
                              message: Text("Neocom can tell you before an extractor program ends or a storage fills up."),
                              systemImage: "bell") {
                    Button("Allow Notifications") {
                        Task {
                            _ = await PlanetaryNotifications.requestAuthorization()
                            await refreshStatus()
                            model.rescheduleNotifications()
                        }
                    }
                    .hudProminentButton()
                }
                .hudBareRow()
            }
        case .denied?:
            Section {
                HUDNotificationsOffPanel(detail: Text("The schedule is kept and starts working as soon as you allow it."),
                                         note: Text("Allow notifications for Neocom in Settings."))
                    .hudBareRow()
            }
        default:
            EmptyView()
        }
    }

    // MARK: Kinds

    private var kinds: some View {
        HUDListSection {
            kindRow(title: Text("Extractor program ends"), detail: Text("Factories run dry soon after."),
                    isOn: $notifyExtractors)
            if notifyExtractors {
                leadRow(selection: $extractorLead)
            }
            kindRow(title: Text("Storage or Launchpad full"),
                    detail: Text("From then on, output that has nowhere to go is lost."), isOn: $notifyFull)
            if notifyFull {
                leadRow(selection: $fullLead)
            }
            kindRow(title: Text("Factory starved"),
                    detail: Text("Only when it will wait for input longer than \(EVETime.duration(PlanetaryAnalysis.longWait))."),
                    isOn: $notifyStarved)
            kindRow(title: Text("Output lost"), detail: Text("When the forecast shows output being wasted."),
                    isOn: $notifyLost)
        } header: {
            HUDSectionHeader(Text("Notify me when")) {
                Text("All colonies")
            }
        }
    }

    private func kindRow(title: Text, detail: Text, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            HUDRowTitle(title: title, subtitle: detail, subtitleCase: nil)
        }
        .tint(Color.hudAccentFill)
        .hudRow(Self.rowStyle)
    }

    private func leadRow(selection: Binding<Int>) -> some View {
        HStack(spacing: 12) {
            Text("Alert")
                .font(.hudLabel)
                .tracking(1)
                .textCase(.uppercase)
                .foregroundStyle(Color.hudInkMuted)
            Spacer(minLength: 8)
            Picker("Alert", selection: selection) {
                ForEach(PlanetaryNotificationSettings.leadChoices, id: \.self) { hours in
                    if hours == 0 {
                        Text("At the moment").tag(hours)
                    } else {
                        Text("\(hours) h before").tag(hours)
                    }
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
        }
        .hudRow(HUDRowStyle(minHeight: 0, verticalPadding: 6))
    }

    // MARK: Colonies

    private func colonies(_ report: PlanetaryReport) -> some View {
        let mutedPlanets = PlanetaryNotificationSettings.mutedPlanets(muted, characterID: characterID)
        return HUDListSection(Text("Colonies")) {
            ForEach(report.colonies) { colony in
                let planetID = colony.id
                Toggle(isOn: Binding(
                    get: { !mutedPlanets.contains(planetID) },
                    set: { isOn in
                        muted = PlanetaryNotificationSettings.setMuted(!isOn, planetID: planetID,
                                                                       characterID: characterID, in: muted)
                    })) {
                    HUDRowTitle(title: Text(verbatim: colony.planet.displayName),
                                subtitle: Text(verbatim: subtitle(colony)))
                }
                .tint(Color.hudAccentFill)
                .hudRow(Self.rowStyle)
            }
        }
    }

    private func subtitle(_ colony: ColonyDetail) -> String {
        let products = colony.overview.products.map(\.commodity.name)
        let what = products.isEmpty
            ? (colony.overview.status == .stopped ? String(localized: "Stopped") : String(localized: "Nothing made"))
            : products.joined(separator: ", ")
        return "\(colony.planet.kind.title) · \(what)"
    }

    // MARK: Scheduled

    #if targetEnvironment(macCatalyst)
    private static let onDevice = Text("On this Mac")
    private static let scheduleNote = Text("Notifications are scheduled on this Mac from each colony's forecast and rebuilt whenever fresh data arrives from EVE. Until you open a colony in game again, Neocom cannot know what you changed there, so a reminder may come for something you already fixed.")
    #else
    private static let onDevice = Text("On this iPhone")
    private static let scheduleNote = Text("Notifications are scheduled on this iPhone from each colony's forecast and rebuilt whenever fresh data arrives from EVE. Until you open a colony in game again, Neocom cannot know what you changed there, so a reminder may come for something you already fixed.")
    #endif

    @ViewBuilder
    private func scheduled(_ alerts: [PlanetaryAlert], now: Date) -> some View {
        let header = HUDSectionHeader(Text("Scheduled · \(alerts.count)")) {
            if isAllowed {
                Self.onDevice
            } else {
                Text("Not delivered").foregroundStyle(Color.hudWarn)
            }
        }
        let footnote = HUDFootnote(Self.scheduleNote)
        if alerts.isEmpty {
            Section {
                HUDEmptyPanel(title: Text("Nothing scheduled"),
                              message: Text("No colony has anything ahead that you asked to be told about."))
                    .hudBareRow()
            } header: {
                header.hudListHeader()
            } footer: {
                footnote.hudListFooter()
            }
        } else {
            HUDListSection {
                ForEach(alerts) { alert in
                    NavigationLink(value: alert.route) {
                        HUDEventRow(when: Text(verbatim: EVETime.relative(alert.fireDate, now: now)),
                                    whenDetail: Text(verbatim: EVETime.monthDayTime(alert.fireDate)),
                                    whenColor: alert.kind == .extractorsFinish ? .hudInk : .hudWarn,
                                    title: Text(verbatim: alert.title),
                                    detail: Text(verbatim: alert.detail.uppercased()),
                                    whenWidth: 76, showsChevron: true)
                            .opacity(isAllowed ? 1 : 0.55)
                            .hudRow(Self.eventStyle)
                    }
                    .hudRowButton(Self.eventStyle)
                }
            } header: {
                header
            } footer: {
                footnote
            }
        }
    }
}

#if DEBUG
#Preview("Notifications") {
    let model = PlanetaryModel.preview()
    NavigationStack {
        PlanetaryNotificationsView(model: model)
            .navigationDestination(for: PlanetaryRoute.self) { $0.destination(model: model) }
    }
}
#endif
