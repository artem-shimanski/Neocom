import SwiftUI
import TrainingKit

/// Settings › Notifications › Training: what to be told about the skill queue, for which pilots,
/// and what is scheduled on this iPhone because of it.
///
/// The settings live in `UserDefaults` under `NotificationSettings`' keys; every change reschedules
/// at once from the queues at hand (`NotificationPlanner`). The list is what iOS holds pending for
/// training, or, while iOS does not allow notifications, what would be there, dimmed.
struct TrainingNotificationsView: View {
    @Environment(AccountStore.self) private var accounts
    @Environment(LocalNotifications.self) private var notifications

    @AppStorage(NotificationSettings.skillTrainedKey) private var skillTrained = NotificationSettings.defaultSkillTrained
    @AppStorage(NotificationSettings.queueEndingKey) private var queueEnding = NotificationSettings.defaultQueueEnding
    @AppStorage(NotificationSettings.queueLeadKey) private var queueLead = TrainingReminders.defaultLead
    @AppStorage(NotificationSettings.mutedPilotsKey) private var muted = ""

    @State private var scheduled: [LocalNotificationRequest] = []

    private static let rowStyle = HUDRowStyle(minHeight: 56, verticalPadding: 12)
    private static let eventStyle = HUDRowStyle(minHeight: 0, verticalPadding: 12)
    private static let prefix = NotificationKind.training.prefix

    private struct Choices: Equatable {
        var skillTrained: Bool
        var queueEnding: Bool
        var queueLead: Int
        var muted: String
    }

    private var choices: Choices {
        Choices(skillTrained: skillTrained, queueEnding: queueEnding, queueLead: queueLead, muted: muted)
    }

    private var isAllowed: Bool { notifications.isAllowed }

    var body: some View {
        // The one clock of the screen.
        TimelineView(.everyMinute) { context in
            content(now: context.date)
        }
        .hudScreen()
        .navigationTitle("Training")
        .navigationBarTitleDisplayMode(.inline)
        // Opening the screen is when iOS is asked, if it never was.
        .task { await notifications.requestIfUndetermined() }
        .task(id: ScheduleKey(revision: notifications.revision, isAllowed: isAllowed)) {
            scheduled = isAllowed
                ? await notifications.pending(prefix: Self.prefix)
                : notifications.planned(prefix: Self.prefix)
        }
        .onChange(of: choices) { old, new in
            NotificationPlanner.shared.settingsChanged()
            if (!old.skillTrained && new.skillTrained) || (!old.queueEnding && new.queueEnding) {
                Task { await notifications.requestIfUndetermined() }
            }
        }
    }

    private struct ScheduleKey: Equatable {
        var revision: Int
        var isAllowed: Bool
    }

    private func content(now: Date) -> some View {
        HUDList {
            kinds
            pilots(now: now)
            scheduledSection(now: now)
        }
    }

    // MARK: Kinds

