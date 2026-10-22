import KillmailKit
import LiteRow
import LiteRowUI
import SDEKit
import SwiftUI

// What the Killmails screens — and a mail's kill report card — say about a killmail, in one
// place: a list row, the report, the attackers and the card print a side, a value, a name or a
// place the same way.

enum KillmailText {
    static func title(of side: KillmailSide) -> String {
        switch side {
        case .kill: String(localized: "Kill")
        case .loss: String(localized: "Loss")
        }
    }

    /// A kill in `accent`, a loss in `danger`.
    static func color(of side: KillmailSide) -> Color {
        switch side {
        case .kill: .hudAccent
        case .loss: .hudDanger
        }
    }

    /// The pilot's part in a killmail: a loss as the victim, a kill among the attackers, and
    /// `nil` on a killmail the pilot is not on (one a mail links to).
    static func side(of killmail: Killmail, pilotID: Int64?) -> KillmailSide? {
        guard let pilotID else { return nil }
        if killmail.victim.characterID == pilotID { return .loss }
        return killmail.attackers.contains { $0.characterID == pilotID } ? .kill : nil
    }

    /// `36.76M`, the estimate without its unit.
    static func isk(_ value: Double) -> String { ISK.compact(value) }

    /// `9 897`.
    static func figure(_ value: Int64) -> String { value.formatted(.number) }

    /// `SOLO`, `5 INVOLVED`.
    static func involved(_ killmail: Killmail) -> String {
        killmail.isSolo ? String(localized: "Solo") : String(localized: "\(killmail.involvedCount) involved")
    }

    /// `39.3%`.
    static func share(_ value: Double) -> String {
        value.formatted(.percent.precision(.fractionLength(1)))
    }

    /// A character's security status, signed: `+3.9`, `-2.3`.
    static func security(_ value: Double) -> String {
        SecurityStatus.string(value, signed: true)
    }

    /// A character's security: positive green, outlaw (-5 and under) red, the rest of the
    /// negatives amber, zero muted.
    static func securityColor(_ value: Double) -> Color {
        if value > 0 { return .hudOk }
        if value <= -5 { return .hudDanger }
        if value < 0 { return .hudWarn }
        return .hudInkMuted
    }

    static func zKillboard(killID: Int64) -> URL? {
        URL(string: "https://zkillboard.com/kill/\(killID)/")
    }

    static func sectionTitle(_ section: KillmailSection) -> String {
        switch section {
        case .high: String(localized: "High Slots")
        case .medium: String(localized: "Medium Slots")
        case .low: String(localized: "Low Slots")
        case .rig: String(localized: "Rigs")
        case .subsystem: String(localized: "Subsystems")
        case .service: String(localized: "Service Slots")
        case .droneBay: String(localized: "Drone Bay")
        case .fighterBay: String(localized: "Fighter Bay")
        case .cargo: String(localized: "Cargo")
        case .implant: String(localized: "Implants")
        case .other: String(localized: "Other")
        }
    }

    /// `4/4` for a rack whose slots are known, `4 TYPES` for a bay of drones, `4 IMPLANTS`,
    /// `4 ITEMS`.
    static func sectionCount(_ group: KillmailItemGroup, slots: Int?) -> String {
        switch group.section {
        case .high, .medium, .low, .rig, .subsystem, .service:
            if let slots, slots >= group.topLevelCount { return "\(group.topLevelCount)/\(slots)" }
            return "\(group.topLevelCount)"
        case .droneBay, .fighterBay:
            return String(localized: "\(group.rows.count) types")
        case .implant:
            return String(localized: "\(group.rows.count) implants")
        default:
            return String(localized: "\(group.rows.count) items")
        }
    }
}

/// The names a killmail is shown with: the ones its snapshot brought, then whatever the sheet
/// has named before.
struct KillmailNaming {
    var names: [Int64: ESIEntityName]
    var sheet: KillmailsSheet?

    func name(of id: Int64?) -> String? {
        guard let id else { return nil }
        return names[id]?.name ?? sheet?.name(of: id)
    }

    /// The victim: the pilot, or — for a structure or a deployable — the corporation.
    func victim(of killmail: Killmail) -> String {
        name(of: killmail.victim.characterID) ?? name(of: killmail.victim.corporationID)
            ?? String(localized: "Unknown")
    }

