import Foundation
import Observation
import UserNotifications

/// Every kind of notification the app posts. Identifiers have the form
/// `<kind>.<characterID>.<id>`, or `<kind>.<corporationID>.<id>` for the corporation kinds.
nonisolated enum NotificationKind: String, CaseIterable, Sendable {
    case planetary
    case training
    case industry
    case contracts
    case orders
    case mail
    case corporationIndustry
    case corporationContracts
    case corporationOrders

    var prefix: String { "\(rawValue)." }

    var isCorporation: Bool {
        switch self {
        case .corporationIndustry, .corporationContracts, .corporationOrders: true
        default: false
        }
    }

    /// The identifier prefix of one character's notifications of this kind.
    func scope(characterID: Int64) -> String { "\(rawValue).\(characterID)." }

    /// The identifier prefix of one corporation's notifications of this kind.
    func scope(corporationID: Int64) -> String { "\(rawValue).\(corporationID)." }

    /// The corporation a scope of this kind belongs to.
    func corporationID(ofScope scope: String) -> Int64? {
        guard isCorporation, scope.hasPrefix(prefix) else { return nil }
        return scope.dropFirst(prefix.count).split(separator: ".").first.flatMap { Int64($0) }
    }
}

/// A notification scheduled for a fixed date.
nonisolated struct LocalNotificationRequest: Sendable, Hashable, Identifiable {
    /// The full identifier, including the scope.
    var id: String
    var title: String
    var body: String
    var threadID: String
    var fireDate: Date
}

/// The single interface to `UNUserNotificationCenter`: authorization and the schedule of every
/// kind on this device.
///
/// iOS keeps at most 64 pending requests per app, shared by all kinds, so each replacement
/// schedules the soonest 64 across all plans. Plans are retained (`plans`), so a request
/// displaced by a sooner one is scheduled again later, and the whole schedule can be restored
/// when authorization is granted. Replacements are serialized.
///
/// Immediate notifications are delivered at once and do not count against the limit.
@Observable
@MainActor
final class LocalNotifications {
    static let shared = LocalNotifications()

    /// The maximum number of pending requests iOS keeps per app.
    static let pendingLimit = 64

    /// `nil` until first asked.
    private(set) var status: UNAuthorizationStatus?
    /// Incremented after every change to the pending schedule.
    private(set) var revision = 0

    /// Every planned request by scope, whether or not it is pending in iOS.
    @ObservationIgnored private var plans: [String: [LocalNotificationRequest]] = [:]
    @ObservationIgnored private var queue: Task<Void, Never>?

    private init() {}

    // MARK: - Authorization

    var isAllowed: Bool { status.map(Self.isAllowed) ?? false }

    nonisolated static func isAllowed(_ status: UNAuthorizationStatus) -> Bool {
        switch status {
        case .authorized, .provisional, .ephemeral: true
        default: false
        }
    }

    /// Reads the current authorization status and reapplies or withdraws the schedule when it
    /// changed since the last read.
    @discardableResult
    func refreshStatus() async -> UNAuthorizationStatus {
        let previous = status
        let current = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        status = current
        if let previous, previous != current {
            reapply()
        }
        return current
    }

    /// Requests authorization; returns whether notifications are allowed afterwards.
    @discardableResult
    func requestAuthorization() async -> Bool {
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
        return Self.isAllowed(await refreshStatus())
    }

    /// Requests authorization if the status is not yet determined.
    func requestIfUndetermined() async {
        let current = status == nil ? await refreshStatus() : status
        if current == .notDetermined {
            await requestAuthorization()
        }
    }

    // MARK: - Schedule

    /// Replaces the pending notifications whose identifiers start with `scope` by `requests`.
    func replace(scope: String, with requests: [LocalNotificationRequest]) {
        plans[scope] = requests
        enqueue { await self.apply(replacing: [scope]) }
    }

    /// Removes every planned and pending notification of one character, of every kind.
    func removeAll(characterID: Int64) {
        let scopes = NotificationKind.allCases.filter { !$0.isCorporation }.map { $0.scope(characterID: characterID) }
        for scope in scopes { plans[scope] = [] }
        enqueue { await self.apply(replacing: scopes) }
    }

    /// Planned requests for scopes starting with `prefix`, soonest first, regardless of
    /// authorization.
    func planned(prefix: String, now: Date = .now) -> [LocalNotificationRequest] {
        plans.filter { $0.key.hasPrefix(prefix) }
            .flatMap(\.value)
            .filter { $0.fireDate > now }
            .sorted { ($0.fireDate, $0.id) < ($1.fireDate, $1.id) }
    }

