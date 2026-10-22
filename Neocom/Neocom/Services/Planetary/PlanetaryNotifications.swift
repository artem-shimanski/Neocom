import DemoFixtures
import Foundation
import UserNotifications

// Local notifications of the Planetary Interaction section, worked out from the report's
// schedule (`PlanetaryReport.schedule`). They are scheduled on this device only, rebuilt from
// scratch every time a report is made — a fetch, a resimulation, the section being opened — and
// whenever the player changes what to be told about. Nothing runs in the background: until the
// app makes a new report, the schedule is the one the last report left.

/// What the player wants to be told about, as kept in `UserDefaults` (the notifications screen
/// edits the same keys through `@AppStorage`).
nonisolated struct PlanetaryNotificationSettings: Sendable, Equatable {
    /// What a lead can be: the moment itself, or so many hours before it.
    static let leadChoices: [Int] = [0, 1, 4, 12]
    static let defaultLead = 4

    var enabled: Set<ColonyEvent.Kind>
    /// Hours before the event, for the kinds that take a lead (`takesLead`).
    var leadHours: [ColonyEvent.Kind: Int]
    /// Planets of this character the player muted.
    var muted: Set<Int64>

    static func enabledKey(_ kind: ColonyEvent.Kind) -> String { "planetary.notifications.\(kind.rawValue)" }
    static func leadKey(_ kind: ColonyEvent.Kind) -> String { "planetary.notifications.\(kind.rawValue).lead" }
    /// One string for all characters: `characterID-planetID` pairs, comma-separated.
    static let mutedKey = "planetary.notifications.muted"

    static func takesLead(_ kind: ColonyEvent.Kind) -> Bool {
        kind == .extractorsFinish || kind == .storageFull
    }

    static func load(characterID: Int64, defaults: UserDefaults = .standard) -> Self {
        var enabled: Set<ColonyEvent.Kind> = []
        var leads: [ColonyEvent.Kind: Int] = [:]
        for kind in ColonyEvent.Kind.allCases {
            if defaults.object(forKey: enabledKey(kind)) as? Bool ?? true { enabled.insert(kind) }
            if takesLead(kind) {
                leads[kind] = defaults.object(forKey: leadKey(kind)) as? Int ?? defaultLead
            }
        }
        return Self(enabled: enabled, leadHours: leads,
                    muted: mutedPlanets(defaults.string(forKey: mutedKey) ?? "", characterID: characterID))
    }

    static func mutedPlanets(_ stored: String, characterID: Int64) -> Set<Int64> {
        Set(stored.split(separator: ",").compactMap { pair -> Int64? in
            let parts = pair.split(separator: "-")
            guard parts.count == 2, Int64(parts[0]) == characterID else { return nil }
            return Int64(parts[1])
        })
    }

    /// `stored` with one planet of one character muted or not.
    static func setMuted(_ isMuted: Bool, planetID: Int64, characterID: Int64, in stored: String) -> String {
        var pairs = stored.split(separator: ",").map(String.init)
        let pair = "\(characterID)-\(planetID)"
        pairs.removeAll { $0 == pair }
        if isMuted { pairs.append(pair) }
        return pairs.joined(separator: ",")
    }
}

extension ColonyEvent.Kind: CaseIterable {
    nonisolated static var allCases: [Self] { [.extractorsFinish, .storageFull, .factoryStarved, .outputLost] }
}

/// One notification: an event of the schedule, put into words, at the moment it is due.
struct PlanetaryAlert: Identifiable, Hashable {
    var id: String
    var kind: ColonyEvent.Kind
    var planetID: Int64
    var pinID: Int64?
    /// When the notification goes off: the event, less the lead.
    var fireDate: Date
    var eventDate: Date
    var leadHours: Int
    /// `Launchpad full in 4 h`.
    var title: String
    /// `Osoggur IX · Launchpad · at 05:50` — the caps line on the screen.
    var detail: String
    var planetName: String
    /// The sentence of the notification itself.
    var body: String

    var route: PlanetaryRoute {
        if let pinID { .facility(planetID: planetID, pinID: pinID) } else { .colony(planetID: planetID) }
    }
}

enum PlanetaryNotifications {
    static let identifierPrefix = NotificationKind.planetary.prefix

