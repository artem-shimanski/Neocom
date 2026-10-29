//
//  Queries.swift
//  SDE
//
//  Created by Artem Shimanski on 05.09.2026.
//

import LiteRow
import SDEModels

/// Item list row: the name from the language file, numbers from the derived fitting table, icon and
/// meta group from the catalog.
@Projection
public struct ItemListRow: Sendable {
    public var id: TypeID
    public var name: String
    public var iconID: IconID?
    public var metaGroupID: MetaGroupID?
    public var kind: DogmaItemKind
    public var cpu: Double?
    public var power: Double?
    /// Position in the current language's alphabet; the list is sorted by it.
    public var ordinal: UInt32
}

/// Ship list row: slots and budgets. Base values, without skills and subsystems.
@Projection
public struct ShipListRow: Sendable {
    public var id: TypeID
    public var name: String
    public var iconID: IconID?
    public var hiSlots: Int
    public var medSlots: Int
    public var lowSlots: Int
    public var rigSlots: Int
    public var turretHardpoints: Int
    public var launcherHardpoints: Int
    public var cpuOutput: Double
    public var powerOutput: Double
    public var ordinal: UInt32
}

/// List queries return published types only: the database also keeps unpublished fit content the
/// engine calculates, so that a fit carrying it still resolves names and icons by id.
public enum SDEQuery {

    // MARK: - Browsing

    /// PNG of a market group icon; empty if the database has no image for `iconID`.
    public static func iconImage(_ id: IconID) -> SQLQuery<IconImage> {
        IconImage.all()
            .filter { image in image.id == id }
            .limit(1)
            .query()
    }

    /// Items of one kind. Scans `dogmaItems` and the `kind` index.
    public static func items(kind: DogmaItemKind, limit: Int = 200) -> SQLQuery<ItemListRow> {
        // The chain is split into statements because of swiftlang/swift#78725: the pack and its
        // parsing in the closure cannot be kept in one expression, and the second `join` is not
        // inferred.
        let withType = DogmaItem.all()
            .join(TypeInfo.self) { item, type in item.id == type.id }
        let withName = withType
            .join(NameRow.self) { _, type, name in type.nameID == name.id }
        return withName
            .filter { item, type, _ in item.kind == kind && type.published == true }
            .select { item, type, name in listRow(item, type, name) }
            .order(by: { _, _, name in name.ordinal })
            .limit(limit)
            .query()
    }

    /// Everything under a market group, including nested ones, in one join over the closure table.
    public static func items(inMarketGroup group: MarketGroupID, limit: Int = 200) -> SQLQuery<ItemListRow> {
        let descendants = MarketGroupTree.all()
            .filter { tree in tree.ancestorID == group }
            .select { tree in tree.descendantID }
        let withType = DogmaItem.all()
            .join(TypeInfo.self) { item, type in item.id == type.id }
        let withName = withType
            .join(NameRow.self) { _, type, name in type.nameID == name.id }
        return withName
            .filter { _, type, _ in type.marketGroupID.in(descendants) && type.published == true }
            .select { item, type, name in listRow(item, type, name) }
            .order(by: { _, _, name in name.ordinal })
            .limit(limit)
            .query()
    }

    /// Items of `kind` that fit this ship.
    ///
    /// No rows in the restriction tables means "fits everyone", so the predicate is "no
    /// restrictions or the restriction is met". The `hasShipRestrictions` flag avoids both
    /// subqueries for unrestricted modules.
    public static func items(
        kind: DogmaItemKind,
        fitting ship: TypeID,
        of group: GroupID,
        limit: Int = 200
    ) -> SQLQuery<ItemListRow> {
        let allowedByType = DogmaItemShipType.all()
            .filter { link in link.shipTypeID == ship }
            .select { link in link.itemID }
        let allowedByGroup = DogmaItemShipGroup.all()
            .filter { link in link.shipGroupID == group }
            .select { link in link.itemID }
        let withType = DogmaItem.all()
            .join(TypeInfo.self) { item, type in item.id == type.id }
        let withName = withType
            .join(NameRow.self) { _, type, name in type.nameID == name.id }
        return withName
            .filter { item, type, _ in
                item.kind == kind
                    && type.published == true
                    && (item.hasShipRestrictions == false
                        || item.id.in(allowedByType)
                        || item.id.in(allowedByGroup))
            }
            .select { item, type, name in listRow(item, type, name) }
            .order(by: { _, _, name in name.ordinal })
            .limit(limit)
            .query()
    }

