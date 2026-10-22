import Foundation

/// A character's assets as a tree.
///
/// The roots are the places items lie in — a station, a structure, a solar system — that is,
/// every `locationID` that is not itself the `itemID` of another record. Below them the
/// records hang by `locationID`: a ship's modules below the ship, a container's contents below
/// the container.
///
/// Building is linear in the number of records and precomputes the search keys; it is meant to
/// run once per fetch, off the main actor. Queries are computed per call from the prepared
/// tables.
public struct AssetIndex: Sendable {
    public let summary: AssetSummary
    /// Every root location, by name.
    public let locations: [AssetLocation]
    /// The same locations grouped by region, regions by name; places with no known system
    /// come last, in a group whose `name` is `nil`.
    public let regions: [AssetRegion]

    private let records: [AssetRecord]
    private let types: [Int64: AssetTypeInfo]
    private let customNames: [Int64: String]
    private let indexByItem: [Int64: Int]
    private let children: [Int64: [Int]]
    /// Per record: how many records lie below it at any depth.
    private let descendants: [Int]
    /// Per record: whether it is its own row that opens.
    private let opens: [Bool]
    /// Per record: the root location it is in.
    private let rootOf: [Int64]
    private let locationByID: [Int64: AssetLocation]
    /// Folded type name and group name, per type.
    private let typeKeys: [Int64: String]
    /// Folded custom name, per record index — only records that have one.
    private let customKeys: [Int: String]
    /// Folded location name and system name, per root.
    private let rootKeys: [Int64: String]