    /// Every notification the report calls for under `settings`, soonest first. Events whose
    /// moment (less the lead) has passed are left out: the report is remade every few minutes,
    /// and each remake would otherwise deliver them again.
    static func plan(report: PlanetaryReport, settings: PlanetaryNotificationSettings,
                     now: Date = .now) -> [PlanetaryAlert] {
        var events: [ColonyEvent] = []
        // Output lost at one moment on one planet is one notification, whatever is lost.
        var lostIndex: [String: Int] = [:]
        var lostCommodities: [Int: [String]] = [:]
        for event in report.schedule
        where settings.enabled.contains(event.kind) && !settings.muted.contains(event.planetID) {
            if event.kind == .outputLost {
                let key = "\(event.planetID)-\(event.date.timeIntervalSince1970)"
                if let index = lostIndex[key] {
                    if let name = event.commodity?.name { lostCommodities[index, default: []].append(name) }
                    continue
                }
                lostIndex[key] = events.count
                lostCommodities[events.count] = event.commodity.map { [$0.name] } ?? []
            }
            events.append(event)
        }

        let alerts = events.enumerated().compactMap { index, event -> PlanetaryAlert? in
            let lead = settings.leadHours[event.kind] ?? 0
            let fireDate = event.date.addingTimeInterval(-TimeInterval(lead) * 3600)
            guard fireDate > now else { return nil }
            let colony = report.colony(planetID: event.planetID)
            let planet = colony?.planet.displayName ?? event.planetName ?? String(localized: "Planet \(event.planetID)")
            let at = EVETime.dateTime(event.date)
            var title: String
            var detail: String
            let body: String
            switch event.kind {
            case .extractorsFinish:
                title = event.count == 1
                    ? String(localized: "Extractor program ends")
                    : String(localized: "Extractors finish")
                detail = String(localized: "\(planet) · \(event.count) programs")
                body = String(localized: "\(planet): extractor programs end at \(at). Restart them in game; factories run dry soon after.")
            case .storageFull:
                let name = event.pinID.flatMap { pin in colony?.facilityName(pin) } ?? String(localized: "Storage")
                title = String(localized: "\(name) full")
                detail = "\(planet) · \(name)"
                body = String(localized: "\(planet): the \(name) is full at \(at). After that new output has nowhere to go and is lost.")
            case .factoryStarved:
                let name = event.pinID.flatMap { pin in colony?.producerName(pin) }
                    ?? event.commodity.map { String(localized: "\($0.name) factory") }
                    ?? String(localized: "Factory")
                title = String(localized: "\(name) starved")
                let wait = event.duration.map { String(localized: "waits \(EVETime.duration($0)) for input") }
                    ?? String(localized: "waits for input to the end")
                detail = "\(planet) · \(wait)"
                body = String(localized: "\(planet): the \(name) runs out of input at \(at) and \(wait).")
            case .outputLost:
                let lost = lostCommodities[index] ?? []
                title = String(localized: "Output lost")
                detail = lost.isEmpty ? planet : "\(planet) · \(lost.joined(separator: ", "))"
                body = lost.isEmpty
                    ? String(localized: "\(planet): output is lost from \(at). Make room for it in game.")
                    : String(localized: "\(planet): \(lost.joined(separator: ", ")) lost from \(at). Make room for it in game.")
            }
            if lead > 0 {
                title += " " + String(localized: "in \(lead) hours")
                detail += " · " + String(localized: "at \(EVETime.time(event.date))")
            }
            return PlanetaryAlert(id: event.id, kind: event.kind, planetID: event.planetID, pinID: event.pinID,
                                  fireDate: fireDate, eventDate: event.date, leadHours: lead, title: title,
                                  detail: detail, planetName: planet, body: body)
        }
        return alerts.sorted { ($0.fireDate, $0.id) < ($1.fireDate, $1.id) }
    }

    /// Replaces this character's pending notifications with the ones `report` calls for, through
    /// the app's one schedule (`LocalNotifications`): it serializes the replacements and shares
    /// iOS's pending budget fairly with the other kinds.
    static func reschedule(characterID: Int64, report: PlanetaryReport) {
        // The demo pilot's colonies are recorded; their timers notify nobody.
        guard !DemoIDs.contains(characterID) else { return }
        let alerts = plan(report: report, settings: .load(characterID: characterID))
        let prefix = NotificationKind.planetary.scope(characterID: characterID)
        let requests = alerts.map { alert in
            LocalNotificationRequest(id: prefix + alert.id, title: alert.title, body: alert.body,
                                     threadID: "\(prefix)\(alert.planetID)", fireDate: alert.fireDate)
        }
        LocalNotifications.shared.replace(scope: prefix, with: requests)
    }

    nonisolated static func isAllowed(_ status: UNAuthorizationStatus) -> Bool {
        LocalNotifications.isAllowed(status)
    }

    static func authorizationStatus() async -> UNAuthorizationStatus {
        await LocalNotifications.shared.refreshStatus()
    }

    /// Asks iOS once; `true` when notifications are allowed afterwards.
    static func requestAuthorization() async -> Bool {
        await LocalNotifications.shared.requestAuthorization()
    }
}
