import Foundation

// How a production chain is laid out top to bottom (the "branched colony" screen): rows of
// nodes in flow order, and what crosses the step under each row. Worked out from the chain's
// own columns and edges — no simulation here, only grouping and sums of the rates the
// analysis already put on the edges.

nonisolated struct ChainLayout: Sendable {
    struct Row: Sendable, Identifiable {
        /// 0-based, top to bottom.
        var id: Int
        var nodes: [ChainNode]
        /// Storages are drawn across the width; everything else as tiles.
        var isStorage: Bool
        /// The facility kind the row is made of, for its caption. A mixed row (two factory kinds
        /// in one column, which the columns by tier do not produce) takes its first node's.
        var kind: FacilityKind
        /// The tier the row's factories make, for its caption: P1 for basic industry.
        var outputTier: Int?
        /// Pins behind the row's nodes.
        var pinCount: Int { nodes.reduce(0) { $0 + $1.count } }
    }

    /// What crosses the step under one row.
    struct Step: Sendable {
        /// Down to the rows below, summed per commodity tier, units per hour.
        var down: [TierFlow]
        /// Back up to a row at or above this one (a factory returning output to its hub).
        var back: [ReturnFlow]
        var isEmpty: Bool { down.isEmpty && back.isEmpty }
    }

    struct TierFlow: Sendable, Hashable {
        var tier: Int
        var perHour: Double
    }

    struct ReturnFlow: Sendable, Hashable {
        var tier: Int
        var perHour: Double
        /// The node the flow goes back to.
        var nodeID: String
    }

    var rows: [Row]
    /// Edges by source node, for the steps.
    private var edges: [ChainEdge]
    private var rowOf: [String: Int]

    /// Storages with no routes at all — usually the command center — are left out: they take
    /// no part in the flow.
    init(_ chain: ProductionChain) {
        let connected = Set(chain.edges.flatMap { [$0.from, $0.to] })
        let nodes = chain.nodes.filter { !$0.kind.isStorage || connected.contains($0.id) }
        let stageOf = Dictionary(nodes.map { ($0.id, $0.stage) }, uniquingKeysWith: { first, _ in first })

        // A hub — a storage that feeds an earlier column than its own — is drawn just above the
        // first column it feeds: then what it hands out flows down, and only what the factories
        // return to it goes back up.
        func position(_ node: ChainNode) -> Double {
            guard node.isHub else { return Double(node.stage) }
            let fed = chain.edges.filter { $0.from == node.id }.compactMap { stageOf[$0.to] }
            return (fed.min().map(Double.init) ?? Double(node.stage)) - 0.5
        }

        struct Key: Hashable, Comparable {
            var position: Double
            var isStorage: Bool
            static func < (lhs: Key, rhs: Key) -> Bool {
                (lhs.position, lhs.isStorage ? 1 : 0) < (rhs.position, rhs.isStorage ? 1 : 0)
            }
        }
        let grouped = Dictionary(grouping: nodes) { Key(position: position($0), isStorage: $0.kind.isStorage) }
        rows = grouped.keys.sorted().enumerated().map { offset, key in
            let members = grouped[key]!.sorted { lhs, rhs in
                // Extractors and factories by what they make, storages by kind.
                (lhs.product?.tier ?? 0, lhs.product?.name ?? lhs.name) < (rhs.product?.tier ?? 0, rhs.product?.name ?? rhs.name)
            }
            return Row(id: offset, nodes: members, isStorage: key.isStorage, kind: members[0].kind,
                       outputTier: key.isStorage || members[0].kind == .extractor ? nil : members.compactMap(\.product?.tier).max())
        }
        var rowOf: [String: Int] = [:]
        for row in rows {
            for node in row.nodes { rowOf[node.id] = row.id }
        }
        self.rowOf = rowOf
        edges = chain.edges
    }

    /// The flow under `row` in `window`.
    func step(after row: Int, window: ChainWindow) -> Step {
        var down: [Int: Double] = [:]
        var back: [ReturnKey: Double] = [:]
        for edge in edges {
            guard rowOf[edge.from] == row, let target = rowOf[edge.to] else { continue }
            let rate = edge.perHour[window] ?? 0
            guard rate > 0 else { continue }
            if target > row {
                down[edge.commodity.tier, default: 0] += rate
            } else {
                back[ReturnKey(tier: edge.commodity.tier, nodeID: edge.to), default: 0] += rate
            }
        }
        return Step(down: down.keys.sorted().map { TierFlow(tier: $0, perHour: down[$0]!) },
                    back: back.keys.sorted { ($0.tier, $0.nodeID) < ($1.tier, $1.nodeID) }
                        .map { ReturnFlow(tier: $0.tier, perHour: back[$0]!, nodeID: $0.nodeID) })
    }

    private struct ReturnKey: Hashable {
        var tier: Int
        var nodeID: String
    }
}

nonisolated extension ProductionChain {
    var layout: ChainLayout { ChainLayout(self) }

    /// Units per hour into and out of a node in `window`, over its routes.
    func throughput(of id: String, window: ChainWindow) -> (in: Double, out: Double) {
        var incoming = 0.0, outgoing = 0.0
        for edge in edges {
            let rate = edge.perHour[window] ?? 0
            if edge.to == id { incoming += rate }
            if edge.from == id { outgoing += rate }
        }
        return (incoming, outgoing)
    }

    /// The node a pin belongs to.
    func node(containing pinID: Int64) -> ChainNode? {
        nodes.first { $0.pinIDs.contains(pinID) }
    }
}