    /// - Parameters:
    ///   - records: every record of every page. A record repeated across pages is kept once.
    ///   - customNames: names the player gave to ships and containers, by item id. `"None"`
    ///     and empty names — what ESI answers for an unnamed item — are ignored.
    ///   - locations: the roots the app could name. A root missing here is guessed from its
    ///     id and `location_type`.
    ///   - systems: solar systems by id, for the locations' system, security and region.
    ///   - types: what the static data says about each type. A type missing here still gets
    ///     a row, under a placeholder name.
    public init(records: [AssetRecord],
                customNames: [Int64: String] = [:],
                locations: [Int64: AssetLocationInfo] = [:],
                systems: [Int64: AssetSolarSystem] = [:],
                types: [Int64: AssetTypeInfo]) {
        var unique: [AssetRecord] = []
        unique.reserveCapacity(records.count)
        var indexByItem: [Int64: Int] = [:]
        indexByItem.reserveCapacity(records.count)
        for record in records where indexByItem[record.itemID] == nil {
            indexByItem[record.itemID] = unique.count
            unique.append(record)
        }
        self.records = unique
        self.indexByItem = indexByItem
        self.types = types
        self.customNames = customNames.filter { !$0.value.isEmpty && $0.value != "None" }

        func type(_ id: Int64) -> AssetTypeInfo { types[id] ?? Self.placeholder(id) }

        var children: [Int64: [Int]] = [:]
        var rootTypes: [Int64: String] = [:]
        var rootOrder: [Int64] = []
        for (index, record) in unique.enumerated() {
            children[record.locationID, default: []].append(index)
            if indexByItem[record.locationID] == nil, rootTypes[record.locationID] == nil {
                rootTypes[record.locationID] = record.locationType
                rootOrder.append(record.locationID)
            }
        }
        self.children = children

        var opens = [Bool](repeating: false, count: unique.count)
        for (index, record) in unique.enumerated() where record.isSingleton {
            let info = type(record.typeID)
            opens[index] = info.categoryID == AssetCategory.ship
                || AssetCategory.containerGroups.contains(info.groupID)
                || record.typeID == AssetCategory.assetSafetyWrap
                || children[record.itemID] != nil
        }
        self.opens = opens

        // Depth-first from every root: which root each record is in, and how many records
        // lie below it. Iterative, so a deep chain cannot overflow the stack; a record caught
        // in a cycle is never reached from a root and simply stays out of the tree.
        var rootOf = [Int64](repeating: 0, count: unique.count)
        var descendants = [Int](repeating: 0, count: unique.count)
        var visited = [Bool](repeating: false, count: unique.count)
        for root in rootOrder {
            var stack: [(index: Int, expanded: Bool)] = (children[root] ?? []).map { ($0, false) }
            while let (index, expanded) = stack.popLast() {
                let itemID = unique[index].itemID
                if expanded {
                    descendants[index] = (children[itemID] ?? []).reduce(0) { $0 + 1 + descendants[$1] }
                    continue
                }
                guard !visited[index] else { continue }
                visited[index] = true
                rootOf[index] = root
                stack.append((index, true))
                for child in children[itemID] ?? [] where !visited[child] {
                    stack.append((child, false))
                }
            }
        }
        self.rootOf = rootOf
        self.descendants = descendants

        // Per-location totals and the overall summary.
        var itemCount: [Int64: Int] = [:]
        var shipCount: [Int64: Int64] = [:]
        var containerCount: [Int64: Int] = [:]
        var summary = AssetSummary(locations: rootOrder.count)
        for (index, record) in unique.enumerated() where visited[index] {
            let root = rootOf[index]
            let info = type(record.typeID)
            itemCount[root, default: 0] += 1
            summary.items += 1
            if info.categoryID == AssetCategory.ship {
                let quantity = max(record.quantity, 1)
                shipCount[root, default: 0] += quantity
                summary.ships += quantity
            } else if opens[index] {
                containerCount[root, default: 0] += 1
            }
            if record.isBlueprintCopy { summary.blueprintCopies += 1 }
        }
        self.summary = summary

        var locationByID: [Int64: AssetLocation] = [:]
        for root in rootOrder {
            let info = locations[root] ?? AssetLocationInfo.guess(id: root, locationType: rootTypes[root] ?? "")
            let systemID = info.solarSystemID ?? (info.kind == .solarSystem ? root : nil)
            let system = systemID.flatMap { systems[$0] }
            let name = info.name ?? (info.kind == .solarSystem ? system?.name : nil)
            locationByID[root] = AssetLocation(id: root,
                                               kind: info.kind,
                                               name: name,
                                               solarSystemID: systemID,
                                               system: system,
                                               itemCount: itemCount[root] ?? 0,
                                               shipCount: shipCount[root] ?? 0,
                                               containerCount: containerCount[root] ?? 0)
        }
        self.locationByID = locationByID

        let sorted = locationByID.values.sorted(by: Self.locationOrder)
        self.locations = sorted
        var byRegion: [String: [AssetLocation]] = [:]
        var unplaced: [AssetLocation] = []
        for location in sorted {
            if let region = location.system?.regionName {
                byRegion[region, default: []].append(location)
            } else {
                unplaced.append(location)
            }
        }
        var regions = byRegion
            .map { AssetRegion(name: $0.key, locations: $0.value) }
            .sorted { ($0.name ?? "").localizedStandardCompare($1.name ?? "") == .orderedAscending }
        if !unplaced.isEmpty { regions.append(AssetRegion(name: nil, locations: unplaced)) }
        self.regions = regions

        // Search keys, folded once.
        var typeKeys: [Int64: String] = [:]
        for record in unique where typeKeys[record.typeID] == nil {
            let info = type(record.typeID)
            typeKeys[record.typeID] = Self.fold(info.name + "\n" + info.groupName)
        }
        self.typeKeys = typeKeys
        var customKeys: [Int: String] = [:]
        for (itemID, name) in self.customNames {
            if let index = indexByItem[itemID] { customKeys[index] = Self.fold(name) }
        }
        self.customKeys = customKeys
        var rootKeys: [Int64: String] = [:]
        for (id, location) in locationByID {
            rootKeys[id] = Self.fold([location.name, location.system?.name].compactMap { $0 }.joined(separator: "\n"))
        }
        self.rootKeys = rootKeys
    }

    // MARK: - Lookup

    public func location(_ id: Int64) -> AssetLocation? {
        locationByID[id]
    }

    /// The row of one item on its own — the header of a ship or container screen.
    public func item(_ itemID: Int64) -> AssetRow? {
        indexByItem[itemID].map { makeRow([$0]) }
    }

    /// Where an item is. `nil` for an id that is not an item.
    public func path(to itemID: Int64) -> AssetPath? {
        guard let index = indexByItem[itemID] else { return nil }
        return AssetPath(location: locationByID[rootOf[index]], parents: parents(of: index))
    }

    // MARK: - Contents

