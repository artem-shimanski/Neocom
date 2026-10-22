import SDEKit
import SwiftUI

/// The items of a list under a heading per meta tier: Tech I first, then Tech II, then the
/// faction, deadspace and officer tiers. Used by the database lists and the fitting pickers,
/// which bring their own row.
struct TypeListSections<RowContent: View>: View {
    let rows: [TypeListRow]
    var order: TypeListSection.Order = .ascending
    /// Whether a list that falls into a single tier still gets that tier's heading. The database
    /// screens say "Items" over such a list; a picker keeps the tier's name.
    var headsEverySection = false
    /// One row. The flag is `true` when the sections carry no tier headings, so the row states the
    /// tier under its name.
    @ViewBuilder var row: (TypeListRow, _ showsMetaGroup: Bool) -> RowContent

    var body: some View {
        let sections = TypeListSection.sections(of: rows, order: order)
        // One section is not a split: the meta group becomes a line under the name instead.
        let showsHeadings = headsEverySection || sections.count > 1
        ForEach(sections) { section in
            HUDListSection(section.rows, row: { row in
                self.row(row, !showsHeadings)
            }, header: {
                HUDSectionHeader(showsHeadings ? heading(of: section) : Text("Items · \(section.rows.count)"))
            })
        }
    }

    /// The tier's name and its count, untinted.
    private func heading(of section: TypeListSection) -> Text {
        Text("\(section.metaGroupName ?? String(localized: "Other")) · \(section.rows.count)")
    }
}

extension TypeListSections where RowContent == TypeListNavigationRow {
    init(rows: [TypeListRow]) {
        self.init(rows: rows) { row, showsMetaGroup in
            TypeListNavigationRow(row: row, showsMetaGroup: showsMetaGroup)
        }
    }
}

struct TypeListNavigationRow: View {
    let row: TypeListRow
    let showsMetaGroup: Bool

    var body: some View {
        NavigationLink(value: DatabaseRoute.type(row.id)) {
            HUDTypeRow(typeID: row.id,
                       name: row.name,
                       subtitle: showsMetaGroup ? row.metaGroupName.map { Text($0) } : nil)
        }
        .hudRowButton(HUDTypeRow.rowStyle)
        .hudTypeContextMenu(typeID: row.id, name: row.name)
    }
}

/// One meta tier of a list of items.
struct TypeListSection: Identifiable {
    let id: MetaGroupID?
    let metaGroupName: String?
    let rows: [TypeListRow]

    enum Order {
        /// The lowest tier first.
        case ascending
    }

    /// Splits a list of items into tiers, the lowest first unless `order` says otherwise. The split
    /// is by meta group, which has a name, while the order is by meta level. Rows keep their incoming
    /// order.
    static func sections(of rows: [TypeListRow], order: Order = .ascending) -> [TypeListSection] {
        Dictionary(grouping: rows, by: \.metaGroupID)
            .map { id, rows in
                TypeListSection(
                    id: id,
                    metaGroupName: rows.first?.metaGroupName,
                    rows: rows
                )
            }
            .sorted { $0.order < $1.order }
    }

    /// Lowest tier first, everything outside a meta group last. A section's level is the lowest one
    /// in it. The export leaves the meta level empty for much of the catalogue (ships among them);
    /// those sections fall back to the meta group id, which misorders only Officer and Deadspace.
    /// The id breaks ties, as Tech II and Storyline are both meta 5.
    private var order: (Int, Int, UInt16) {
        (id == nil ? 1 : 0, rows.compactMap(\.metaLevel).min() ?? .max, id?.rawValue ?? .max)
    }
}

/// How a meta group is written and tinted wherever it is drawn as a badge.
enum MetaTier {
    static let techI: MetaGroupID = 1

    /// The tier as a badge writes it. Tech I to III are `T1`, `T2`, `T3` by id, as the names are
    /// translated; other tiers are spelled out. `nil` for a type outside any meta group.
    static func badgeText(id: MetaGroupID?, name: String?) -> String? {
        switch id {
        case 1: "T1"
        case 2: "T2"
        case 14: "T3"
        default: name
        }
    }

    /// The tint CCP gives the tech level, stored as three components; a missing component leaves the
    /// label secondary.
    static func color(red: Double?, green: Double?, blue: Double?) -> Color? {
        guard let red, let green, let blue else { return nil }
        return Color(red: red, green: green, blue: blue)
    }

    /// What a badge is tinted with: the meta group's own colour, except Tech I, which uses the muted
    /// ink as its static data gold reads as a warning. `HUDMetaBadge` adjusts it for legibility
    /// without changing the hue.
    static func badgeColor(id: MetaGroupID?, red: Double?, green: Double?, blue: Double?) -> Color? {
        guard id != techI else { return nil }
        return color(red: red, green: green, blue: blue)
    }
}

extension TypeListRow {
    var metaBadgeText: String? {
        MetaTier.badgeText(id: metaGroupID, name: metaGroupName)
    }

    var metaBadgeColor: Color? {
        MetaTier.badgeColor(id: metaGroupID, red: metaColorRed, green: metaColorGreen, blue: metaColorBlue)
    }
}
