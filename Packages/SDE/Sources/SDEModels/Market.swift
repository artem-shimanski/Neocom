//
//  Market.swift
//  SDE
//
//  Created by Artem Shimanski on 04.09.2026.
//

import LiteRow

@Table("marketGroups")
public struct MarketGroupInfo: Identifiable {
    @PrimaryKey public var id: MarketGroupID
    /// Parent in the market tree; `MarketGroupID`, not `GroupID`.
    @Index public var parentID: MarketGroupID? = nil
    public var nameID: NameID
    public var descriptionID: DescriptionID? = nil
    public var iconID: IconID? = nil
    /// Leaf group: contains types, not subgroups.
    public var hasTypes: Bool = false
}

/// Transitive closure of the market tree: a row for every "ancestor — descendant" pair, including
/// the pair with itself (`depth == 0`). Replaces recursive traversal with one join.
@Table("marketGroupTree")
public struct MarketGroupTree {
    @PrimaryKey public var ancestorID: MarketGroupID
    @PrimaryKey public var descendantID: MarketGroupID
    public var depth: Int = 0
}