    /// What lies in a root location, a container or a ship, as titled sections.
    ///
    /// For a location or a container: ships first, containers next, then one section per
    /// category; items under a flag that is not a hangar (Deliveries, Asset Safety, …) go to a
    /// section named after the flag. For a ship: one section per rack and bay, by flag. Items
    /// that open are rows of their own; everything else is stacked by type.
    ///
    /// A ship whose hull numbers are known always lists its high, medium and low slots, rigs,
    /// subsystems, service slots, drone and fighter bays and cargo where the hull has any —
    /// empty ones included, with their `capacity`.
    public func contents(of id: Int64) -> [AssetSection] {
        let hull = indexByItem[id].map { type(records[$0].typeID) }.flatMap { $0.categoryID == AssetCategory.ship ? $0 : nil }
        let isShip = hull != nil && indexByItem[id].map { records[$0].isSingleton } == true

        var buckets: [AssetSection.Kind: [StackKey: [Int]]] = [:]
        var categoryNames: [Int64: String] = [:]
        for index in children[id] ?? [] {
            let (kind, key) = bucket(of: index)
            buckets[kind, default: [:]][key, default: []].append(index)
            if case let .category(categoryID) = kind {
                categoryNames[categoryID] = type(records[index].typeID).categoryName
            }
        }

        let slots = isShip ? hull?.slots.map { fittedSlots($0, ship: id) } : nil
        if let slots {
            let racks: [(AssetSection.Kind, Bool)] = [
                (.highSlots, slots.high > 0), (.mediumSlots, slots.medium > 0),
                (.lowSlots, slots.low > 0), (.rigSlots, slots.rig > 0),
                (.subsystemSlots, slots.subsystem > 0), (.serviceSlots, slots.service > 0),
                (.droneBay, (slots.droneCapacity ?? 0) > 0), (.fighterBay, (slots.fighterCapacity ?? 0) > 0),
                (.cargo, (hull?.capacity ?? 0) > 0),
            ]
            for (kind, present) in racks where present && buckets[kind] == nil {
                buckets[kind] = [:]
            }
        }

        var sections = buckets.map { kind, stacks in
            let rows = stacks.values.map { makeRow($0) }.sorted(by: Self.rowOrder)
            let categoryName: String? = if case let .category(categoryID) = kind { categoryNames[categoryID] } else { nil }
            return AssetSection(kind: kind,
                                title: AssetFlag.title(of: kind, categoryName: categoryName),
                                rows: rows,
                                capacity: isShip ? capacity(of: kind, rows: rows, hull: hull, slots: slots) : nil)
        }
        sections.sort { lhs, rhs in
            let (left, right) = (AssetFlag.rank(of: lhs.kind), AssetFlag.rank(of: rhs.kind))
            if left != right { return left < right }
            return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
        }
        return sections
    }

    // MARK: - Fitting

    /// An assembled ship as a game fitting: the hull, and what is in its slots, drone bay and
    /// fighter bay — cargo and other holds are not part of a fit. Modules of the same type in
    /// the same flag are merged; charges stay in the flag of the module they are loaded in.
    /// `nil` for anything that is not an assembled ship.
    public func fitting(ofShip itemID: Int64) -> AssetFitting? {
        guard let index = indexByItem[itemID] else { return nil }
        let ship = records[index]
        let hull = type(ship.typeID)
        guard ship.isSingleton, hull.categoryID == AssetCategory.ship else { return nil }

        var order: [FittingKey] = []
        var quantities: [FittingKey: Int64] = [:]
        for child in children[itemID] ?? [] {
            let record = records[child]
            guard AssetFlag.isFittingFlag(record.locationFlag) else { continue }
            let flag = record.locationFlag.hasPrefix("FighterTube") ? "FighterBay" : record.locationFlag
            let key = FittingKey(typeID: record.typeID, flag: flag)
            if quantities[key] == nil { order.append(key) }
            quantities[key, default: 0] += max(record.quantity, 1)
        }
        return AssetFitting(shipItemID: itemID,
                            shipTypeID: ship.typeID,
                            name: customNames[itemID] ?? hull.name,
                            items: order.map { AssetFitting.Item(typeID: $0.typeID, flag: $0.flag, quantity: quantities[$0] ?? 0) })
    }

    // MARK: - Search

