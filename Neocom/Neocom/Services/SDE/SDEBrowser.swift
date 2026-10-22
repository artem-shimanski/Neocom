import LiteRow
import SDEKit

// Rows of the database browser: one projection per screen. Cells combine tables of the main file
// with strings from the attached language file.

@Projection
struct CategoryListRow: Sendable, Identifiable {
    var id: CategoryID
    var name: String
    /// Published types below this category; empty categories are excluded.
    var typeCount: Int
}

@Projection
struct GroupListRow: Sendable, Identifiable {
    var id: GroupID
    var name: String
    var typeCount: Int
}

/// A node of the market tree, at any level from a root ("Ships") to a leaf group ("Assault Frigates").
@Projection
struct MarketGroupListRow: Sendable, Identifiable {
    var id: MarketGroupID
    var name: String
    /// Published types anywhere below, including the group's own.
    var typeCount: Int
    /// The group's icon in `iconImages`; not every group has one, nor every icon a picture.
    var iconID: IconID?
}

@Projection
struct TypeListRow: Sendable, Identifiable {
    var id: TypeID
    var name: String
    /// The meta group of the item, which is also its list section. `nil` for types outside any.
    var metaGroupID: MetaGroupID?
    /// Tech level badge: "Tech II", "Faction", … `nil` for types outside any meta group.
    var metaGroupName: String?
    /// The item's tier, which orders the list sections. Differs from the meta group id, which
    /// follows creation order (Officer before Deadspace). Empty for many types.
    var metaLevel: Int?
    /// The badge colour as three components, as stored in the database.
    var metaColorRed: Double?
    var metaColorGreen: Double?
    var metaColorBlue: Double?
    /// CPU in teraflops and power grid in megawatts the item needs before skills or bonuses, from
    /// `dogmaItems`. Only the fitting picker's queries fill them; the database screens leave
    /// them `nil`, as does an item without such needs.
    var cpu: Double?
    var power: Double?
    /// Drone bay volume in m³ and bandwidth in Mbit/s of one drone, from `dogmaItems`; filled by
    /// the fitting picker only, like `cpu` and `power`.
    var volume: Double?
    var droneBandwidth: Double?
}

@Projection
struct TypeSearchRow: Sendable, Identifiable {
    var id: TypeID
    var name: String
    var groupID: GroupID
    var groupName: String
}

/// Everything the type screen shows above its attributes.
///
/// Group and category are a separate query, `header(ofGroup:)`: six joins in one chain exceed the
/// type-checker.
@Projection
struct TypeSummary: Sendable, Identifiable {
    var id: TypeID
    var name: String
    /// Raw SDE markup (`<br>`, `<b>`, `<a href=showinfo:…>`), converted by `EVEMarkup`.
    var descriptionText: String?
    var groupID: GroupID
    var metaGroupID: MetaGroupID?
    var metaGroupName: String?
    /// The meta group colour as three components, as in `TypeListRow`.
    var metaColorRed: Double?
    var metaColorGreen: Double?
    var metaColorBlue: Double?
    /// The type's market tree node; `nil` for types not traded on the market.
    var marketGroupID: MarketGroupID?
}

extension TypeSummary {
    var isOnMarket: Bool { marketGroupID != nil }
}

/// A group with its category: the heading of the type list and the type screen.
@Projection
struct GroupHeader: Sendable, Identifiable {
    var id: GroupID
    var name: String
    var categoryID: CategoryID
    var categoryName: String
}

@Projection
struct CategoryHeader: Sendable, Identifiable {
    var id: CategoryID
    var name: String
}

@Projection
struct MarketGroupHeader: Sendable, Identifiable {
    var id: MarketGroupID
    var name: String
    /// The icon inherited by sub-groups without one of their own.
    var iconID: IconID?
}

/// One row of the attributes list.
///
/// `displayName` is the localized name and is missing for some attributes; `name` is the internal
/// one (`shipModuleRemoteArmorRepairer`) and serves as the fallback.
@Projection
struct TypeAttributeRow: Sendable, Identifiable {
    var id: AttributeID
    var name: String
    var displayName: String?
    var value: Double
    /// The type's own SDE value, kept next to `value` when a fit replaces it. The query reads the
    /// same column twice, so both are equal on output.
    var baseValue: Double
    var unitID: UnitID?
    /// Localized unit suffix ("m", "%", "HP"); not every unit has one.
    var unitName: String?
    var categoryID: AttributeCategoryID?
    /// Not localized; attribute categories only have an English name.
    var categoryName: String?
}

