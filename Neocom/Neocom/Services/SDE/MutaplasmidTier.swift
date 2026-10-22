import Foundation

/// The tier of a mutaplasmid, read from its English name: `Gravid` from
/// `Gravid Medium Armor Repairer Mutaplasmid`, `Glorified Unstable` from a glorified one.
///
/// The SDE has no tier column. The English name is used so the tier is the game's word in every
/// language; a name matching no pattern has no tier.
enum MutaplasmidTier {
    /// Ordered by widening ranges; `Radical` and `Exigent` are the drone and damage-amplifier tiers.
    private static let kinds = ["Decayed", "Gravid", "Unstable", "Radical", "Exigent"]
    private static let glorified = "Glorified"

    /// `Gravid`, `Glorified Gravid`, or `nil` for a name without a known tier.
    static func name(of englishName: String) -> String? {
        let words = englishName.split(separator: " ")
        guard let first = words.first else { return nil }
        if first == glorified, words.count > 1, kinds.contains(String(words[1])) {
            return "\(glorified) \(words[1])"
        }
        return kinds.contains(String(first)) ? String(first) : nil
    }

    /// The list order: plain tiers from narrowest to widest range, then glorified ones, then the rest.
    static func rank(of englishName: String) -> Int {
        guard let tier = name(of: englishName) else { return Int.max }
        let words = tier.split(separator: " ")
        let isGlorified = words.count > 1
        let kind = kinds.firstIndex(of: String(words.last ?? "")) ?? kinds.count
        return (isGlorified ? kinds.count : 0) + kind
    }
}

// The English name: `textEn` is empty in the English database, where `name` is English.
extension MutaplasmidRow {
    var tierSourceName: String { englishName.isEmpty ? name : englishName }
}

extension MutaplasmidNameRow {
    var tierSourceName: String { englishName.isEmpty ? name : englishName }
}