    /// Items whose type name, custom name or group name — or whose location's or system's
    /// name — contain every word of `query`, ignoring case and diacritics. Grouped by root
    /// location in the order of `locations`; stacks are the same as on the screens, so seven
    /// packaged Velators in one hangar are one hit.
    ///
    /// - Parameter limit: stop after this many hits, for a query that matches half the
    ///   hangar. `nil` returns every hit.
    public func search(_ query: String, limit: Int? = nil) -> [AssetSearchResult] {
        let terms = Self.fold(query)
            .split(whereSeparator: \.isWhitespace)
            .prefix(16)
            .map(String.init)
        guard !terms.isEmpty else { return [] }
        let all: UInt16 = terms.count == 16 ? .max : (1 << UInt16(terms.count)) - 1

        func mask(_ key: String) -> UInt16 {
            var result: UInt16 = 0
            for (offset, term) in terms.enumerated() where key.contains(term) {
                result |= 1 << UInt16(offset)
            }
            return result
        }
        let typeMasks = typeKeys.mapValues(mask)
        let rootMasks = rootKeys.mapValues(mask)

        // Matching records, bucketed by the parent they lie in and the row they make there.
        var groups: [Int64: [HitKey: [Int]]] = [:]
        var hitCount = 0
        for index in records.indices {
            let record = records[index]
            guard let rootMask = rootMasks[rootOf[index]] else { continue }
            var matched = (typeMasks[record.typeID] ?? 0) | rootMask
            if matched != all, let custom = customKeys[index] { matched |= mask(custom) }
            guard matched == all else { continue }
            let (kind, stack) = bucket(of: index)
            let key = HitKey(parent: record.locationID, kind: kind, stack: stack)
            if groups[rootOf[index], default: [:]][key] == nil {
                if let limit, hitCount >= limit { continue }
                hitCount += 1
            }
            groups[rootOf[index], default: [:]][key, default: []].append(index)
        }

        return locations.compactMap { location in
            guard let buckets = groups[location.id] else { return nil }
            let hits = buckets.values
                .map { indices in AssetSearchHit(row: makeRow(indices), parents: parents(of: indices[0])) }
                .sorted { lhs, rhs in
                    if lhs.parents.count != rhs.parents.count { return lhs.parents.count < rhs.parents.count }
                    return Self.rowOrder(lhs.row, rhs.row)
                }
            return AssetSearchResult(location: location, hits: hits)
        }
    }

    // MARK: - Internals

    private struct StackKey: Hashable {
        var typeID: Int64
        var isBlueprintCopy: Bool
        /// Set for a record that opens: it is a row of its own.
        var itemID: Int64?
    }

    private struct HitKey: Hashable {
        var parent: Int64
        var kind: AssetSection.Kind
        var stack: StackKey
    }

    private struct FittingKey: Hashable {
        var typeID: Int64
        var flag: String
    }

    private func type(_ id: Int64) -> AssetTypeInfo {
        types[id] ?? Self.placeholder(id)
    }

    private static func placeholder(_ id: Int64) -> AssetTypeInfo {
        let name = id == AssetCategory.assetSafetyWrap ? "Asset Safety Wrap" : "Type \(id)"
        return AssetTypeInfo(typeID: id, name: name, groupID: -1, groupName: "", categoryID: -1, categoryName: "Other")
    }

    /// The section a record goes to, and the row it is part of there.
    private func bucket(of index: Int) -> (AssetSection.Kind, StackKey) {
        let record = records[index]
        let info = type(record.typeID)
        let key = StackKey(typeID: record.typeID,
                           isBlueprintCopy: record.isBlueprintCopy,
                           itemID: opens[index] ? record.itemID : nil)
        if let rack = AssetFlag.shipSection(record.locationFlag) {
            return (rack, key)
        }
        guard AssetFlag.looseFlags.contains(record.locationFlag) else {
            return (.flag(record.locationFlag), key)
        }
        if info.categoryID == AssetCategory.ship { return (.ships, key) }
        if opens[index] { return (.containers, key) }
        return (.category(info.categoryID), key)
    }