// MARK: - Attributes that hold a reference
//
// `requiredSkill1` holds a type id, `canFitShipGroup01` a group id and `maxGroupActive` an
// attribute id, all in the same `REAL` column as other values. SQLite joins `REAL` to `INTEGER`
// keys numerically, but the query builder compares Swift types, so `Expression<Double>` cannot
// meet `Expression<TypeID>`.
//
// Three more models over `typeAttributes`, one per kind of id, type the value column as the id.
// They are for joins and filters only and are never decoded.

@Table("typeAttributes")
struct TypeAttributeAsTypeReference {
    @PrimaryKey var typeID: TypeID
    @PrimaryKey var attributeID: AttributeID
    var value: TypeID = 0
}

@Table("typeAttributes")
struct TypeAttributeAsGroupReference {
    @PrimaryKey var typeID: TypeID
    @PrimaryKey var attributeID: AttributeID
    var value: GroupID = 0
}

@Table("typeAttributes")
struct TypeAttributeAsAttributeReference {
    @PrimaryKey var typeID: TypeID
    @PrimaryKey var attributeID: AttributeID
    var value: AttributeID = 0
}

/// A name resolved for an attribute whose value is a reference.
@Projection
struct TypeReference: Sendable, Identifiable {
    var id: TypeID
    var name: String
}

@Projection
struct GroupReference: Sendable, Identifiable {
    var id: GroupID
    var name: String
}

@Projection
struct AttributeReference: Sendable, Identifiable {
    var id: AttributeID
    var name: String
    var displayName: String?
}

// MARK: - Required skills

/// One direct skill requirement of an item: the skill and its level.
@Projection
struct RequiredSkillRow: Sendable, Identifiable {
    var id: TypeID
    var level: Int
}

/// The name of one type, looked up by id.
@Projection
struct TypeNameRow: Sendable, Identifiable {
    var id: TypeID
    var name: String
}

/// Queries behind the Database and Market sections.
///
/// Built outside the views because `@LiteQuery` treats the query as the identity of a fetch, so it
/// has to be an argument of the view.
enum SDEBrowser {

    // MARK: - Browsing

    /// Published categories that contain published types. The type count is the aggregate the
    /// `HAVING` uses to drop empty categories.
    static func categories() -> SQLQuery<CategoryListRow> {
        // One join per statement: growing the type pack and destructuring it in the same expression
        // hits swiftlang/swift#78725.
        let withName = CategoryInfo.all()
            .join(NameRow.self) { category, name in category.nameID == name.id }
        let withGroup = withName
            .leftJoin(GroupInfo.self) { category, _, group in
                group.categoryID == category.id && group.published == true
            }
        let withType = withGroup
            .leftJoin(TypeInfo.self) { _, _, group, type in
                type.groupID == group.id && type.published == true
            }
        return withType
            .filter { category, _, _, _ in category.published == true }
            .group(by: { category, _, _, _ in category.id })
            .having { _, _, _, type in type.id.count() > 0 }
            .select { category, name, _, type in
                CategoryListRow.projection(
                    id: category.id,
                    name: name.text,
                    typeCount: type.id.count()
                )
            }
            .order(by: { _, name, _, _ in name.ordinal })
            .query()
    }

    static func groups(inCategory category: CategoryID) -> SQLQuery<GroupListRow> {
        let withName = GroupInfo.all()
            .join(NameRow.self) { group, name in group.nameID == name.id }
        let withType = withName
            .leftJoin(TypeInfo.self) { group, _, type in
                type.groupID == group.id && type.published == true
            }
        return withType
            .filter { group, _, _ in group.categoryID == category && group.published == true }
            .group(by: { group, _, _ in group.id })
            .having { _, _, type in type.id.count() > 0 }
            .select { group, name, type in
                GroupListRow.projection(
                    id: group.id,
                    name: name.text,
                    typeCount: type.id.count()
                )
            }
            .order(by: { _, name, _ in name.ordinal })
            .query()
    }

    /// Everything published in one group, in the alphabet of the current language.
    ///
    /// Sorted by `ordinal`: text `ORDER BY` is `BINARY` or `NOCASE`, wrong outside English.
    static func types(inGroup group: GroupID) -> SQLQuery<TypeListRow> {
        let withName = TypeInfo.all()
            .join(NameRow.self) { type, name in type.nameID == name.id }
        let withMeta = withName
            .leftJoin(MetaGroupInfo.self) { type, _, meta in type.metaGroupID == meta.id }
        let withMetaName = withMeta
            .leftJoin(NameRow.self) { _, _, meta, metaName in meta.nameID == metaName.id }
        return withMetaName
            .filter { type, _, _, _ in type.groupID == group && type.published == true }
            .select { type, name, meta, metaName in typeListRow(type, name, meta, metaName) }
            .order(by: { _, name, _, _ in name.ordinal })
            .query()
    }

