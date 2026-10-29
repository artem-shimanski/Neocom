import DogmaKit
import LiteRow
import SDEKit

// Queries behind the Fitting Tool section: the ships of the "My Fits" list and everything the
// editor's pickers use.

/// A ship as the fitting list groups and labels it.
@Projection
struct ShipRow: Sendable, Identifiable {
    var id: TypeID
    var name: String
    var groupID: GroupID
    var groupName: String
    var groupOrdinal: UInt32
    /// Ship or structure; keeps structure fits out of a fleet.
    var categoryID: CategoryID
}

// MARK: - Item picker rows

/// The hull as the picker's filters and the editor's header need it.
///
/// The inventory group lives in `types` and is what `canFitShipGroup*` refers to; the rig size lives
/// in `dogmaShips`. The two names only feed the header's `GALLENTE · CRUISER` line.
@Projection
struct ShipContextRow: Sendable, Identifiable {
    var id: TypeID
    var groupID: GroupID
    /// `nil` for hulls that accept no rigs (shuttles, capsules); the picker has no rig section then.
    var rigSize: UInt8?
    /// Ship or structure; selects the module category the picker offers.
    var categoryID: CategoryID
    /// The name of the hull's inventory group ("Cruiser", "Strategic Cruiser").
    var groupName: String
    /// The hull's race from `types.raceID`; `nil` for hulls without one (e.g. pirate and rogue-drone
    /// hulls), where the header shows the group name alone.
    var raceName: String?
}

/// An item id only; the ship-restriction lists are read into a `Set<TypeID>` and never shown.
@Projection
struct ItemIDRow: Sendable, Identifiable {
    var id: TypeID
}

/// One slot number of a slot attribute (`boosterness`), as the SDE stores it: a `REAL`.
@Projection
struct SlotNumberRow: Sendable, Identifiable {
    var id: Double
}

/// Where a type stands in its variation family.
///
/// `variationParentID` is `nil` on the root and holds the root's id on every variant, so the family
/// of a type is `rootID ?? id`.
@Projection
struct VariationRootRow: Sendable, Identifiable {
    var id: TypeID
    var rootID: TypeID?
}

/// One skill an item asks for, with the item that asks.
///
/// `id` is the skill, so a skill required by several items repeats once per item. Consumers needing
/// one entry per skill collapse the rows (keeping the highest `level`) and key a `ForEach` by
/// something else.
@Projection
struct ItemSkillRow: Sendable, Identifiable {
    var id: TypeID
    var itemID: TypeID
    var level: Int
    var name: String
}

// MARK: - Damage-pattern source rows

/// An ammo charge or a drone that deals damage, for the "Damage from…" list.
///
/// `TypeListRow` with the group and charge size, which decide whether a charge fits one of the
/// fit's modules (`FittingBrowser.damageCharges(inGroups:)` returns the union of their groups; the
/// pairs are matched in Swift). The damage is read separately by `FittingBrowser.damageAttributes(of:)`,
/// as four more joins exceed the type-checker.
@Projection
struct DamageItemRow: Sendable, Identifiable {
    var id: TypeID
    var name: String
    var groupID: GroupID
    var chargeSize: UInt8?
    var volume: Double?
    var metaGroupID: MetaGroupID?
    var metaGroupName: String?
    var metaLevel: Int?
    var metaColorRed: Double?
    var metaColorGreen: Double?
    var metaColorBlue: Double?
}

extension DamageItemRow {
    /// The same item as the picker's shared row.
    var listRow: TypeListRow {
        TypeListRow(id: id,
                    name: name,
                    metaGroupID: metaGroupID,
                    metaGroupName: metaGroupName,
                    metaLevel: metaLevel,
                    metaColorRed: metaColorRed,
                    metaColorGreen: metaColorGreen,
                    metaColorBlue: metaColorBlue,
                    cpu: nil,
                    power: nil,
                    volume: volume,
                    droneBandwidth: nil)
    }
}

// MARK: - Implant and booster picker rows

/// One implant or booster of a slot, with the inventory group the implant picker sections by.
///
/// `TypeListRow` plus `groupID` and `groupName`; heading order comes from the query's `ORDER BY`.
/// The booster picker sections by `metaLevel`, since `metaGroupID` is `NULL` on 295 of 429 boosters.
@Projection
struct SlotItemRow: Sendable, Identifiable {
    var id: TypeID
    var name: String
    var groupID: GroupID
    var groupName: String
    var metaGroupID: MetaGroupID?
    var metaGroupName: String?
    var metaLevel: Int?
    var metaColorRed: Double?
    var metaColorGreen: Double?
    var metaColorBlue: Double?
}

extension SlotItemRow {
    /// The same item as the picker's shared row; CPU, power grid, volume and bandwidth are empty.
    var listRow: TypeListRow {
        TypeListRow(id: id,
                    name: name,
                    metaGroupID: metaGroupID,
                    metaGroupName: metaGroupName,
                    metaLevel: metaLevel,
                    metaColorRed: metaColorRed,
                    metaColorGreen: metaColorGreen,
                    metaColorBlue: metaColorBlue,
                    cpu: nil,
                    power: nil,
                    volume: nil,
                    droneBandwidth: nil)
    }
}

/// One attribute an item's effect raises or lowers, with the figure the item carries for it.
///
/// The second source of the bonus line (see `ItemBonusLine`): the attribute a type's effect works
/// through (`Duration Bonus`, `Armor Hitpoint Bonus`) and its value on the type. `id` is the
/// attribute, so a type reaching it through several effects repeats once per effect.
@Projection
struct ItemModifierRow: Sendable, Identifiable {
    var id: AttributeID
    var typeID: TypeID
    /// Internal name, for attributes without a `displayName`.
    var name: String
    var displayName: String?
    var value: Double
    var unitID: UnitID?
    var unitName: String?
}

/// One side effect of a booster: what it affects, by how much and how often.
@Projection
struct BoosterSideEffectRow: Sendable, Identifiable {
    /// The effect, e.g. `boosterArmorHpPenalty`.
    var id: EffectID
    var typeID: TypeID
    /// The penalty attribute `value` belongs to; queried from the engine for the applied figure
    /// (`Nanite Control` lowers it through attribute 1126).
    var attributeID: AttributeID
    /// Internal name of the penalty attribute, for attributes without a `displayName`.
    var name: String
    /// `Armor Hitpoint Penalty`, `Turret Tracking Penalty`.
    var displayName: String?
    /// The penalty value as stored in the SDE, e.g. `-20`. The engine applies a different figure
    /// when the pilot has the softening skill; see `attributeID`.
    var value: Double
    /// The chance the effect fires as a fraction, e.g. `0.2`; the value of the attribute named by
    /// `fittingUsageChanceAttributeID` on the same booster.
    var chance: Double
    var unitID: UnitID?
    var unitName: String?
}

