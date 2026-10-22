import KillmailKit
import SwiftUI
import ZKillKit

// What the zKillboard screens say about a search, in one place: the form's menus, the
// results header's filters line and its footnote name a kind, a period or a value the same way.

/// What the form's TYPE menu picks: a subject of some kind, or one killmail by its id.
enum ZKillboardSubjectMode: Hashable {
    case subject(KillboardSubjectKind)
    case killmailID

    static var allCases: [ZKillboardSubjectMode] {
        KillboardSubjectKind.allCases.map(ZKillboardSubjectMode.subject) + [.killmailID]
    }
}

enum ZKillboardText {
    static func title(of kind: KillboardSubjectKind) -> String {
        switch kind {
        case .character: String(localized: "Character")
        case .corporation: String(localized: "Corporation")
        case .alliance: String(localized: "Alliance")
        case .faction: String(localized: "Faction")
        case .shipType: String(localized: "Ship")
        case .shipGroup: String(localized: "Ship Group")
        case .solarSystem: String(localized: "System")
        case .constellation: String(localized: "Constellation")
        case .region: String(localized: "Region")
        }
    }

    static func title(of mode: ZKillboardSubjectMode) -> String {
        switch mode {
        case let .subject(kind): title(of: kind)
        case .killmailID: String(localized: "Killmail ID")
        }
    }

    /// `Choose a Ship`.
    static func choose(_ kind: KillboardSubjectKind) -> String {
        switch kind {
        case .character: String(localized: "Choose a Character")
        case .corporation: String(localized: "Choose a Corporation")
        case .alliance: String(localized: "Choose an Alliance")
        case .faction: String(localized: "Choose a Faction")
        case .shipType: String(localized: "Choose a Ship")
        case .shipGroup: String(localized: "Choose a Ship Group")
        case .solarSystem: String(localized: "Choose a System")
        case .constellation: String(localized: "Choose a Constellation")
        case .region: String(localized: "Choose a Region")
        }
    }

    /// The plate's glyph for a subject the image server has no picture of.
    static func symbol(of kind: KillboardSubjectKind) -> String {
        switch kind {
        case .character: "person"
        case .corporation, .faction: "building.2"
        case .alliance: "shield"
        case .shipType, .shipGroup: "square.stack.3d.up"
        case .solarSystem: "sun.max"
        case .constellation: "sparkles"
        case .region: "globe"
        }
    }

    static func title(of side: KillmailFilter) -> String {
        switch side {
        case .all: String(localized: "All")
        case .kills: String(localized: "Kills")
        case .losses: String(localized: "Losses")
        }
    }

    static func title(of space: KillboardSpace?) -> String {
        switch space {
        case nil: String(localized: "Any")
        case .highsec: String(localized: "Highsec")
        case .lowsec: String(localized: "Lowsec")
        case .nullsec: String(localized: "Nullsec")
        case .wormhole: String(localized: "W-Space")
        case .abyssal: String(localized: "Abyssal")
        }
    }

    static func title(of engagement: KillboardEngagement?) -> String {
        switch engagement {
        case nil: String(localized: "Any")
        case .solo: String(localized: "Solo")
        case .ganked: String(localized: "Ganked")
        }
    }

    /// The NPC and AWOX menus: `Any`, `Only`, `Excluded`.
    static func title(of inclusion: KillboardInclusion) -> String {
        switch inclusion {
        case .any: String(localized: "Any")
        case .only: String(localized: "Only")
        case .excluded: String(localized: "Excluded")
        }
    }

    static func title(of period: KillboardPeriod) -> String {
        switch period {
        case .any: String(localized: "Any Time")
        case .pastHour: String(localized: "Past Hour")
        case .pastDay: String(localized: "Past Day")
        case .pastWeek: String(localized: "Past Week")
        case let .month(year, month): monthTitle(year: year, month: month)
        }
    }

    /// `October 2026`, EVE time.
    static func monthTitle(year: Int, month: Int) -> String {
        guard let date = calendar.date(from: DateComponents(year: year, month: month, day: 1)) else {
            return "\(year).\(month)"
        }
        var style = Date.FormatStyle(date: .omitted, time: .omitted).month(.wide).year()
        style.timeZone = .gmt
        return date.formatted(style)
    }