    // MARK: - Market tree

    /// Market groups directly under `parent`, or the roots of the tree when it is `nil`.
    ///
    /// The count covers the whole subtree, since groups such as "Ship Equipment" hold nothing
    /// directly. `marketGroupTree` makes that a join and includes the depth-0 row, so a group counts
    /// its own types too.
    ///
    /// The `HAVING` drops subtrees without published types; market groups have no `published` flag.
    static func marketGroups(inParent parent: MarketGroupID?) -> SQLQuery<MarketGroupListRow> {
        let withName = MarketGroupInfo.all()
            .join(NameRow.self) { group, name in group.nameID == name.id }
        let withTree = withName
            .join(MarketGroupTree.self) { group, _, tree in tree.ancestorID == group.id }
        let withType = withTree
            .leftJoin(TypeInfo.self) { _, _, tree, type in
                type.marketGroupID == tree.descendantID && type.published == true
            }
        return withType
            // Comparing to a `nil` parent produces `IS NULL`, which selects the roots.
            .filter { group, _, _, _ in group.parentID == parent }
            .group(by: { group, _, _, _ in group.id })
            .having { _, _, _, type in type.id.count() > 0 }
            .select { group, name, _, type in
                MarketGroupListRow.projection(
                    id: group.id,
                    name: name.text,
                    typeCount: type.id.count(),
                    iconID: group.iconID
                )
            }
            .order(by: { _, name, _, _ in name.ordinal })
            .query()
    }

    /// Types filed directly on one market group, not in its subtree.
    static func types(inMarketGroup group: MarketGroupID) -> SQLQuery<TypeListRow> {
        let withName = TypeInfo.all()
            .join(NameRow.self) { type, name in type.nameID == name.id }
        let withMeta = withName
            .leftJoin(MetaGroupInfo.self) { type, _, meta in type.metaGroupID == meta.id }
        let withMetaName = withMeta
            .leftJoin(NameRow.self) { _, _, meta, metaName in meta.nameID == metaName.id }
        return withMetaName
            .filter { type, _, _, _ in type.marketGroupID == group && type.published == true }
            .select { type, name, meta, metaName in typeListRow(type, name, meta, metaName) }
            .order(by: { _, name, _, _ in name.ordinal })
            .query()
    }

    // MARK: - Search

    /// Name search across the whole catalogue in the current language and English at once,
    /// ordered by relevance.
    ///
    /// Both columns sit in one fts5 index in the language file; `SDEDatabase.searchRanking`
    /// weighs the native column above English. Covers types the market tree cannot reach.
    static func search(
        _ pattern: FTS5Pattern,
        limit: Int = 100
    ) -> SQLQuery<TypeSearchRow> {
        let withType = NameSearchIndex.all()
            .join(TypeInfo.self) { fts, type in fts.rowID(as: NameID.self) == type.nameID }
        let withName = withType
            .join(NameRow.self) { _, type, name in type.nameID == name.id }
        let withGroup = withName
            .join(GroupInfo.self) { _, type, _, group in type.groupID == group.id }
        let withGroupName = withGroup
            .join(NameRow.self) { _, _, _, group, groupName in group.nameID == groupName.id }
        return withGroupName
            .filter { fts, _, _, _, _ in
                fts.match(pattern) && fts.ranked(by: SDEDatabase.searchRanking)
            }
            .filter { _, type, _, _, _ in type.published == true }
            .select { _, type, name, group, groupName in
                TypeSearchRow.projection(
                    id: type.id,
                    name: name.text,
                    groupID: group.id,
                    groupName: groupName.text
                )
            }
            .order(by: { fts, _, _, _, _ in fts.rank })
            .limit(limit)
            .query()
    }

    // MARK: - One type

    static func summary(of type: TypeID) -> SQLQuery<TypeSummary> {
        let withName = TypeInfo.all()
            .join(NameRow.self) { row, name in row.nameID == name.id }
        let withDescription = withName
            .leftJoin(DescriptionRow.self) { row, _, text in row.descriptionID == text.id }
        let withMeta = withDescription
            .leftJoin(MetaGroupInfo.self) { row, _, _, meta in row.metaGroupID == meta.id }
        let withMetaName = withMeta
            .leftJoin(NameRow.self) { _, _, _, meta, metaName in meta.nameID == metaName.id }
        return withMetaName
            .filter { row, _, _, _, _ in row.id == type }
            .select { row, name, text, meta, metaName in
                TypeSummary.projection(
                    id: row.id,
                    name: name.text,
                    descriptionText: text.text,
                    groupID: row.groupID,
                    metaGroupID: row.metaGroupID,
                    metaGroupName: metaName.text,
                    metaColorRed: meta.colorR,
                    metaColorGreen: meta.colorG,
                    metaColorBlue: meta.colorB,
                    marketGroupID: row.marketGroupID
                )
            }
            .limit(1)
            .query()
    }

