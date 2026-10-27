import DogmaKit

/// The fit's value under a price table, summed over the snapshot.
nonisolated struct FitCost: Sendable, Equatable {
    /// A breakdown line, in editor order.
    nonisolated enum Group: Int, Sendable, CaseIterable, Identifiable {
        case hull, modules, charges, drones, implants, boosters
        var id: Int { rawValue }
    }

    nonisolated struct Line: Sendable, Equatable, Identifiable {
        var group: Group
        /// Item count; drone stacks and charge loads count each piece.
        var quantity: Int
        /// The summed value of the priced items.
        var value: Double
        var id: Group { group }
    }

    /// Non-empty groups, in `Group` order.
    var lines: [Line]
    /// Sum of all priced items; a lower bound when `unpricedTypes > 0`.
    var total: Double
    /// The number of types without a price; their items are excluded from `total`.
    var unpricedTypes: Int

    var isPartial: Bool { unpricedTypes > 0 }

    init(_ snapshot: FitSnapshot, price: (Int64) -> Double?) {
        var items: [Group: [(TypeID, Int)]] = [:]
        items[.hull] = [(snapshot.shipTypeID, 1)]
        items[.modules] = snapshot.modules.map { ($0.typeID, 1) }
        items[.charges] = snapshot.modules.compactMap { module in
            module.charge.map { ($0, max(module.chargeCount, 1)) }
        }
        items[.drones] = snapshot.drones.map { ($0.typeID, $0.count) }
        items[.implants] = snapshot.implants.map { ($0.typeID, 1) }
        items[.boosters] = snapshot.boosters.map { ($0.typeID, 1) }

        var unpriced: Set<TypeID> = []
        var lines: [Line] = []
        for group in Group.allCases {
            let entries = items[group] ?? []
            let quantity = entries.reduce(0) { $0 + $1.1 }
            guard quantity > 0 else { continue }
            var value = 0.0
            for (typeID, count) in entries {
                if let each = price(Int64(typeID.rawValue)) {
                    value += each * Double(count)
                } else {
                    unpriced.insert(typeID)
                }
            }
            lines.append(Line(group: group, quantity: quantity, value: value))
        }
        self.lines = lines
        total = lines.reduce(0) { $0 + $1.value }
        unpricedTypes = unpriced.count
    }
}