// MARK: - Environment rows

/// A system effect the environment screen offers: a type of the `Effect Beacon` group.
@Projection
struct EnvironmentEffectRow: Sendable, Identifiable {
    var id: TypeID
    /// In the database's language.
    var name: String
    /// In English regardless of language; `EnvironmentCatalog` categorizes by it.
    var englishName: String
}

/// One attribute of an environment effect, with its value on the effect's type.
@Projection
struct EnvironmentAttributeRow: Sendable, Identifiable {
    var id: AttributeID
    var typeID: TypeID
    var displayName: String?
    var value: Double
    var unitID: UnitID?
    var unitName: String?
}

/// How an environment effect applies one of its attributes: the operation of the modifier working
/// through it and what the modifier changes. The figure's meaning depends on both: `1.72` is `+72%`
/// under a multiplication, `36` on a resonance is a resistance lowered by 36%.
@Projection
struct EnvironmentOperationRow: Sendable {
    /// The attribute of the effect's type the modifier takes its figure from; never `nil` in the
    /// query's rows, optional because the column is.
    var attributeID: AttributeID?
    var typeID: TypeID
    var operation: Int?
    var modifiedAttributeID: AttributeID?
}

// MARK: - Mutation rows

/// A mutaplasmid that applies to one base type, and the abyssal type the module becomes.
@Projection
struct MutaplasmidRow: Sendable, Identifiable {
    var id: TypeID
    /// In the database's language.
    var name: String
    /// In English regardless of language; `MutaplasmidTier` reads the tier from it.
    var englishName: String
    var resultingTypeID: TypeID
}

/// A mutaplasmid's names, for the editor's rows of mutated modules.
@Projection
struct MutaplasmidNameRow: Sendable, Identifiable {
    var id: TypeID
    var name: String
    var englishName: String
}

/// One range of a mutaplasmid (multipliers of the base value) with the attribute's name and unit.
@Projection
struct MutaplasmidRangeRow: Sendable {
    var mutaplasmidID: TypeID
    var attributeID: AttributeID
    var minMultiplier: Double
    var maxMultiplier: Double
    var name: String
    var displayName: String?
    var unitID: UnitID?
    var unitName: String?
}

/// Queries behind the Fitting Tool section.
enum FittingBrowser {

    /// Names and inventory groups of the ships a list of fits uses.
    ///
    /// `published` is not checked: a fit on a withdrawn ship still exists.
    static func ships(_ types: [TypeID]) -> SQLQuery<ShipRow> {
        let withName = TypeInfo.all()
            .join(NameRow.self) { type, name in type.nameID == name.id }
        let withGroup = withName
            .join(GroupInfo.self) { type, _, group in type.groupID == group.id }
        let withGroupName = withGroup
            .join(NameRow.self) { _, _, group, groupName in group.nameID == groupName.id }
        return withGroupName
            .filter { type, _, _, _ in type.id.in(types) }
            .select { type, name, group, groupName in
                ShipRow.projection(id: type.id,
                                   name: name.text,
                                   groupID: group.id,
                                   groupName: groupName.text,
                                   groupOrdinal: groupName.ordinal,
                                   categoryID: group.categoryID)
            }
            .query()
    }

    // MARK: - Hulls

    /// Ids of every hull the hull picker offers; the subquery its three queries narrow by.
    ///
    /// A hull is a type with a row in `dogmaShips`. Every ship counts, including shuttles and
    /// capsules; a structure counts only with at least one slot. `published` is checked by the
    /// outer queries.
    ///
    /// `includingStructures` is a bound constant, not an `if`, to keep one expression of one Swift
    /// type (see `fits`); off, the term is a literal false.
    private static func hullIDs(includingStructures: Bool) -> some Subquery<Scalar<TypeID>> {
        let includesStructures = ParameterExpression(value: includingStructures)
        let withType = DogmaShip.all()
            .join(TypeInfo.self) { hull, type in type.id == hull.id }
        let withGroup = withType
            .join(GroupInfo.self) { _, type, group in type.groupID == group.id }
        return withGroup
            .filter { hull, _, group in
                let slots = hull.hiSlots + hull.medSlots + hull.lowSlots + hull.rigSlots + hull.serviceSlots
                return group.categoryID == CategoryID.ship
                    || (includesStructures && group.categoryID == CategoryID.structure && slots > 0)
            }
            .select { hull, _, _ in hull.id }
    }

    /// The hull picker's market groups under `parent`, or its roots when `nil`:
    /// `marketGroups(inParent:narrowedTo:)` over `hullIDs`.
    ///
    /// The roots are the market roots with a hull below them: "Ships" and, with structures,
    /// "Structures". The `HAVING` drops branches holding only starbases, deployables and the like;
    /// counts are of hulls alone.
    static func hullMarketGroups(inParent parent: MarketGroupID?,
                                 includingStructures: Bool) -> SQLQuery<MarketGroupListRow> {
        marketGroups(inParent: parent, narrowedTo: hullIDs(includingStructures: includingStructures), hiding: [])
    }

    /// Market roots the item picker leaves out. "Special Edition Assets" (1659) contains festival
    /// launchers, which would add a second root for high slots; search still finds them.
    private static let hiddenItemRoots: [MarketGroupID] = [1659]