    private var kinds: some View {
        HUDListSection("Notify me when") {
            kindRow(title: Text("Skill trained"), detail: Text("Each skill as it reaches its level."),
                    isOn: $skillTrained)
            kindRow(title: Text("Queue running out"),
                    detail: Text("Before the last skill in the queue ends, so training never stops."),
                    isOn: $queueEnding)
            if queueEnding {
                leadRow
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

    private var leadRow: some View {
        HStack(spacing: 12) {
            Text("Alert")
                .font(.hudLabel)
                .tracking(1)
                .textCase(.uppercase)
                .foregroundStyle(Color.hudInkMuted)
            Spacer(minLength: 8)
            Picker("Alert", selection: $queueLead) {
                ForEach(TrainingReminders.leadChoices, id: \.self) { hours in
                    if hours == 0 {
                        Text("At the end").tag(hours)
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

    // MARK: Pilots

    private func pilots(now: Date) -> some View {
        let mutedPilots = NotificationSettings.mutedPilots(muted)
        return HUDListSection("Pilots") {
            ForEach(accounts.accounts) { account in
                let characterID = account.id
                HStack(spacing: 12) {
                    HUDImagePlate(url: account.portraitURL, size: 36)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: account.characterName)
                            .font(.hudTileTitle)
                            .tracking(0.3)
                            .foregroundStyle(Color.hudInk)
                        status(of: account, now: now)
                    }
                    Spacer(minLength: 8)
                    Toggle(isOn: Binding(
                        get: { !mutedPilots.contains(characterID) },
                        set: { isOn in
                            muted = NotificationSettings.setMuted(!isOn, characterID: characterID, in: muted)
                        })) {
                        Text(verbatim: account.characterName)
                    }
                    .labelsHidden()
                    .tint(Color.hudAccentFill)
                }
                .hudRow(.subtitled)
            }
        }
    }

    /// The pilot's queue as their sheet last saw it, made from the disk cache and never fetched for
    /// this screen.
    private func status(of account: Account, now: Date) -> some View {
        let (text, color): (Text, Color) = switch queueState(of: account, now: now) {
        case nil: (Text("No data yet"), .hudInkMuted)
        case .empty?: (Text("Queue empty"), .hudWarn)
        case .paused?: (Text("Queue paused"), .hudWarn)
        case let .training(until)?: (Text("Training · ends \(EVETime.relative(until, now: now))"), .hudInkMuted)
        }
        return text
            .font(HUDFont.mono(11, weight: .regular, relativeTo: .caption))
            .textCase(.uppercase)
            .foregroundStyle(color)
            .lineLimit(1)
    }

    private func queueState(of account: Account, now: Date) -> TrainingReminders.QueueState? {
        accounts.sheet(for: account).snapshot.map { TrainingReminders.state(of: $0.queue, now: now) }
    }

    // MARK: Scheduled

    #if targetEnvironment(macCatalyst)
    private static let onDevice = Text("On this Mac")
    #else
    private static let onDevice = Text("On this iPhone")
    #endif

    @ViewBuilder
    private func scheduledSection(now: Date) -> some View {
        let items = scheduled.filter { $0.fireDate > now }
        let header = HUDSectionHeader(Text("Scheduled · \(items.count)")) {
            if isAllowed {
                Self.onDevice
            } else {
                Text("Not delivered").foregroundStyle(Color.hudWarn)
            }
        }
        let footnote = HUDFootnote(Text("Reminders are rebuilt from each pilot's queue whenever fresh data arrives from EVE. If you change the queue in game, open Neocom once so the times here follow."))
        if items.isEmpty {
            Section {
                HUDEmptyPanel(title: Text("Nothing scheduled"), message: emptyMessage(now: now))
                    .hudBareRow()
            } header: {
                header.hudListHeader()
            } footer: {
                footnote.hudListFooter()
            }
        } else {
            HUDListSection {
                ForEach(items) { item in
                    HUDEventRow(when: Text(verbatim: EVETime.relative(item.fireDate, now: now)),
                                whenDetail: Text(verbatim: EVETime.monthDayTime(item.fireDate)),
                                whenColor: .hudInk,
                                title: Text(verbatim: item.title),
                                detail: Text(verbatim: item.body),
                                whenWidth: 76)
                        .opacity(isAllowed ? 1 : 0.55)
                        .hudRow(Self.eventStyle)
                }
            } header: {
                header
            } footer: {
                footnote
            }
        }
    }

    /// Why the list is empty, in the most specific words that are true.
    private func emptyMessage(now: Date) -> Text {
        guard skillTrained || queueEnding else {
            return Text("Both reminders are off.")
        }
        let mutedPilots = NotificationSettings.mutedPilots(muted)
        let listened = accounts.accounts.filter { !mutedPilots.contains($0.id) }
        guard !listened.isEmpty else {
            return Text("Every pilot's training reminders are off.")
        }
        let paused = listened.filter { queueState(of: $0, now: now) == .paused }
        if listened.count == 1, let pilot = paused.first {
            return Text("\(pilot.characterName)'s queue is paused: no skill has an end time yet.")
        }
        if paused.count == listened.count {
            return Text("Every queue is paused: no skill has an end time yet.")
        }
        return Text("No skill in any queue has an end time ahead.")
    }
}
