import Foundation
import TrainingKit

/// Notification preferences other than Planetary Interaction (`PlanetaryNotificationSettings`),
/// stored in `UserDefaults` and edited through `@AppStorage` on the same keys. Not cleared by
/// Clear Cached Data or sign-out.
nonisolated struct NotificationSettings: Sendable, Equatable {
    var skillTrained: Bool
    var queueEnding: Bool
    /// Hours before the queue's end, one of `TrainingReminders.leadChoices`.
    var queueLeadHours: Int
    var industry: Bool
    var contracts: Bool
    var orders: Bool
    var mail: Bool
    /// Industry, contracts and orders of the pilots' corporations, each also behind its own
    /// switch.
    var corporation: Bool
    /// Pilots excluded from training notifications.
    var mutedPilots: Set<Int64>

    static let skillTrainedKey = "notifications.training.skill"
    static let queueEndingKey = "notifications.training.queue"
    static let queueLeadKey = "notifications.training.queue.lead"
    static let industryKey = "notifications.industry"
    static let contractsKey = "notifications.contracts"
    static let ordersKey = "notifications.orders"
    static let mailKey = "notifications.mail"
    static let corporationKey = "notifications.corporation"
    /// Comma-separated character ids.
    static let mutedPilotsKey = "notifications.training.muted"

    static let defaultSkillTrained = true
    static let defaultQueueEnding = true
    static let defaultIndustry = true
    static let defaultContracts = true
    static let defaultOrders = false
    static let defaultMail = false
    static let defaultCorporation = false

    static func load(defaults: UserDefaults = .standard) -> Self {
        func flag(_ key: String, _ fallback: Bool) -> Bool { defaults.object(forKey: key) as? Bool ?? fallback }
        return Self(skillTrained: flag(skillTrainedKey, defaultSkillTrained),
                    queueEnding: flag(queueEndingKey, defaultQueueEnding),
                    queueLeadHours: defaults.object(forKey: queueLeadKey) as? Int ?? TrainingReminders.defaultLead,
                    industry: flag(industryKey, defaultIndustry),
                    contracts: flag(contractsKey, defaultContracts),
                    orders: flag(ordersKey, defaultOrders),
                    mail: flag(mailKey, defaultMail),
                    corporation: flag(corporationKey, defaultCorporation),
                    mutedPilots: mutedPilots(defaults.string(forKey: mutedPilotsKey) ?? ""))
    }

    func trainsAlerts(for characterID: Int64) -> Bool {
        (skillTrained || queueEnding) && !mutedPilots.contains(characterID)
    }

    var corporationIndustry: Bool { corporation && industry }
    var corporationContracts: Bool { corporation && contracts }
    var corporationOrders: Bool { corporation && orders }
    var corporationAny: Bool { corporationIndustry || corporationContracts || corporationOrders }

    /// Whether any enabled kind needs a background check: those detected only by polling, and
    /// scheduled ones whose times shift. A corporation kind is on only with its personal
    /// switch, which counts already.
    var needsBackgroundCheck: Bool {
        orders || mail || contracts || industry || skillTrained || queueEnding
    }

    static func mutedPilots(_ stored: String) -> Set<Int64> {
        Set(stored.split(separator: ",").compactMap { Int64($0) })
    }

    /// `stored` with one pilot muted or unmuted.
    static func setMuted(_ isMuted: Bool, characterID: Int64, in stored: String) -> String {
        var ids = stored.split(separator: ",").map(String.init)
        ids.removeAll { $0 == String(characterID) }
        if isMuted { ids.append(String(characterID)) }
        return ids.joined(separator: ",")
    }
}