    /// Gregorian, UTC: EVE time.
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        return calendar
    }()

    /// `500M`, `1B`, `Any`.
    static func title(ofMinimumValue value: Int64?) -> String {
        guard let value else { return String(localized: "Any") }
        if value >= 1_000_000_000, value % 1_000_000_000 == 0 { return "\(value / 1_000_000_000)B" }
        return "\(value / 1_000_000)M"
    }

    /// The results header's `All · Lowsec · Past Week`: every filter that is set, side first.
    static func summary(of criteria: KillboardCriteria) -> String {
        let hasSide = criteria.subject?.kind.hasSide ?? true
        var parts: [String] = []
        if hasSide { parts.append(title(of: criteria.side)) }
        if let space = criteria.space { parts.append(title(of: space)) }
        if let engagement = criteria.engagement { parts.append(title(of: engagement)) }
        switch criteria.npc {
        case .any: break
        case .only: parts.append(String(localized: "NPC only"))
        case .excluded: parts.append(String(localized: "No NPC"))
        }
        switch criteria.awox {
        case .any: break
        case .only: parts.append(String(localized: "AWOX only"))
        case .excluded: parts.append(String(localized: "No AWOX"))
        }
        if criteria.period != .any { parts.append(title(of: criteria.period)) }
        if let value = criteria.minimumValue {
            parts.append(String(localized: "≥ \(title(ofMinimumValue: value)) ISK"))
        }
        if hasSide, criteria.finalBlowOnly { parts.append(String(localized: "Final blow")) }
        return parts.isEmpty ? String(localized: "None") : parts.joined(separator: " · ")
    }

    /// What kill and loss mean for this subject — the results footnote's middle sentence.
    static func sides(of subject: KillboardSubject) -> String {
        let name = subject.name
        switch subject.kind {
        case .shipType:
            return String(localized: "A kill means a \(name) was among the attackers; a loss, that a \(name) was destroyed.")
        case .shipGroup:
            return String(localized: "A kill means a ship of \(name) was among the attackers; a loss, that one was destroyed.")
        case .character, .corporation, .alliance, .faction:
            return String(localized: "A kill means \(name) was among the attackers; a loss, that \(name) was the victim.")
        case .solarSystem, .constellation, .region:
            return String(localized: "Every killmail in \(name) is listed: a place has no kills or losses.")
        }
    }

    /// `22 points`, `1 point`.
    static func points(_ points: Int) -> String {
        String(localized: "\(points) points")
    }

    /// What a failed zKillboard request says.
    static func message(of failure: ZKillboardSheet.Failure) -> String {
        switch failure {
        case .busy:
            String(localized: "zKillboard is limiting requests right now (HTTP 429). Wait a minute, then try again.")
        case .notFound:
            String(localized: "zKillboard has no such killmail.")
        case let .failed(error):
            message(of: error)
        }
    }

    /// Anything else that failed, in words: zKillboard's own failures by case, the network's by
    /// URLSession's description.
    private static func message(of error: any Error) -> String {
        switch error {
        case let error as ZKillError:
            switch error {
            case let .invalidQuery(query):
                return message(of: query)
            case let .http(status, _) where status >= 500:
                return String(localized: "zKillboard is having trouble right now (HTTP \(status)). Try again in a little while.")
            case let .http(status, _):
                return String(localized: "zKillboard refused the request (HTTP \(status)).")
            case let .api(message):
                return String(localized: "zKillboard answered: \(message)")
            case .decoding, .invalidResponse:
                return String(localized: "zKillboard's answer could not be read. Try again in a little while.")
            case .notFound:
                return String(localized: "zKillboard has no such killmail.")
            }
        case let error as ZKillQueryError:
            return message(of: error)
        case let error as URLError:
            return error.localizedDescription
        default:
            return String(localized: "Something went wrong talking to zKillboard or EVE. Try again in a little while.")
        }
    }

    /// A search zKillboard would not take — the form keeps these out, so this is a safety net.
    private static func message(of error: ZKillQueryError) -> String {
        switch error {
        case .invalidPastSeconds, .invalidYear, .invalidMonth:
            String(localized: "zKillboard does not take this period.")
        case .invalidISKValue:
            String(localized: "zKillboard does not take this minimum value.")
        case .invalidPage:
            String(localized: "zKillboard serves no more pages for this search.")
        case .invalidID, .invalidLabel, .requiresEntity, .killIDMustStandAlone:
            String(localized: "zKillboard does not take this search.")
        }
    }
}