    static func header(ofGroup group: GroupID) -> SQLQuery<GroupHeader> {
        let withName = GroupInfo.all()
            .join(NameRow.self) { row, name in row.nameID == name.id }
        let withCategory = withName
            .join(CategoryInfo.self) { row, _, category in row.categoryID == category.id }
        let withCategoryName = withCategory
            .join(NameRow.self) { _, _, category, categoryName in category.nameID == categoryName.id }
        return withCategoryName
            .filter { row, _, _, _ in row.id == group }
            .select { row, name, category, categoryName in
                GroupHeader.projection(
                    id: row.id,
                    name: name.text,
                    categoryID: category.id,
                    categoryName: categoryName.text
                )
            }
            .limit(1)
            .query()
    }

    static func header(ofCategory category: CategoryID) -> SQLQuery<CategoryHeader> {
        CategoryInfo.all()
            .join(NameRow.self) { row, name in row.nameID == name.id }
            .filter { row, _ in row.id == category }
            .select { row, name in CategoryHeader.projection(id: row.id, name: name.text) }
            .limit(1)
            .query()
    }

    static func header(ofMarketGroup group: MarketGroupID) -> SQLQuery<MarketGroupHeader> {
        MarketGroupInfo.all()
            .join(NameRow.self) { row, name in row.nameID == name.id }
            .filter { row, _ in row.id == group }
            .select { row, name in
                MarketGroupHeader.projection(id: row.id, name: name.text, iconID: row.iconID)
            }
            .limit(1)
            .query()
    }

    /// Published attributes of a type, ordered by the screen's grouping. Unpublished attributes
    /// are internal (`isCapitalSize`, `entityFlyRange`).
    static func attributes(of type: TypeID) -> SQLQuery<TypeAttributeRow> {
        let withAttribute = TypeAttribute.all()
            .join(DogmaAttributeInfo.self) { row, attribute in row.attributeID == attribute.id }
        let withDisplayName = withAttribute
            .leftJoin(NameRow.self) { _, attribute, name in attribute.displayNameID == name.id }
        let withCategory = withDisplayName
            .leftJoin(DogmaAttributeCategoryInfo.self) { _, attribute, _, category in
                attribute.attributeCategoryID == category.id
            }
        let withUnit = withCategory
            .leftJoin(DogmaUnitInfo.self) { _, attribute, _, _, unit in attribute.unitID == unit.id }
        let withUnitName = withUnit
            .leftJoin(NameRow.self) { _, _, _, _, unit, unitName in unit.displayNameID == unitName.id }
        return withUnitName
            .filter { row, attribute, _, _, _, _ in
                row.typeID == type && attribute.published == true
            }
            .select { row, attribute, name, category, unit, unitName in
                TypeAttributeRow.projection(
                    id: attribute.id,
                    name: attribute.name,
                    displayName: name.text,
                    value: row.value,
                    baseValue: row.value,
                    unitID: unit.id,
                    unitName: unitName.text,
                    categoryID: category.id,
                    categoryName: category.name
                )
            }
            .order(by: { _, attribute, _, _, _, _ in attribute.attributeCategoryID })
            .order(by: { _, attribute, _, _, _, _ in attribute.id })
            .query()
    }

    // MARK: - Attribute references

    /// Names of the types this type's attributes refer to, such as required skills and ammunition.
    static func referencedTypes(of type: TypeID) -> SQLQuery<TypeReference> {
        let withAttribute = TypeAttributeAsTypeReference.all()
            .join(DogmaAttributeInfo.self) { row, attribute in row.attributeID == attribute.id }
        let withTarget = withAttribute
            .join(TypeInfo.self) { row, _, target in row.value == target.id }
        let withName = withTarget
            .join(NameRow.self) { _, _, target, name in target.nameID == name.id }
        return withName
            .filter { row, attribute, _, _ in
                row.typeID == type && attribute.unitID == SDEUnit.typeID.id
            }
            .select { _, _, target, name in
                TypeReference.projection(id: target.id, name: name.text)
            }
            .query()
    }

