// Who did it: the attackers by damage, their shares, the final blow.

import Foundation

/// One attacker as the report lists them.
public struct KillmailAttackerRow: Sendable, Hashable, Identifiable {
    /// The attacker's position in `Killmail.attackers`: attackers have no id of their own.
    public var index: Int
    public var attacker: KillmailAttacker
    /// `damage_done` over the victim's `damage_taken`, 0...1.
    public var share: Double
    public var isTopDamage: Bool

    public var id: Int { index }
    public var isFinalBlow: Bool { attacker.isFinalBlow }
}

/// `INVOLVED 5 · PILOTS 4 · NPC 1 · DAMAGE 9 897`.
public struct KillmailAttackerSummary: Sendable, Hashable {
    public var involved: Int
    public var pilots: Int
    public var npc: Int
    public var damage: Int64

    public init(involved: Int, pilots: Int, npc: Int, damage: Int64) {
        self.involved = involved
        self.pilots = pilots
        self.npc = npc
        self.damage = damage
    }
}

extension Killmail {
    /// Everyone involved, the final blow included.
    public var involvedCount: Int { attackers.count }

    /// One attacker alone.
    public var isSolo: Bool { attackers.count == 1 }

    public var finalBlow: KillmailAttacker? { attackers.first { $0.isFinalBlow } }

    /// The damage the shares are of: what the victim took, or — when ESI says 0 — what the
    /// attackers did between them.
    public var totalDamage: Int64 {
        victim.damageTaken > 0 ? victim.damageTaken : attackers.reduce(0) { $0 + max(0, $1.damageDone) }
    }

    /// `damage_done / damage_taken`, 0...1; 0 when there was no damage at all.
    public func damageShare(of attacker: KillmailAttacker) -> Double {
        let total = totalDamage
        guard total > 0 else { return 0 }
        return min(1, max(0, Double(attacker.damageDone) / Double(total)))
    }

    /// The attackers by damage, most first; on a tie the final blow, then pilots before NPCs,
    /// then ESI's order. Every attacker with the top damage (above 0) is `isTopDamage`.
    public var rankedAttackers: [KillmailAttackerRow] {
        let top = attackers.map(\.damageDone).max() ?? 0
        return attackers.enumerated()
            .sorted { lhs, rhs in
                let (l, r) = (lhs.element, rhs.element)
                if l.damageDone != r.damageDone { return l.damageDone > r.damageDone }
                if l.isFinalBlow != r.isFinalBlow { return l.isFinalBlow }
                if l.isNPC != r.isNPC { return !l.isNPC }
                return lhs.offset < rhs.offset
            }
            .map { offset, attacker in
                KillmailAttackerRow(index: offset, attacker: attacker, share: damageShare(of: attacker),
                                    isTopDamage: top > 0 && attacker.damageDone == top)
            }
    }

    /// What the report shows at the top: the final blow, then the top damage if it is someone
    /// else — two rows, filled up from the ranking when one attacker is both (so a killmail
    /// with two attackers shows them both); the rest is behind "All attackers".
    public var leadingAttackers: [KillmailAttackerRow] {
        let ranked = rankedAttackers
        var rows: [KillmailAttackerRow] = []
        if let finalBlow = ranked.first(where: \.isFinalBlow) { rows.append(finalBlow) }
        for row in ranked where rows.count < 2 && !rows.contains(where: { $0.index == row.index }) {
            rows.append(row)
        }
        return rows
    }

    public var attackerSummary: KillmailAttackerSummary {
        let npc = attackers.count(where: \.isNPC)
        return KillmailAttackerSummary(involved: attackers.count, pilots: attackers.count - npc, npc: npc,
                                       damage: totalDamage)
    }
}
