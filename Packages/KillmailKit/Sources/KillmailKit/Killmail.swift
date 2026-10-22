// A killmail as plain data: what `GET /killmails/{id}/{hash}` reports, independent of the
// generated ESI types. A killmail is immutable once written.

import Foundation

/// What `GET /characters/{id}/killmails/recent` lists: the id, and the hash that opens the
/// killmail on the public `GET /killmails/{id}/{hash}`. A mail's `killReport:ID:HASH` link
/// carries the same pair.
public struct KillmailRef: Codable, Sendable, Hashable, Identifiable {
    public var id: Int64
    public var hash: String

    public init(id: Int64, hash: String) {
        self.id = id
        self.hash = hash
    }
}

/// One killmail.
public struct Killmail: Codable, Sendable, Hashable, Identifiable {
    public var id: Int64
    public var hash: String
    public var time: Date
    public var solarSystemID: Int64
    public var moonID: Int64?
    public var warID: Int64?
    public var victim: KillmailVictim
    /// In the order ESI lists them; `rankedAttackers` orders them by damage.
    public var attackers: [KillmailAttacker]

    public init(id: Int64, hash: String, time: Date, solarSystemID: Int64, moonID: Int64? = nil, warID: Int64? = nil,
                victim: KillmailVictim, attackers: [KillmailAttacker]) {
        self.id = id
        self.hash = hash
        self.time = time
        self.solarSystemID = solarSystemID
        self.moonID = moonID
        self.warID = warID
        self.victim = victim
        self.attackers = attackers
    }

    public var ref: KillmailRef { KillmailRef(id: id, hash: hash) }
}

/// The ship that died and who flew it. A structure or a deployable has no character.
public struct KillmailVictim: Codable, Sendable, Hashable {
    public var characterID: Int64?
    public var corporationID: Int64?
    public var allianceID: Int64?
    public var factionID: Int64?
    public var shipTypeID: Int64
    public var damageTaken: Int64
    /// Top-level items; a container's contents are in its `items`.
    public var items: [KillmailItem]

    public init(characterID: Int64? = nil, corporationID: Int64? = nil, allianceID: Int64? = nil, factionID: Int64? = nil,
                shipTypeID: Int64, damageTaken: Int64, items: [KillmailItem] = []) {
        self.characterID = characterID
        self.corporationID = corporationID
        self.allianceID = allianceID
        self.factionID = factionID
        self.shipTypeID = shipTypeID
        self.damageTaken = damageTaken
        self.items = items
    }
}

/// One stack on the victim's ship: fitted, loaded, in a bay, or inside a container. A stack
/// can split: part of it destroyed, part dropped into the wreck.
public struct KillmailItem: Codable, Sendable, Hashable {
    public var typeID: Int64
    /// The inventory flag: which slot, bay or hold (see `KillmailSection`).
    public var flag: Int64
    public var quantityDestroyed: Int64
    public var quantityDropped: Int64
    /// ESI's `singleton`: 2 marks a blueprint copy.
    public var singleton: Int64
    /// The contents, for a container.
    public var items: [KillmailItem]

    public init(typeID: Int64, flag: Int64, destroyed: Int64 = 0, dropped: Int64 = 0, singleton: Int64 = 0,
                items: [KillmailItem] = []) {
        self.typeID = typeID
        self.flag = flag
        quantityDestroyed = destroyed
        quantityDropped = dropped
        self.singleton = singleton
        self.items = items
    }

    public var quantity: Int64 { quantityDestroyed + quantityDropped }

    /// A blueprint copy: priced at nothing — the average price is the original's.
    public var isBlueprintCopy: Bool { singleton == 2 }
}

/// One of those who damaged the victim, or landed the final blow. An NPC has no character —
/// only a corporation or a faction, and a "ship" that is the NPC's own type.
public struct KillmailAttacker: Codable, Sendable, Hashable {
    public var characterID: Int64?
    public var corporationID: Int64?
    public var allianceID: Int64?
    public var factionID: Int64?
    public var shipTypeID: Int64?
    public var weaponTypeID: Int64?
    public var damageDone: Int64
    public var isFinalBlow: Bool
    public var securityStatus: Double

    public init(characterID: Int64? = nil, corporationID: Int64? = nil, allianceID: Int64? = nil, factionID: Int64? = nil,
                shipTypeID: Int64? = nil, weaponTypeID: Int64? = nil, damageDone: Int64, isFinalBlow: Bool = false,
                securityStatus: Double = 0) {
        self.characterID = characterID
        self.corporationID = corporationID
        self.allianceID = allianceID
        self.factionID = factionID
        self.shipTypeID = shipTypeID
        self.weaponTypeID = weaponTypeID
        self.damageDone = damageDone
        self.isFinalBlow = isFinalBlow
        self.securityStatus = securityStatus
    }

    /// No character: an NPC (or a structure's guns).
    public var isNPC: Bool { characterID == nil }

    /// The weapon worth showing next to the ship: `nil` when there is none, or when ESI
    /// recorded the ship itself as the weapon (`weapon_type_id == ship_type_id`).
    public var separateWeaponTypeID: Int64? {
        guard let weaponTypeID, weaponTypeID != shipTypeID else { return nil }
        return weaponTypeID
    }
}

/// Whether a killmail is the pilot's kill or loss.
public enum KillmailSide: String, Codable, Sendable, Hashable, CaseIterable {
    case kill
    case loss
}

extension Killmail {
    /// A loss when the pilot is the victim, a kill otherwise — `/killmails/recent` lists only
    /// killmails the pilot is on, as the victim or among the attackers.
    public func side(for pilotID: Int64) -> KillmailSide {
        victim.characterID == pilotID ? .loss : .kill
    }

    /// Capsule type ids: the plain capsule and the Genolution one. A capsule has no fit.
    public static let capsuleTypeIDs: Set<Int64> = [670, 33328]

    public var isCapsule: Bool { Self.capsuleTypeIDs.contains(victim.shipTypeID) }

    /// Every id the killmail names someone by: victim and attackers, characters, corporations,
    /// alliances and factions.
    public var nameableIDs: Set<Int64> {
        var ids = victim.nameableIDs
        for attacker in attackers {
            ids.formUnion([attacker.characterID, attacker.corporationID, attacker.allianceID, attacker.factionID]
                .compactMap { $0 })
        }
        return ids
    }

    /// What a list row names: the victim, and who landed the final blow.
    public var listNameableIDs: Set<Int64> {
        var ids = victim.nameableIDs
        if let finalBlow {
            ids.formUnion([finalBlow.characterID, finalBlow.corporationID, finalBlow.allianceID, finalBlow.factionID]
                .compactMap { $0 })
        }
        return ids
    }
}

extension KillmailVictim {
    var nameableIDs: Set<Int64> {
        Set([characterID, corporationID, allianceID, factionID].compactMap { $0 })
    }
}