    private func makeRow(_ indices: [Int]) -> AssetRow {
        let first = records[indices[0]]
        let info = type(first.typeID)
        let opensAlone = indices.count == 1 && opens[indices[0]]
        let customName = indices.count == 1 ? customNames[first.itemID] : nil
        let kind: AssetRow.Kind = opensAlone ? (info.categoryID == AssetCategory.ship ? .ship : .container) : .item
        return AssetRow(id: first.itemID,
                        itemIDs: indices.map { records[$0].itemID },
                        kind: kind,
                        typeID: first.typeID,
                        name: customName ?? info.name,
                        customName: customName,
                        typeName: info.name,
                        groupID: info.groupID,
                        groupName: info.groupName,
                        categoryID: info.categoryID,
                        categoryName: info.categoryName,
                        quantity: indices.reduce(0) { $0 + max(records[$1].quantity, 1) },
                        isBlueprintCopy: first.isBlueprintCopy,
                        isAssembled: indices.allSatisfy { records[$0].isSingleton },
                        flag: first.locationFlag,
                        childCount: opensAlone ? (children[first.itemID]?.count ?? 0) : 0,
                        nestedCount: opensAlone ? descendants[indices[0]] : 0)
    }

    /// The ships and containers around a record, outermost first.
    private func parents(of index: Int) -> [AssetRow] {
        var result: [AssetRow] = []
        var seen: Set<Int64> = []
        var location = records[index].locationID
        while let parent = indexByItem[location], seen.insert(location).inserted {
            result.append(makeRow([parent]))
            location = records[parent].locationID
        }
        return result.reversed()
    }

    /// The hull's slots plus what its fitted subsystems add: a Strategic Cruiser's hull has no
    /// high, medium or low slots of its own.
    private func fittedSlots(_ hullSlots: AssetTypeInfo.Slots, ship itemID: Int64) -> AssetTypeInfo.Slots {
        var slots = hullSlots
        for child in children[itemID] ?? [] {
            let record = records[child]
            guard AssetFlag.shipSection(record.locationFlag) == .subsystemSlots,
                  let modifiers = type(record.typeID).slotModifiers else { continue }
            slots.high += modifiers.high
            slots.medium += modifiers.medium
            slots.low += modifiers.low
        }
        return slots
    }

    private func capacity(of kind: AssetSection.Kind, rows: [AssetRow], hull: AssetTypeInfo?,
                          slots: AssetTypeInfo.Slots?) -> AssetCapacity? {
        guard let hull, let slots else {
            if case .cargo = kind, let total = hull?.capacity { return .volume(used: volume(of: rows), total: total) }
            return nil
        }
        // A rack never reads fuller than it is: when the supplied numbers fall short (a
        // modifier the caller did not know), the total is at least what is fitted.
        func rack(_ total: Int) -> AssetCapacity {
            let used = Int(rows.filter { !$0.isCharge }.reduce(Int64(0)) { $0 + $1.quantity })
            return .slots(used: used, total: max(total, used))
        }
        switch kind {
        case .highSlots: return rack(slots.high)
        case .mediumSlots: return rack(slots.medium)
        case .lowSlots: return rack(slots.low)
        case .rigSlots: return rack(slots.rig)
        case .subsystemSlots: return rack(slots.subsystem)
        case .serviceSlots: return rack(slots.service)
        case .droneBay: return slots.droneCapacity.map { .volume(used: volume(of: rows), total: $0) }
        case .fighterBay: return slots.fighterCapacity.map { .volume(used: volume(of: rows), total: $0) }
        case .cargo: return hull.capacity.map { .volume(used: volume(of: rows), total: $0) }
        default: return nil
        }
    }

    private func volume(of rows: [AssetRow]) -> Double {
        rows.reduce(0) { $0 + Double($1.quantity) * (types[$1.typeID]?.volume ?? 0) }
    }

    private static func rowOrder(_ lhs: AssetRow, _ rhs: AssetRow) -> Bool {
        if lhs.opens != rhs.opens { return lhs.opens }
        switch lhs.name.localizedStandardCompare(rhs.name) {
        case .orderedAscending: return true
        case .orderedDescending: return false
        case .orderedSame: return lhs.id < rhs.id
        }
    }

    private static func locationOrder(_ lhs: AssetLocation, _ rhs: AssetLocation) -> Bool {
        switch (lhs.name, rhs.name) {
        case let (left?, right?):
            let order = left.localizedStandardCompare(right)
            return order == .orderedSame ? lhs.id < rhs.id : order == .orderedAscending
        case (.some, nil): return true
        case (nil, .some): return false
        case (nil, nil): return lhs.id < rhs.id
        }
    }

    static func fold(_ string: String) -> String {
        string.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
    }
}
