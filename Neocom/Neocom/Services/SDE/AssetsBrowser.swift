import LiteRow
import SDEKit

// Queries behind the Assets section.

/// A type as the asset rows need it. Group and category come from `AssetsBrowser.groups(_:)`;
/// one query for the whole chain would be too complex for the query builder's type-checker.
@Projection
struct AssetTypeRow: Sendable, Identifiable {
    var id: TypeID
    var name: String
    var groupID: GroupID
    /// m³ of one unit.
    var volume: Double?
    /// Cargo hold or container size, m³.
    var capacity: Double?
}

enum AssetsBrowser {
    /// Types for a set of ids. The caller chunks large sets: SQLite caps bound parameters per statement.
    static func types(_ types: [TypeID]) -> SQLQuery<AssetTypeRow> {
        TypeInfo.all()
            .join(NameRow.self) { type, name in type.nameID == name.id }
            .filter { type, _ in type.id.in(types) }
            .select { type, name in
                AssetTypeRow.projection(id: type.id, name: name.text, groupID: type.groupID,
                                        volume: type.volume, capacity: type.capacity)
            }
            .query()
    }

    /// Groups with their category, named.
    static func groups(_ groups: [GroupID]) -> SQLQuery<GroupHeader> {
        let withName = GroupInfo.all()
            .join(NameRow.self) { row, name in row.nameID == name.id }
        let withCategory = withName
            .join(CategoryInfo.self) { row, _, category in row.categoryID == category.id }
        let withCategoryName = withCategory
            .join(NameRow.self) { _, _, category, categoryName in category.nameID == categoryName.id }
        return withCategoryName
            .filter { row, _, _, _ in row.id.in(groups) }
            .select { row, name, category, categoryName in
                GroupHeader.projection(id: row.id, name: name.text, categoryID: category.id,
                                       categoryName: categoryName.text)
            }
            .query()
    }
}
