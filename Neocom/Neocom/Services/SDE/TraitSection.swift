import Foundation
import SDEKit

/// A block of ship bonuses as the game's Traits tab arranges it: one section per skill, then the
/// role bonuses, then the rest.
struct TraitSection: Identifiable {
    var id: String
    var kind: TraitKind
    var skillName: String?
    var lines: [TraitLine]

    static func sections(from rows: [TypeTraitRow]) -> [TraitSection] {
        func lines(_ rows: [TypeTraitRow]) -> [TraitLine] {
            rows.sorted { $0.index < $1.index }.map { TraitLine($0) }
        }
        let skillRows = Dictionary(grouping: rows.filter { $0.kind == .skill }, by: \.skillID)
        let skills = skillRows.values
            .sorted { ($0[0].skillName ?? "") < ($1[0].skillName ?? "") }
            .map { TraitSection(id: "skill/\($0[0].skillID.rawValue)", kind: .skill,
                                skillName: $0[0].skillName, lines: lines($0)) }
        let others = [TraitKind.role, .misc].compactMap { kind -> TraitSection? in
            let matching = rows.filter { $0.kind == kind }
            return matching.isEmpty ? nil : TraitSection(id: "kind/\(kind.rawValue)", kind: kind,
                                                         skillName: nil, lines: lines(matching))
        }
        return skills + others
    }
}

struct TraitLine: Identifiable {
    var id: String
    /// `5%`, `10 m`; `nil` for a line without a figure.
    var figure: String?
    var text: String

    init(_ row: TypeTraitRow) {
        id = row.id
        text = row.text
        figure = row.bonus.map { bonus in
            TypeAttributeRow(id: 0, name: "", displayName: nil, value: bonus, baseValue: bonus,
                             unitID: row.unitID, unitName: row.unitName,
                             categoryID: nil, categoryName: nil).formattedValue
        }
    }
}