    static func referencedGroups(of type: TypeID) -> SQLQuery<GroupReference> {
        let withAttribute = TypeAttributeAsGroupReference.all()
            .join(DogmaAttributeInfo.self) { row, attribute in row.attributeID == attribute.id }
        let withTarget = withAttribute
            .join(GroupInfo.self) { row, _, target in row.value == target.id }
        let withName = withTarget
            .join(NameRow.self) { _, _, target, name in target.nameID == name.id }
        return withName
            .filter { row, attribute, _, _ in
                row.typeID == type && attribute.unitID == SDEUnit.groupID.id
            }
            .select { _, _, target, name in
                GroupReference.projection(id: target.id, name: name.text)
            }
            .query()
    }

    static func referencedAttributes(of type: TypeID) -> SQLQuery<AttributeReference> {
        let withAttribute = TypeAttributeAsAttributeReference.all()
            .join(DogmaAttributeInfo.self) { row, attribute in row.attributeID == attribute.id }
        let withTarget = withAttribute
            .join(DogmaAttributeInfo.self) { row, _, target in row.value == target.id }
        let withName = withTarget
            .leftJoin(NameRow.self) { _, _, target, name in target.displayNameID == name.id }
        return withName
            .filter { row, attribute, _, _ in
                row.typeID == type && attribute.unitID == SDEUnit.attributeID.id
            }
            .select { _, _, target, name in
                AttributeReference.projection(
                    id: target.id,
                    name: target.name,
                    displayName: name.text
                )
            }
            .query()
    }

    // MARK: - Required skills

    /// Direct skill requirements of a type, from `dogmaItemSkills`, without prerequisites of those
    /// skills; the catalog expands the tree.
    ///
    /// The row id is the skill, since the item is fixed by the argument.
    static func requiredSkills(of type: TypeID) -> SQLQuery<RequiredSkillRow> {
        DogmaItemSkill.all()
            .filter { requirement in requirement.itemID == type }
            .select { requirement in
                RequiredSkillRow.projection(id: requirement.skillID, level: requirement.level)
            }
            .query()
    }

    /// Names for a set of types: required skills, implants in a clone, a flown ship.
    ///
    /// A separate query rather than a join onto `requiredSkills(of:)`, since the skill tree is
    /// expanded afterwards and holds skills that are nobody's direct requirement.
    ///
    /// `published` is not checked, so unlisted skills still resolve to a name.
    static func typeNames(of types: [TypeID]) -> SQLQuery<TypeNameRow> {
        let withName = TypeInfo.all()
            .join(NameRow.self) { type, name in type.nameID == name.id }
        return withName
            .filter { type, _ in type.id.in(types) }
            .select { type, name in
                TypeNameRow.projection(id: type.id, name: name.text)
            }
            .query()
    }

    // MARK: - Shared projection

    /// The item cell, shared by lists reached through the inventory group, the market group or the
    /// fitting picker. Internal so that `FittingBrowser` reuses the same four-table chain.
    static func typeListRow(
        _ type: TableRef<TypeInfo>,
        _ name: TableRef<NameRow>,
        _ meta: TableRef<MetaGroupInfo>,
        _ metaName: TableRef<NameRow>
    ) -> Projection<TypeListRow> {
        TypeListRow.projection(
            id: type.id,
            name: name.text,
            metaGroupID: type.metaGroupID,
            metaGroupName: metaName.text,
            metaLevel: type.metaLevel,
            metaColorRed: meta.colorR,
            metaColorGreen: meta.colorG,
            metaColorBlue: meta.colorB,
            // Bound NULLs instead of a `LEFT JOIN` onto `dogmaItems`; these lists do not use the
            // fitting figures.
            cpu: ParameterExpression(value: Double?.none),
            power: ParameterExpression(value: Double?.none),
            volume: ParameterExpression(value: Double?.none),
            droneBandwidth: ParameterExpression(value: Double?.none)
        )
    }

    /// The same cell with the fitting figures filled in, for queries that already join `dogmaItems`.
    static func typeListRow(
        _ type: TableRef<TypeInfo>,
        _ name: TableRef<NameRow>,
        _ meta: TableRef<MetaGroupInfo>,
        _ metaName: TableRef<NameRow>,
        _ item: TableRef<DogmaItem>
    ) -> Projection<TypeListRow> {
        TypeListRow.projection(
            id: type.id,
            name: name.text,
            metaGroupID: type.metaGroupID,
            metaGroupName: metaName.text,
            metaLevel: type.metaLevel,
            metaColorRed: meta.colorR,
            metaColorGreen: meta.colorG,
            metaColorBlue: meta.colorB,
            cpu: item.cpu,
            power: item.power,
            volume: item.volume,
            droneBandwidth: item.droneBandwidthUsed
        )
    }
}