    /// `Corporation · Alliance`, with no tickers: there is no owner of `/corporations/{id}`.
    func organization(corporationID: Int64?, allianceID: Int64?, factionID: Int64?) -> String {
        [name(of: corporationID), name(of: allianceID), name(of: factionID)].compactMap { $0 }
            .joined(separator: " · ")
    }

    /// A pilot by name; an NPC by its corporation or faction, or the type it is.
    func attacker(_ attacker: KillmailAttacker, statics: KillmailStatics) -> String {
        if let characterID = attacker.characterID {
            return name(of: characterID) ?? String(localized: "Unknown Pilot")
        }
        return name(of: attacker.corporationID) ?? name(of: attacker.factionID)
            ?? statics.typeName(attacker.shipTypeID) ?? String(localized: "Unknown")
    }
}

// MARK: - Static data

/// The SDE rows the killmail screens look up: systems with their region, types, and — for the
/// report's item rows — their groups.
struct KillmailStatics {
    var systems: [Int64: MarketSystemRow] = [:]
    var types: [Int64: AssetTypeRow] = [:]
    var groups: [GroupID: GroupHeader] = [:]

    func system(_ id: Int64) -> MarketSystemRow? { systems[id] }

    func typeName(_ id: Int64?) -> String? {
        id.flatMap { types[$0]?.name }
    }

    func groupName(ofType id: Int64) -> String? {
        types[id].flatMap { groups[$0.groupID]?.name }
    }

    /// `KAMELA 0.4`, with `details` after it: the region, `SOLO`.
    func placeLine(_ systemID: Int64, details: [String?]) -> Text? {
        let system = systems[systemID]
        return HUDPlaceBlock.line(systemName: system?.name, security: system?.securityStatus, details: details)
    }
}

/// Reads systems and types — and with `groups`, the types' groups — out of the SDE and hands
/// them over as `KillmailStatics`.
struct KillmailStaticsReader<Content: View>: View {
    @LiteQuery private var systemRows: [MarketSystemRow]
    @LiteQuery private var typeRows: [AssetTypeRow]
    private let withGroups: Bool
    private let content: (KillmailStatics) -> Content

    init(systemIDs: some Sequence<Int64>, typeIDs: some Sequence<Int64>, groups: Bool = false,
         @ViewBuilder content: @escaping (KillmailStatics) -> Content) {
        self.content = content
        withGroups = groups
        let systems = Array(Set(systemIDs)).sorted().map(MarketFormat.systemID)
        let types = Array(Set(typeIDs)).sorted().map { TypeID(rawValue: UInt32(clamping: $0)) }
        _systemRows = LiteQuery(systems.isEmpty ? nil : MarketBrowser.systems(systems))
        _typeRows = LiteQuery(types.isEmpty ? nil : AssetsBrowser.types(types))
    }

    var body: some View {
        let statics = KillmailStatics(
            systems: Dictionary(systemRows.map { (Int64($0.id.rawValue), $0) }, uniquingKeysWith: { first, _ in first }),
            types: Dictionary(typeRows.map { (Int64($0.id.rawValue), $0) }, uniquingKeysWith: { first, _ in first }))
        if withGroups {
            KillmailGroupsReader(statics: statics, content: content)
        } else {
            content(statics)
        }
    }
}

/// The second step of `KillmailStaticsReader`: the groups of the types the first one read.
private struct KillmailGroupsReader<Content: View>: View {
    let statics: KillmailStatics
    let content: (KillmailStatics) -> Content
    @LiteQuery private var groupRows: [GroupHeader]

    init(statics: KillmailStatics, content: @escaping (KillmailStatics) -> Content) {
        self.statics = statics
        self.content = content
        let groups = Array(Set(statics.types.values.map(\.groupID))).sorted { $0.rawValue < $1.rawValue }
        _groupRows = LiteQuery(groups.isEmpty ? nil : AssetsBrowser.groups(groups))
    }

    var body: some View {
        var statics = statics
        statics.groups = Dictionary(groupRows.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return content(statics)
    }
}

extension Killmail {
    /// Every type the report names: the hull, every item (containers' contents too), and the
    /// attackers' ships and weapons.
    var reportTypeIDs: Set<Int64> {
        var ids: Set<Int64> = [victim.shipTypeID]
        func add(_ items: [KillmailItem]) {
            for item in items {
                ids.insert(item.typeID)
                add(item.items)
            }
        }
        add(victim.items)
        for attacker in attackers {
            if let ship = attacker.shipTypeID { ids.insert(ship) }
            if let weapon = attacker.weaponTypeID { ids.insert(weapon) }
        }
        return ids
    }
}