    /// The scopes starting with `prefix` that hold planned or pending requests.
    func scopes(prefix: String) async -> Set<String> {
        let pending = await UNUserNotificationCenter.current().pendingNotificationRequests()
            .map(\.identifier).filter { $0.hasPrefix(prefix) }.map(Self.scope(of:))
        return Set(plans.filter { $0.key.hasPrefix(prefix) && !$0.value.isEmpty }.keys).union(pending)
    }

    /// Pending iOS requests with identifiers starting with `prefix`, soonest first.
    func pending(prefix: String) async -> [LocalNotificationRequest] {
        await UNUserNotificationCenter.current().pendingNotificationRequests()
            .filter { $0.identifier.hasPrefix(prefix) }
            .map { request in
                LocalNotificationRequest(id: request.identifier, title: request.content.title,
                                         body: request.content.body, threadID: request.content.threadIdentifier,
                                         fireDate: Self.fireDate(of: request) ?? .distantFuture)
            }
            .sorted { ($0.fireDate, $0.id) < ($1.fireDate, $1.id) }
    }

    /// Delivers a notification immediately, if authorized.
    func post(id: String, title: String, body: String, threadID: String) {
        enqueue {
            let center = UNUserNotificationCenter.current()
            guard Self.isAllowed(await center.notificationSettings().authorizationStatus) else { return }
            let content = Self.content(title: title, body: body, threadID: threadID)
            try? await center.add(UNNotificationRequest(identifier: id, content: content, trigger: nil))
        }
    }

    /// Reapplies every plan after an authorization change.
    private func reapply() {
        let scopes = Array(plans.keys)
        enqueue { await self.apply(replacing: scopes) }
    }

    private func enqueue(_ work: @escaping @MainActor () async -> Void) {
        let previous = queue
        queue = Task {
            await previous?.value
            await work()
        }
    }

    /// Brings the pending requests in line with the plans; scopes in `replacing` are rebuilt
    /// from scratch, since their content may have changed under the same identifiers.
    ///
    /// Pending requests of scopes not planned since launch were scheduled by an earlier run;
    /// they are adopted into the plans as read back from iOS, so they can regain a slot after
    /// being displaced.
    private func apply(replacing scopes: [String]) async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        let now = Date.now
        let replaced = Set(scopes)
        func scope(of identifier: String) -> String? {
            plans.keys.first { identifier.hasPrefix($0) }
        }
        var adopted: [String: [LocalNotificationRequest]] = [:]
        for request in pending where scope(of: request.identifier) == nil {
            guard let fireDate = Self.fireDate(of: request) else { continue }
            adopted[Self.scope(of: request.identifier), default: []]
                .append(LocalNotificationRequest(id: request.identifier, title: request.content.title,
                                                 body: request.content.body,
                                                 threadID: request.content.threadIdentifier,
                                                 fireDate: fireDate))
        }
        plans.merge(adopted) { current, _ in current }

        guard Self.isAllowed(await center.notificationSettings().authorizationStatus) else {
            // Not authorized: remove the replaced scopes and keep the plans.
            let own = pending.map(\.identifier).filter { id in replaced.contains { id.hasPrefix($0) } }
            center.removePendingNotificationRequests(withIdentifiers: own)
            revision += 1
            return
        }

        let chosen = plans.values.joined().filter { $0.fireDate > now }
            .sorted { ($0.fireDate, $0.id) < ($1.fireDate, $1.id) }
            .prefix(Self.pendingLimit)
        let chosenIDs = Set(chosen.map(\.id))
        let pendingIDs = Set(pending.map(\.identifier))

        let removals = pending.map(\.identifier).filter { id in
            !chosenIDs.contains(id) || replaced.contains { id.hasPrefix($0) }
        }
        center.removePendingNotificationRequests(withIdentifiers: removals)

        for request in chosen {
            let isReplaced = replaced.contains { request.id.hasPrefix($0) }
            guard isReplaced || !pendingIDs.contains(request.id) else { continue }
            let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second],
                                                             from: request.fireDate)
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            let content = Self.content(title: request.title, body: request.body, threadID: request.threadID)
            try? await center.add(UNNotificationRequest(identifier: request.id, content: content, trigger: trigger))
        }
        revision += 1
    }

    private static func content(title: String, body: String, threadID: String) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.threadIdentifier = threadID
        return content
    }

    /// The scope of an identifier (`<kind>.<characterID>.`), or the identifier itself when it
    /// has another form.
    private static func scope(of identifier: String) -> String {
        let parts = identifier.split(separator: ".", maxSplits: 2, omittingEmptySubsequences: false)
        guard parts.count == 3 else { return identifier }
        return "\(parts[0]).\(parts[1])."
    }

    private static func fireDate(of request: UNNotificationRequest) -> Date? {
        switch request.trigger {
        case let trigger as UNCalendarNotificationTrigger: trigger.nextTriggerDate()
        case let trigger as UNTimeIntervalNotificationTrigger: trigger.nextTriggerDate()
        default: nil
        }
    }
}