    /// `SDEBrowser.marketGroups(inParent:)` with the types narrowed to `ids`: groups, counts and
    /// roots cover only what the picker offers, and empty branches are omitted. Shared by the hull
    /// and item pickers, which differ in the subquery and the hidden roots.
    private static func marketGroups<IDs: Subquery<Scalar<TypeID>>>(
        inParent parent: MarketGroupID?,
        narrowedTo ids: IDs,
        hiding hidden: [MarketGroupID]
    ) -> SQLQuery<MarketGroupListRow> {
        let withName = MarketGroupInfo.all()
            .join(NameRow.self) { group, name in group.nameID == name.id }
        let withTree = withName
            .join(MarketGroupTree.self) { group, _, tree in tree.ancestorID == group.id }
        let withType = withTree
            .leftJoin(TypeInfo.self) { _, _, tree, type in
                type.marketGroupID == tree.descendantID && type.published == true && type.id.in(ids)
            }
        return withType
            .filter { group, _, _, _ in group.parentID == parent && group.id.notIn(hidden) }
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

    /// Hulls filed directly on one market group: `SDEBrowser.types(inMarketGroup:)` narrowed to `hullIDs`.
    static func hulls(inMarketGroup group: MarketGroupID,
                      includingStructures: Bool) -> SQLQuery<TypeListRow> {
        let hulls = hullIDs(includingStructures: includingStructures)
        let withName = TypeInfo.all()
            .join(NameRow.self) { type, name in type.nameID == name.id }
        let withMeta = withName
            .leftJoin(MetaGroupInfo.self) { type, _, meta in type.metaGroupID == meta.id }
        let withMetaName = withMeta
            .leftJoin(NameRow.self) { _, _, meta, metaName in meta.nameID == metaName.id }
        return withMetaName
            .filter { type, _, _, _ in
                type.marketGroupID == group && type.published == true && type.id.in(hulls)
            }
            .select { type, name, meta, metaName in SDEBrowser.typeListRow(type, name, meta, metaName) }
            .order(by: { _, name, _, _ in name.ordinal })
            .query()
    }

    /// The hull picker's name search: `SDEBrowser.search(_:limit:)` narrowed to `hullIDs`.
    ///
    /// Not restricted to the market tree: some published hulls (the Capsule, the Stratios Emergency
    /// Responder) have no market group.
    static func hulls(matching pattern: FTS5Pattern,
                      includingStructures: Bool,
                      limit: Int = 100) -> SQLQuery<TypeSearchRow> {
        let hulls = hullIDs(includingStructures: includingStructures)
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
            .filter { _, type, _, _, _ in type.published == true && type.id.in(hulls) }
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

    // MARK: - Hull filter keys

    /// The hull's group and rig size, the two keys every filter below needs. Read once when a fit
    /// is opened; they do not change while it is edited.
    static func shipContext(_ ship: TypeID) -> SQLQuery<ShipContextRow> {
        // One join per statement. The race is a left join since `types.raceID` is optional.
        let withHull = TypeInfo.all()
            .join(DogmaShip.self) { type, hull in type.id == hull.id }
        let withGroup = withHull
            .join(GroupInfo.self) { type, _, group in type.groupID == group.id }
        let withGroupName = withGroup
            .join(NameRow.self) { _, _, group, groupName in group.nameID == groupName.id }
        let withRace = withGroupName
            .leftJoin(RaceInfo.self) { type, _, _, _, race in type.raceID == race.id }
        let withRaceName = withRace
            .leftJoin(NameRow.self) { _, _, _, _, race, raceName in race.nameID == raceName.id }
        return withRaceName
            .filter { type, _, _, _, _, _ in type.id == ship }
            .select { type, hull, group, groupName, _, raceName in
                ShipContextRow.projection(id: type.id,
                                          groupID: type.groupID,
                                          rigSize: hull.rigSize,
                                          categoryID: group.categoryID,
                                          groupName: groupName.text,
                                          raceName: raceName.text)
            }
            .limit(1)
            .query()
    }

    /// Items this hull is explicitly allowed to fit, by type.
    ///
    /// Separate queries instead of `LEFT JOIN`s onto the item list, which already uses five tables
    /// and would exceed the pack-expansion type-checker. The union of both results is the `allowed`
    /// argument below. Only 684 items carry any restriction; unrestricted items pass on
    /// `hasShipRestrictions == false`.
    static func allowedByShipType(_ ship: TypeID) -> SQLQuery<ItemIDRow> {
        DogmaItemShipType.all()
            .filter { restriction in restriction.shipTypeID == ship }
            .select { restriction in ItemIDRow.projection(id: restriction.itemID) }
            .query()
    }

    /// The same by the hull's inventory group (`canFitShipGroup01…20`).
    static func allowedByShipGroup(_ group: GroupID) -> SQLQuery<ItemIDRow> {
        DogmaItemShipGroup.all()
            .filter { restriction in restriction.shipGroupID == group }
            .select { restriction in ItemIDRow.projection(id: restriction.itemID) }
            .query()
    }

    // MARK: - Fitting items

    /// The item picker's market groups under `parent`, or its roots when `nil`: the market tree
    /// narrowed to items of this kind that fit this hull. A high slot gets "Ship Equipment" without
    /// armour modules; a rig slot gets "Ship and Module Modifications" only. Drone and fighter
    /// pickers walk the same tree under "Drones".
    ///
    /// `squadron`, for the fighter picker, is the type attribute marking the squadron type
    /// (`fighterSquadronIsLight` and the rest); `nil` elsewhere.
    ///
    /// Items without a market group are absent from the tree; search still finds them.
    static func fittingMarketGroups(kind: DogmaItemKind,
                                    inParent parent: MarketGroupID?,
                                    allowed: [TypeID],
                                    rigSize: UInt8?,
                                    structureHull: Bool?,
                                    squadron: AttributeID? = nil) -> SQLQuery<MarketGroupListRow> {
        marketGroups(inParent: parent,
                     narrowedTo: fittingItemIDs(kind: kind, allowed: allowed, rigSize: rigSize, structureHull: structureHull,
                                                squadron: squadron),
                     hiding: hiddenItemRoots)
    }

    /// The items of this kind that fit this hull filed directly on one market group, matching what
    /// `fittingMarketGroups` counts by the same subquery. `published` is checked since the tree
    /// counts published types only.
    ///
    /// The cell is the database browser's `TypeListRow` with `dogmaItems` joined on top.
    static func fittingItems(kind: DogmaItemKind,
                             inMarketGroup group: MarketGroupID,
                             allowed: [TypeID],
                             rigSize: UInt8?,
                             structureHull: Bool?,
                             squadron: AttributeID? = nil) -> SQLQuery<TypeListRow> {
        // One join per statement: growing the type pack and destructuring it in the same expression
        // hits swiftlang/swift#78725.
        let withName = TypeInfo.all()
            .join(NameRow.self) { type, name in type.nameID == name.id }
        let withMeta = withName
            .leftJoin(MetaGroupInfo.self) { type, _, meta in type.metaGroupID == meta.id }
        let withMetaName = withMeta
            .leftJoin(NameRow.self) { _, _, meta, metaName in meta.nameID == metaName.id }
        let withItem = withMetaName
            .join(DogmaItem.self) { type, _, _, _, item in type.id == item.id }
        let ids = fittingItemIDs(kind: kind, allowed: allowed, rigSize: rigSize, structureHull: structureHull,
                                 squadron: squadron)
        return withItem
            .filter { type, _, _, _, _ in type.marketGroupID == group && type.published == true }
            .filter { type, _, _, _, _ in type.id.in(ids) }
            .select { type, name, meta, metaName, item in
                SDEBrowser.typeListRow(type, name, meta, metaName, item)
            }
            .order(by: { _, name, _, _, _ in name.ordinal })
            .query()
    }

    /// Ids of the items of this kind that fit this hull; the subquery narrowing the item picker's
    /// market tree, counterpart of `hullIDs`. The squadron term is a bound constant (see `fits`);
    /// off, it is a literal true.
    private static func fittingItemIDs(kind: DogmaItemKind,
                                       allowed: [TypeID],
                                       rigSize: UInt8?,
                                       structureHull: Bool?,
                                       squadron: AttributeID?) -> some Subquery<Scalar<TypeID>> {
        let ignoresSquadron = ParameterExpression(value: squadron == nil)
        let squadronID = squadron ?? AttributeID(rawValue: 0)
        let members = TypeAttribute.all()
            .filter { attribute in attribute.attributeID == squadronID }
            .select { attribute in attribute.typeID }
        return DogmaItem.all()
            .filter { item in fits(item, kind: kind, allowed: allowed, rigSize: rigSize, structureHull: structureHull) }
            .filter { item in ignoresSquadron || item.id.in(members) }
            .select { item in item.id }
    }

    /// The same items by name across every group of the kind, ordered by relevance. Backs the
    /// picker's `.searchable`.
    static func fittingItems(kind: DogmaItemKind,
                             matching pattern: FTS5Pattern,
                             allowed: [TypeID],
                             rigSize: UInt8?,
                             structureHull: Bool?) -> SQLQuery<TypeListRow> {
        let withType = NameSearchIndex.all()
            .join(TypeInfo.self) { fts, type in fts.rowID(as: NameID.self) == type.nameID }
        let withName = withType
            .join(NameRow.self) { _, type, name in type.nameID == name.id }
        let withMeta = withName
            .leftJoin(MetaGroupInfo.self) { _, type, _, meta in type.metaGroupID == meta.id }
        let withMetaName = withMeta
            .leftJoin(NameRow.self) { _, _, _, meta, metaName in meta.nameID == metaName.id }
        let withItem = withMetaName
            .join(DogmaItem.self) { _, type, _, _, _, item in type.id == item.id }
        return withItem
            .filter { fts, _, _, _, _, _ in
                fts.match(pattern) && fts.ranked(by: SDEDatabase.searchRanking)
            }
            .filter { _, type, _, _, _, item in
                type.published == true
                    && fits(item, kind: kind, allowed: allowed, rigSize: rigSize, structureHull: structureHull)
            }
            .select { _, type, name, meta, metaName, item in
                SDEBrowser.typeListRow(type, name, meta, metaName, item)
            }
            .order(by: { fts, _, _, _, _, _ in fts.rank })
            .query()
    }

    /// Charges a module takes: the groups it names, narrowed to its charge size, by name.
    ///
    /// There is no `allowed` argument; what a charge fits into is decided by the module. `size` is
    /// `nil` for modules taking sizeless charges (scripts, single-size mining crystals), which
    /// narrows nothing.
    static func charges(inGroups groups: [GroupID], size: UInt8?) -> SQLQuery<TypeListRow> {
        let withName = TypeInfo.all()
            .join(NameRow.self) { type, name in type.nameID == name.id }
        let withMeta = withName
            .leftJoin(MetaGroupInfo.self) { type, _, meta in type.metaGroupID == meta.id }
        let withMetaName = withMeta
            .leftJoin(NameRow.self) { _, _, meta, metaName in meta.nameID == metaName.id }
        let withItem = withMetaName
            .join(DogmaItem.self) { type, _, _, _, item in type.id == item.id }
        var query = withItem
            .filter { type, _, _, _, _ in type.groupID.in(groups) && type.published == true }
            .filter { _, _, _, _, item in item.kind == DogmaItemKind.charge }
        if size != nil {
            query = query.filter { _, _, _, _, item in item.chargeSize == size }
        }
        return query
            .select { type, name, meta, metaName, item in
                SDEBrowser.typeListRow(type, name, meta, metaName, item)
            }
            .order(by: { _, name, _, _, _ in name.ordinal })
            .query()
    }

    /// The same charges by name, ordered by relevance. Backs the ammo picker's `.searchable`.
    static func charges(inGroups groups: [GroupID],
                        size: UInt8?,
                        matching pattern: FTS5Pattern) -> SQLQuery<TypeListRow> {
        let withType = NameSearchIndex.all()
            .join(TypeInfo.self) { fts, type in fts.rowID(as: NameID.self) == type.nameID }
        let withName = withType
            .join(NameRow.self) { _, type, name in type.nameID == name.id }
        let withMeta = withName
            .leftJoin(MetaGroupInfo.self) { _, type, _, meta in type.metaGroupID == meta.id }
        let withMetaName = withMeta
            .leftJoin(NameRow.self) { _, _, _, meta, metaName in meta.nameID == metaName.id }
        let withItem = withMetaName
            .join(DogmaItem.self) { _, type, _, _, _, item in type.id == item.id }
        var query = withItem
            .filter { fts, _, _, _, _, _ in
                fts.match(pattern) && fts.ranked(by: SDEDatabase.searchRanking)
            }
            .filter { _, type, _, _, _, _ in type.groupID.in(groups) && type.published == true }
            .filter { _, _, _, _, _, item in item.kind == DogmaItemKind.charge }
        if size != nil {
            query = query.filter { _, _, _, _, _, item in item.chargeSize == size }
        }
        return query
            .select { _, type, name, meta, metaName, item in
                SDEBrowser.typeListRow(type, name, meta, metaName, item)
            }
            .order(by: { fts, _, _, _, _, _ in fts.rank })
            .query()
    }

    // MARK: - Damage-pattern sources

    /// `emDamage`, `thermalDamage`, `kineticDamage`, `explosiveDamage`: an item's damage per type,
    /// stored in `typeAttributes`.
    static let damageAttributeIDs: [AttributeID] = [.emDamage, .thermalDamage, .kineticDamage, .explosiveDamage]

    /// The given types that deal damage; the "In this fit" section, with ids from the snapshot.
    static func damageItems(ids: [TypeID]) -> SQLQuery<DamageItemRow> {
        damageItems { type, _ in type.id.in(ids) }
    }

    /// Every damaging charge of these groups, by name; the union of what the fit's modules take.
    /// The caller narrows it to each module's groups and size.
    static func damageCharges(inGroups groups: [GroupID]) -> SQLQuery<DamageItemRow> {
        let kind = DogmaItemKind.charge
        return damageItems { type, item in type.groupID.in(groups) && type.published == true && item.kind == kind }
    }

    /// Every damaging drone the hull may fit, by name.
    static func damageDrones(allowed: [TypeID]) -> SQLQuery<DamageItemRow> {
        let kind = DogmaItemKind.drone
        return damageItems { type, item in
            type.published == true
                && item.kind == kind
                && (item.hasShipRestrictions == false || item.id.in(allowed))
        }
    }

    /// The four damage values of these types; a type has no rows for damage types it does not deal.
    static func damageAttributes(of types: [TypeID]) -> SQLQuery<TypeAttribute> {
        let attributes = damageAttributeIDs
        return TypeAttribute.all()
            .filter { row in row.typeID.in(types) && row.attributeID.in(attributes) }
            .query()
    }

    /// The cell chain of `charges(inGroups:size:)` with `filter` on top, excluding types without damage.
    private static func damageItems<Condition: Expression<Bool>>(
        _ filter: @escaping (TableRef<TypeInfo>, TableRef<DogmaItem>) -> Condition
    ) -> SQLQuery<DamageItemRow> {
        let withName = TypeInfo.all()
            .join(NameRow.self) { type, name in type.nameID == name.id }
        let withMeta = withName
            .leftJoin(MetaGroupInfo.self) { type, _, meta in type.metaGroupID == meta.id }
        let withMetaName = withMeta
            .leftJoin(NameRow.self) { _, _, meta, metaName in meta.nameID == metaName.id }
        let withItem = withMetaName
            .join(DogmaItem.self) { type, _, _, _, item in type.id == item.id }
        return withItem
            .filter { type, _, _, _, item in filter(type, item) }
            .filter { type, _, _, _, _ in type.id.in(damageDealerIDs()) }
            .select { type, name, meta, metaName, item in
                DamageItemRow.projection(id: type.id,
                                         name: name.text,
                                         groupID: type.groupID,
                                         chargeSize: item.chargeSize,
                                         volume: item.volume,
                                         metaGroupID: type.metaGroupID,
                                         metaGroupName: metaName.text,
                                         metaLevel: type.metaLevel,
                                         metaColorRed: meta.colorR,
                                         metaColorGreen: meta.colorG,
                                         metaColorBlue: meta.colorB)
            }
            .order(by: { _, name, _, _, _ in name.ordinal })
            .query()
    }

    /// Every type with a damage value above zero; a subquery, like `structureModuleIDs()`, so the
    /// item chain keeps its five tables.
    private static func damageDealerIDs() -> some Subquery<Scalar<TypeID>> {
        let attributes = damageAttributeIDs
        return TypeAttribute.all()
            .filter { row in row.attributeID.in(attributes) && row.value > 0 }
            .select { row in row.typeID }
    }

    // MARK: - Variations

    /// The root of the family a type belongs to.
    ///
    /// One row, not a join onto the family: the root of a variant is its `variationParentID` and a
    /// root's `nil` is resolved in Swift before the second query.
    static func variationRoot(of type: TypeID) -> SQLQuery<VariationRootRow> {
        TypeInfo.all()
            .filter { row in row.id == type }
            .select { row in
                VariationRootRow.projection(id: row.id, rootID: row.variationParentID)
            }
            .limit(1)
            .query()
    }

    /// Everyone in the family: the root and every variant.
    ///
    /// The hull's filters apply as in the picker, since the list offers replacements; unpublished
    /// members are left out. A family may cross meta groups freely.
    static func variations(ofRoot root: TypeID,
                           kind: DogmaItemKind,
                           allowed: [TypeID],
                           rigSize: UInt8?,
                           structureHull: Bool?) -> SQLQuery<TypeListRow> {
        let withName = TypeInfo.all()
            .join(NameRow.self) { type, name in type.nameID == name.id }
        let withMeta = withName
            .leftJoin(MetaGroupInfo.self) { type, _, meta in type.metaGroupID == meta.id }
        let withMetaName = withMeta
            .leftJoin(NameRow.self) { _, _, meta, metaName in meta.nameID == metaName.id }
        let withItem = withMetaName
            .join(DogmaItem.self) { type, _, _, _, item in type.id == item.id }
        return withItem
            .filter { type, _, _, _, _ in
                (type.id == root || type.variationParentID == root) && type.published == true
            }
            .filter { _, _, _, _, item in fits(item, kind: kind, allowed: allowed, rigSize: rigSize, structureHull: structureHull) }
            .select { type, name, meta, metaName, item in
                SDEBrowser.typeListRow(type, name, meta, metaName, item)
            }
            .order(by: { _, name, _, _, _ in name.ordinal })
            .query()
    }

    // MARK: - Implants and boosters

    /// `implantness` and `boosterness`: the attributes carrying an item's slot, stored in
    /// `typeAttributes`.
    private static let implantness: AttributeID = 331
    private static let boosterness: AttributeID = 1087

    /// The types that go into one implant or booster slot, or into any when `slot` is `nil`.
    ///
    /// A separate query since the item list already uses six tables and the slot lives in a seventh.
    /// The caller passes the result to `slotItems(ids:)`.
    ///
    /// Both pickers ask for one slot; the booster slots come from `boosterSlots()`.
    ///
    /// `kind` is `.implant` or `.booster` and is checked in addition to the slot attribute.
    ///
    /// `marketableOnly` drops types without a market group, which for boosters are expired event
    /// doses. The implant picker passes `false`: three implants lack a market group, all in slot 6.
    ///
    /// No hull filter applies: `hasShipRestrictions` is false for every implant and booster.
    static func slotItemIDs(kind: DogmaItemKind,
                            slot: UInt16?,
                            marketableOnly: Bool) -> SQLQuery<ItemIDRow> {
        let slotAttribute = kind == .booster ? Self.boosterness : Self.implantness
        let withItem = TypeAttribute.all()
            .join(DogmaItem.self) { attribute, item in attribute.typeID == item.id }
        let withType = withItem
            .join(TypeInfo.self) { attribute, _, type in attribute.typeID == type.id }
        var query = withType
            .filter { attribute, item, type in
                attribute.attributeID == slotAttribute && item.kind == kind && type.published == true
            }
        if let slot {
            let slotValue = Double(slot)
            query = query.filter { attribute, _, _ in attribute.value == slotValue }
        }
        if marketableOnly {
            query = query.filter { _, _, type in type.marketGroupID != nil }
        }
        return query
            .select { attribute, _, _ in ItemIDRow.projection(id: attribute.typeID) }
            .query()
    }

    /// The booster slots shown as rows: every `boosterness` value among marketable boosters,
    /// ascending.
    ///
    /// Uses the booster picker's filter (`slotItemIDs(kind: .booster, …, marketableOnly: true)`),
    /// so every row has items. Other values belong to expired event doses; a fit carrying one keeps
    /// its own row outside the grid, as an implant with `implantness` 79 does.
    static func boosterSlots() -> SQLQuery<SlotNumberRow> {
        let kind = DogmaItemKind.booster
        let slotAttribute = Self.boosterness
        let withItem = TypeAttribute.all()
            .join(DogmaItem.self) { attribute, item in attribute.typeID == item.id }
        let withType = withItem
            .join(TypeInfo.self) { attribute, _, type in attribute.typeID == type.id }
        return withType
            .filter { attribute, item, type in
                attribute.attributeID == slotAttribute && item.kind == kind && type.marketGroupID != nil
                    && type.published == true
            }
            .group(by: { attribute, _, _ in attribute.value })
            .select { attribute, _, _ in SlotNumberRow.projection(id: attribute.value) }
            .order(by: { attribute, _, _ in attribute.value })
            .query()
    }

    /// The items of a slot with their inventory group, ordered by group name and then item name, so
    /// one pass yields the sections.
    ///
    /// `ids` is the result of `slotItemIDs`, which alone decides what the slot holds.
    static func slotItems(ids: [TypeID]) -> SQLQuery<SlotItemRow> {
        // One join per statement.
        let withName = TypeInfo.all()
            .join(NameRow.self) { type, name in type.nameID == name.id }
        let withGroup = withName
            .join(GroupInfo.self) { type, _, group in type.groupID == group.id }
        let withGroupName = withGroup
            .join(NameRow.self) { _, _, group, groupName in group.nameID == groupName.id }
        let withMeta = withGroupName
            .leftJoin(MetaGroupInfo.self) { type, _, _, _, meta in type.metaGroupID == meta.id }
        let withMetaName = withMeta
            .leftJoin(NameRow.self) { _, _, _, _, meta, metaName in meta.nameID == metaName.id }
        return withMetaName
            .filter { type, _, _, _, _, _ in type.id.in(ids) }
            .select { type, name, group, groupName, meta, metaName in
                SlotItemRow.projection(id: type.id,
                                       name: name.text,
                                       groupID: group.id,
                                       groupName: groupName.text,
                                       metaGroupID: type.metaGroupID,
                                       metaGroupName: metaName.text,
                                       metaLevel: type.metaLevel,
                                       metaColorRed: meta.colorR,
                                       metaColorGreen: meta.colorG,
                                       metaColorBlue: meta.colorB)
            }
            .order(by: { _, _, _, groupName, _, _ in groupName.ordinal })
            .order(by: { _, name, _, _, _, _ in name.ordinal })
            .query()
    }

    /// The same items by name, ordered by relevance. Backs the pickers' `.searchable`.
    ///
    /// Returns `TypeListRow` rather than `SlotItemRow`: results are one flat list without group headings.
    static func slotItems(ids: [TypeID], matching pattern: FTS5Pattern) -> SQLQuery<TypeListRow> {
        let withType = NameSearchIndex.all()
            .join(TypeInfo.self) { fts, type in fts.rowID(as: NameID.self) == type.nameID }
        let withName = withType
            .join(NameRow.self) { _, type, name in type.nameID == name.id }
        let withMeta = withName
            .leftJoin(MetaGroupInfo.self) { _, type, _, meta in type.metaGroupID == meta.id }
        let withMetaName = withMeta
            .leftJoin(NameRow.self) { _, _, _, meta, metaName in meta.nameID == metaName.id }
        return withMetaName
            .filter { fts, _, _, _, _ in
                fts.match(pattern) && fts.ranked(by: SDEDatabase.searchRanking)
            }
            .filter { _, type, _, _, _ in type.id.in(ids) }
            .select { _, type, name, meta, metaName in
                SDEBrowser.typeListRow(type, name, meta, metaName)
            }
            .order(by: { fts, _, _, _, _ in fts.rank })
            .query()
    }

    /// The side effects of boosters: every effect that has a chance of firing.
    ///
    /// `fittingUsageChanceAttributeID IS NOT NULL` matches 12 effects, all booster penalties. The
    /// penalty is the attribute the effect's modifier works through (`modifyingAttributeID`), its
    /// value on the booster is the magnitude, and the chance is the value of the attribute the
    /// effect names.
    ///
    /// Does not use `SDEBrowser.attributes(of:)`, which keeps only `published` attributes:
    /// `boosterEffectChance2…5` and the effect `boosterMissileExplosionCloudPenaltyFixed` are
    /// unpublished.
    ///
    /// Only the modifier with `index = 0` is read; the two effects with two modifiers repeat the
    /// same penalty attribute.
    ///
    /// Ordered by effect, which is stable but not meaningful.
    static func sideEffects(of types: [TypeID]) -> SQLQuery<BoosterSideEffectRow> {
        let withEffect = TypeEffect.all()
            .join(DogmaEffectInfo.self) { link, effect in link.effectID == effect.id }
        let withModifier = withEffect
            .join(DogmaEffectModifier.self) { _, effect, modifier in
                modifier.effectID == effect.id && modifier.index == 0
            }
        let withValue = withModifier
            .join(TypeAttribute.self) { link, _, modifier, value in
                value.typeID == link.typeID && value.attributeID == modifier.modifyingAttributeID
            }
        let withChance = withValue
            .join(TypeAttribute.self) { link, effect, _, _, chance in
                chance.typeID == link.typeID && chance.attributeID == effect.fittingUsageChanceAttributeID
            }
        let withAttribute = withChance
            .join(DogmaAttributeInfo.self) { _, _, modifier, _, _, attribute in
                attribute.id == modifier.modifyingAttributeID
            }
        let withName = withAttribute
            .leftJoin(NameRow.self) { _, _, _, _, _, attribute, name in attribute.displayNameID == name.id }
        let withUnit = withName
            .leftJoin(DogmaUnitInfo.self) { _, _, _, _, _, attribute, _, unit in attribute.unitID == unit.id }
        let withUnitName = withUnit
            .leftJoin(NameRow.self) { _, _, _, _, _, _, _, unit, unitName in unit.displayNameID == unitName.id }
        return withUnitName
            .filter { link, effect, _, _, _, _, _, _, _ in
                link.typeID.in(types) && effect.fittingUsageChanceAttributeID != nil
            }
            .select { link, effect, _, value, chance, attribute, name, unit, unitName in
                BoosterSideEffectRow.projection(id: effect.id,
                                                typeID: link.typeID,
                                                attributeID: attribute.id,
                                                name: attribute.name,
                                                displayName: name.text,
                                                value: value.value,
                                                chance: chance.value,
                                                unitID: unit.id,
                                                unitName: unitName.text)
            }
            .order(by: { _, effect, _, _, _, _, _, _, _ in effect.id })
            .query()
    }

    // MARK: - Item bonuses

    /// What an implant (or a booster that works like one) adds to the pilot's attributes; the first
    /// source of the bonus line. Non-zero bonuses only, one row per (item, attribute).
    static func attributeBonuses(of types: [TypeID]) -> SQLQuery<DogmaImplantAttribute> {
        DogmaImplantAttribute.all()
            .filter { bonus in bonus.implantID.in(types) }
            .query()
    }

    /// The attributes the types' own effects work through; the second source of the bonus line.
    ///
    /// Covers every effect except booster penalties (`sideEffects(of:)`) and every modifier, with
    /// the type's value for the attribute the modifier works through. `ItemBonusLine` keeps a type
    /// only when this reduces to one attribute. Effects whose attribute the type has no value for
    /// are omitted.
    static func effectModifiers(of types: [TypeID]) -> SQLQuery<ItemModifierRow> {
        let withEffect = TypeEffect.all()
            .join(DogmaEffectInfo.self) { link, effect in link.effectID == effect.id }
        let withModifier = withEffect
            .join(DogmaEffectModifier.self) { _, effect, modifier in modifier.effectID == effect.id }
        let withValue = withModifier
            .join(TypeAttribute.self) { link, _, modifier, value in
                value.typeID == link.typeID && value.attributeID == modifier.modifyingAttributeID
            }
        let withAttribute = withValue
            .join(DogmaAttributeInfo.self) { _, _, modifier, _, attribute in
                attribute.id == modifier.modifyingAttributeID
            }
        let withName = withAttribute
            .leftJoin(NameRow.self) { _, _, _, _, attribute, name in attribute.displayNameID == name.id }
        let withUnit = withName
            .leftJoin(DogmaUnitInfo.self) { _, _, _, _, attribute, _, unit in attribute.unitID == unit.id }
        let withUnitName = withUnit
            .leftJoin(NameRow.self) { _, _, _, _, _, _, unit, unitName in unit.displayNameID == unitName.id }
        return withUnitName
            .filter { link, effect, _, _, _, _, _, _ in
                link.typeID.in(types) && effect.fittingUsageChanceAttributeID == nil
            }
            .select { link, _, _, value, attribute, name, unit, unitName in
                ItemModifierRow.projection(id: attribute.id,
                                           typeID: link.typeID,
                                           name: attribute.name,
                                           displayName: name.text,
                                           value: value.value,
                                           unitID: unit.id,
                                           unitName: unitName.text)
            }
            .query()
    }

    // MARK: - Environment

    /// Every published type of the `Effect Beacon` group (920), covering wormhole, incursion,
    /// invasion and storm effects and beacons, in the current language's alphabet.
    ///
    /// Internal `SOEEB…` types are published too, marked `DO NOT TRANSLATE`; `EnvironmentCatalog`
    /// drops them.
    static func environmentEffects() -> SQLQuery<EnvironmentEffectRow> {
        let group = GroupID.effectBeacon
        let withName = TypeInfo.all()
            .join(NameRow.self) { type, name in type.nameID == name.id }
        return withName
            .filter { type, _ in type.groupID == group && type.published == true }
            .select { type, name in
                EnvironmentEffectRow.projection(id: type.id, name: name.text, englishName: name.textEn)
            }
            .order(by: { _, name in name.ordinal })
            .query()
    }

    /// The same rows for the effects a fit carries, for the editor's chip. Neither the group nor
    /// `published` is checked, since an imported document can carry any Celestial type.
    static func environmentEffects(of types: [TypeID]) -> SQLQuery<EnvironmentEffectRow> {
        let withName = TypeInfo.all()
            .join(NameRow.self) { type, name in type.nameID == name.id }
        return withName
            .filter { type, _ in type.id.in(types) }
            .select { type, name in
                EnvironmentEffectRow.projection(id: type.id, name: name.text, englishName: name.textEn)
            }
            .query()
    }

    /// The published attributes of environment effects, by attribute id. All of them modify the
    /// affected ships; the group has no other attributes.
    static func environmentAttributes(of types: [TypeID]) -> SQLQuery<EnvironmentAttributeRow> {
        let withAttribute = TypeAttribute.all()
            .join(DogmaAttributeInfo.self) { row, attribute in row.attributeID == attribute.id }
        let withName = withAttribute
            .leftJoin(NameRow.self) { _, attribute, name in attribute.displayNameID == name.id }
        let withUnit = withName
            .leftJoin(DogmaUnitInfo.self) { _, attribute, _, unit in attribute.unitID == unit.id }
        let withUnitName = withUnit
            .leftJoin(NameRow.self) { _, _, _, unit, unitName in unit.displayNameID == unitName.id }
        return withUnitName
            .filter { row, attribute, _, _, _ in row.typeID.in(types) && attribute.published == true }
            .select { row, attribute, name, unit, unitName in
                EnvironmentAttributeRow.projection(id: attribute.id,
                                                   typeID: row.typeID,
                                                   displayName: name.text,
                                                   value: row.value,
                                                   unitID: unit.id,
                                                   unitName: unitName.text)
            }
            .order(by: { _, attribute, _, _, _ in attribute.id })
            .query()
    }

    /// How the types' effects apply their attributes: one row per effect modifier, keyed by the
    /// attribute it takes its figure from. An attribute with several modifiers repeats once per
    /// modifier; they share the operation in every effect of the group.
    static func environmentOperations(of types: [TypeID]) -> SQLQuery<EnvironmentOperationRow> {
        let withModifier = TypeEffect.all()
            .join(DogmaEffectModifier.self) { link, modifier in link.effectID == modifier.effectID }
        return withModifier
            .filter { link, modifier in link.typeID.in(types) && modifier.modifyingAttributeID != nil }
            .select { link, modifier in
                EnvironmentOperationRow.projection(attributeID: modifier.modifyingAttributeID,
                                                           typeID: link.typeID,
                                                           operation: modifier.operation,
                                                           modifiedAttributeID: modifier.modifiedAttributeID)
            }
            .query()
    }

    // MARK: - Mutaplasmids

    /// Every mutaplasmid the SDE maps to this base type (`dynamicItemAttributeMappings`), with the
    /// type each turns it into. For a mutated module the base type is the original, not the abyssal
    /// one. Unordered; `MutaplasmidTier` sorts by tier.
    static func mutaplasmids(for baseType: TypeID) -> SQLQuery<MutaplasmidRow> {
        let withType = DynamicItemAttributeMapping.all()
            .join(TypeInfo.self) { mapping, type in mapping.mutaplasmidID == type.id }
        let withName = withType
            .join(NameRow.self) { _, type, name in type.nameID == name.id }
        return withName
            .filter { mapping, _, _ in mapping.applicableTypeID == baseType }
            .select { mapping, _, name in
                MutaplasmidRow.projection(id: mapping.mutaplasmidID,
                                          name: name.text,
                                          englishName: name.textEn,
                                          resultingTypeID: mapping.resultingTypeID)
            }
            .query()
    }

    /// The names of these mutaplasmids.
    static func mutaplasmidNames(of types: [TypeID]) -> SQLQuery<MutaplasmidNameRow> {
        let withName = TypeInfo.all()
            .join(NameRow.self) { type, name in type.nameID == name.id }
        return withName
            .filter { type, _ in type.id.in(types) }
            .select { type, name in
                MutaplasmidNameRow.projection(id: type.id, name: name.text, englishName: name.textEn)
            }
            .query()
    }

    /// Which of these types some mutaplasmid applies to. One row per mapping, so a type repeats once
    /// per mutaplasmid; the caller builds a set.
    static func mutableTypes(among types: [TypeID]) -> SQLQuery<ItemIDRow> {
        DynamicItemAttributeMapping.all()
            .filter { mapping in mapping.applicableTypeID.in(types) }
            .select { mapping in ItemIDRow.projection(id: mapping.applicableTypeID) }
            .query()
    }

    /// The ranges of these mutaplasmids in attribute id order, the order the engine lists rolls in.
    static func mutaplasmidRanges(of mutaplasmids: [TypeID]) -> SQLQuery<MutaplasmidRangeRow> {
        let withAttribute = DynamicItemAttributeRange.all()
            .join(DogmaAttributeInfo.self) { range, attribute in range.attributeID == attribute.id }
        let withName = withAttribute
            .leftJoin(NameRow.self) { _, attribute, name in attribute.displayNameID == name.id }
        let withUnit = withName
            .leftJoin(DogmaUnitInfo.self) { _, attribute, _, unit in attribute.unitID == unit.id }
        let withUnitName = withUnit
            .leftJoin(NameRow.self) { _, _, _, unit, unitName in unit.displayNameID == unitName.id }
        return withUnitName
            .filter { range, _, _, _, _ in range.mutaplasmidID.in(mutaplasmids) }
            .select { range, attribute, name, unit, unitName in
                MutaplasmidRangeRow.projection(mutaplasmidID: range.mutaplasmidID,
                                               attributeID: range.attributeID,
                                               minMultiplier: range.min,
                                               maxMultiplier: range.max,
                                               name: attribute.name,
                                               displayName: name.text,
                                               unitID: unit.id,
                                               unitName: unitName.text)
            }
            .order(by: { range, _, _, _, _ in range.attributeID })
            .query()
    }

    // MARK: - Skills

    /// Direct skill requirements of a set of items (the hull, modules, charges and drones) in one
    /// query instead of `SDEBrowser.requiredSkills(of:)` per item.
    ///
    /// `itemID` and `name` serve callers listing one line per (item, skill). The skills screen
    /// collapses the rows to one level per skill, expands them through `SkillCatalog` and names the
    /// expanded set with `SDEBrowser.typeNames(of:)`.
    ///
    /// Direct requirements only; `SkillCatalog.expand` adds prerequisites.
    ///
    /// `published` is not checked, so unlisted skills still count toward the fit's demands.
    static func skills(requiredBy items: [TypeID]) -> SQLQuery<ItemSkillRow> {
        let withSkill = DogmaItemSkill.all()
            .join(TypeInfo.self) { requirement, skill in requirement.skillID == skill.id }
        let withName = withSkill
            .join(NameRow.self) { _, skill, name in skill.nameID == name.id }
        return withName
            .filter { requirement, _, _ in requirement.itemID.in(items) }
            .select { requirement, skill, name in
                ItemSkillRow.projection(id: skill.id,
                                        itemID: requirement.itemID,
                                        level: requirement.level,
                                        name: name.text)
            }
            .order(by: { _, _, name in name.ordinal })
            .query()
    }

    // MARK: - Shared filter

    /// Everything the picker refuses to show, in one expression.
    ///
    /// Only the structurally impossible is cut: the wrong kind of item, an item the hull is not
    /// listed for, a rig of the wrong size. CPU, power grid, calibration and `maxGroupFitted`
    /// depend on skills and the rest of the fit, and the engine reports them instead.
    ///
    /// `structureHull` is `true` for a structure (structure modules only), `false` for a ship
    /// (anything else) and `nil` without a hull (drones).
    ///
    /// `published` is checked by the callers: `dogmaItems` also holds unpublished types, the T3D
    /// tactical modes and the fit content kept for imported fits.
    ///
    /// The rig size and `structureHull` are bound constants, not `if`s, to keep one expression of
    /// one Swift type for all four callers; for non-rigs the term is a literal true that SQLite drops.
    private static func fits(_ item: TableRef<DogmaItem>,
                             kind: DogmaItemKind,
                             allowed: [TypeID],
                             rigSize: UInt8?,
                             structureHull: Bool?) -> some Expression<Bool> {
        let ignoresRigSize = ParameterExpression(value: kind != .rig && kind != .structureRig)
        let ignoresHullClass = ParameterExpression(value: structureHull == nil)
        let isStructureHull = ParameterExpression(value: structureHull == true)
        return item.kind == kind
            && (item.hasShipRestrictions == false || item.id.in(allowed))
            && (ignoresRigSize || item.rigSize == rigSize)
            && (ignoresHullClass || isStructureHull == item.id.in(structureModuleIDs()))
    }

    /// Every type of the structure-module category. A structure takes only these and a ship none,
    /// regardless of `hasShipRestrictions`; most ship modules and six structure modules are
    /// unrestricted. A subquery rather than a join so `fits` stays one expression over the item table.
    private static func structureModuleIDs() -> some Subquery<Scalar<TypeID>> {
        let withGroup = TypeInfo.all()
            .join(GroupInfo.self) { type, group in type.groupID == group.id }
        return withGroup
            .filter { _, group in group.categoryID == CategoryID.structureModule }
            .select { type, _ in type.id }
    }
}