    /// Charges the module accepts.
    public static func charges(for module: TypeID, limit: Int = 200) -> SQLQuery<ItemListRow> {
        let groups = DogmaItemChargeGroup.all()
            .filter { link in link.itemID == module }
            .select { link in link.chargeGroupID }
        let withType = DogmaItem.all()
            .join(TypeInfo.self) { item, type in item.id == type.id }
        let withName = withType
            .join(NameRow.self) { _, type, name in type.nameID == name.id }
        return withName
            .filter { _, type, _ in type.groupID.in(groups) && type.published == true }
            .select { item, type, name in listRow(item, type, name) }
            .order(by: { _, _, name in name.ordinal })
            .limit(limit)
            .query()
    }

    /// Meta variants: T2, faction and abyssal versions of the same module.
    public static func variants(of parent: TypeID, limit: Int = 100) -> SQLQuery<ItemListRow> {
        let withType = DogmaItem.all()
            .join(TypeInfo.self) { item, type in item.id == type.id }
        let withName = withType
            .join(NameRow.self) { _, type, name in type.nameID == name.id }
        return withName
            .filter { _, type, _ in type.variationParentID == parent && type.published == true }
            .select { item, type, name in listRow(item, type, name) }
            .order(by: { item, _, _ in item.metaLevel })
            .limit(limit)
            .query()
    }

    // MARK: - Ships

    public static func ships(inMarketGroup group: MarketGroupID, limit: Int = 200) -> SQLQuery<ShipListRow> {
        let descendants = MarketGroupTree.all()
            .filter { tree in tree.ancestorID == group }
            .select { tree in tree.descendantID }
        let withType = DogmaShip.all()
            .join(TypeInfo.self) { ship, type in ship.id == type.id }
        let withName = withType
            .join(NameRow.self) { _, type, name in type.nameID == name.id }
        return withName
            .filter { _, type, _ in type.marketGroupID.in(descendants) && type.published == true }
            .select { ship, type, name in
                ShipListRow.projection(
                    id: ship.id,
                    name: name.text,
                    iconID: type.iconID,
                    hiSlots: ship.hiSlots,
                    medSlots: ship.medSlots,
                    lowSlots: ship.lowSlots,
                    rigSlots: ship.rigSlots,
                    turretHardpoints: ship.turretHardpoints,
                    launcherHardpoints: ship.launcherHardpoints,
                    cpuOutput: ship.cpuOutput,
                    powerOutput: ship.powerOutput,
                    ordinal: name.ordinal
                )
            }
            .order(by: { _, _, name in name.ordinal })
            .limit(limit)
            .query()
    }

    // MARK: - Search

    /// Search by name in the user's language and in English at once.
    ///
    /// Both columns are in one fts5 index, so there is one rank; weights are
    /// `SDEDatabase.searchRanking`. Ordered by `rank`, not alphabetically.
    public static func search(
        _ pattern: FTS5Pattern,
        kind: DogmaItemKind? = nil,
        limit: Int = 50
    ) -> SQLQuery<ItemListRow> {
        let withType = NameSearchIndex.all()
            .join(TypeInfo.self) { fts, type in fts.rowID(as: NameID.self) == type.nameID }
        let withItem = withType
            .join(DogmaItem.self) { _, type, item in type.id == item.id }
        let withName = withItem
            .join(NameRow.self) { _, type, _, name in type.nameID == name.id }
        var query = withName
            .filter { fts, _, _, _ in fts.match(pattern) && fts.ranked(by: SDEDatabase.searchRanking) }
            .filter { _, type, _, _ in type.published == true }
        if let kind {
            query = query.filter { _, _, item, _ in item.kind == kind }
        }
        return query
            .select { _, type, item, name in listRow(item, type, name) }
            .order(by: { fts, _, _, _ in fts.rank })
            .limit(limit)
            .query()
    }

    // MARK: - Common projection

    private static func listRow(
        _ item: TableRef<DogmaItem>,
        _ type: TableRef<TypeInfo>,
        _ name: TableRef<NameRow>
    ) -> Projection<ItemListRow> {
        ItemListRow.projection(
            id: item.id,
            name: name.text,
            iconID: type.iconID,
            metaGroupID: item.metaGroupID,
            kind: item.kind,
            cpu: item.cpu,
            power: item.power,
            ordinal: name.ordinal
        )
    }
}
