import AssetsKit
import BusinessKit
import LiteRow
import MarketKit
import Observation
import SDEKit
import SwiftUI

/// What the Market Orders screens read: the sheet's two lists plus names from the static data,
/// station names and each order's place in its region's book. The list never fetches a book;
/// `refreshPositions()` uses only books the market holds, no older than `bookTolerance`. The
/// detail screen loads its own (`loadDetail`).
@Observable
@MainActor
final class OrdersModel {
    struct TypeLabel {
        var name: String
        var group: String?
    }

    /// A cached book older than this is unreliable for undercut and outbid.
    private static let bookTolerance: TimeInterval = 3600

    let sheet: OrdersSheet
    private(set) var types: [Int64: TypeLabel] = [:]
    private(set) var systems: [Int64: MarketSystemRow] = [:]
    private(set) var regions: [Int64: String] = [:]
    /// Order id to its place in the book. Open orders only.
    private(set) var positions: [Int64: OrderBookPosition] = [:]
    /// Order id to the system of the best other order of its side, once its book was read.
    private(set) var bestSystems: [Int64: Int64] = [:]
    private(set) var bestPrices: [Int64: Double] = [:]

    @ObservationIgnored private let market: MarketSheet
    @ObservationIgnored private let characterSheet: CharacterSheet?
    @ObservationIgnored private let database: SDEDatabase?

    init(sheet: OrdersSheet, market: MarketSheet, characterSheet: CharacterSheet?, database: SDEDatabase?) {
        self.sheet = sheet
        self.market = market
        self.characterSheet = characterSheet
        self.database = database
    }

    // MARK: - Reading

    var open: [CharacterOrder] { sheet.open.value?.orders ?? [] }
    var history: [CharacterOrder] { sheet.history.value?.orders ?? [] }

    func order(id: Int64) -> CharacterOrder? {
        open.first { $0.id == id } ?? history.first { $0.id == id }
    }

    func typeName(_ order: CharacterOrder) -> String {
        types[order.typeID]?.name ?? "—"
    }

    /// The station or structure the order sits in, as named as it can be.
    func locationName(_ order: CharacterOrder) -> String {
        let info = locationInfo(order)
        if let name = info?.name { return name }
        if let name = market.stationNames[order.locationID] { return name }
        return String(localized: "Unknown Location")
    }

    func systemID(of order: CharacterOrder) -> Int64? {
        locationInfo(order)?.solarSystemID
    }

    func system(of order: CharacterOrder) -> MarketSystemRow? {
        systemID(of: order).flatMap { systems[$0] }
    }

    func regionName(_ order: CharacterOrder) -> String? {
        regions[order.regionID] ?? system(of: order)?.regionName
    }

    func position(of order: CharacterOrder) -> OrderBookPosition? { positions[order.id] }

    /// Jumps from the pilot's system to the order's, if both are known.
    func jumps(to order: CharacterOrder) -> Int? {
        guard let origin = pilotSystemID, let destination = systemID(of: order) else { return nil }
        return market.jumps(from: origin, to: destination)
    }

    func jumps(toSystem destination: Int64) -> Int? {
        pilotSystemID.flatMap { market.jumps(from: $0, to: destination) }
    }

    var pilotSystemID: Int64? { characterSheet?.currentSolarSystemID }

    var pilotSystem: MarketSystemRow? { pilotSystemID.flatMap { systems[$0] } }

    func isBookLoading(_ order: CharacterOrder) -> Bool {
        market.orders(typeID: order.typeID, regionID: order.regionID).state.isLoading
    }

    func bookError(_ order: CharacterOrder) -> (any Error)? {
        let book = market.orders(typeID: order.typeID, regionID: order.regionID)
        guard book.value == nil, case let .failed(error) = book.state else { return nil }
        return error
    }

    private func locationInfo(_ order: CharacterOrder) -> AssetLocationInfo? {
        sheet.open.value?.locations[order.locationID] ?? sheet.history.value?.locations[order.locationID]
    }

    // MARK: - Loading

    /// Names for everything the lists show; local and safe to call on every revision.
    func resolveNames() async {
        let orders = open + history
        guard !orders.isEmpty, let database else { return }

        let typeIDs = Set(orders.map(\.typeID)).filter { types[$0] == nil }.map { TypeID(rawValue: UInt32(clamping: $0)) }
        let systemIDs = Set(orders.compactMap(systemID(of:))).filter { systems[$0] == nil }.map(MarketFormat.systemID)
        let regionIDs = Set(orders.map(\.regionID)).filter { regions[$0] == nil }.map(MarketFormat.regionID)
        if !(typeIDs.isEmpty && systemIDs.isEmpty && regionIDs.isEmpty) {
            // Unstructured: the list's task is cancelled whenever a revision lands, and a read
            // cancelled with it would leave the names unresolved.
            let read = try? await Task { try await database.database.read { reader -> ([AssetTypeRow], [GroupHeader], [MarketSystemRow], [MarketRegionRow]) in
                let typeRows = try stride(from: 0, to: typeIDs.count, by: 500).flatMap {
                    try reader.fetchAll(AssetsBrowser.types(Array(typeIDs[$0..<min($0 + 500, typeIDs.count)])))
                }
                let groupIDs = Array(Set(typeRows.map(\.groupID)))
                let groups = groupIDs.isEmpty ? [] : try reader.fetchAll(AssetsBrowser.groups(groupIDs))
                let systemRows = systemIDs.isEmpty ? [] : try reader.fetchAll(MarketBrowser.systems(systemIDs))
                let regionRows = regionIDs.isEmpty ? [] : try reader.fetchAll(MarketBrowser.regions(regionIDs))
                return (typeRows, groups, systemRows, regionRows)
            } }.value
            if let (typeRows, groups, systemRows, regionRows) = read {
                let groupNames = Dictionary(groups.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
                for row in typeRows {
                    types[Int64(row.id.rawValue)] = TypeLabel(name: row.name, group: groupNames[row.groupID])
                }
                for row in systemRows { systems[Int64(row.id.rawValue)] = row }
                for row in regionRows { regions[Int64(row.id.rawValue)] = row.name }
            }
        }

        await market.resolveStationNames(orders.map(\.locationID))
    }

    /// Flags for the list from books the market holds; never asks ESI.
    func refreshPositions() {
        let now = Date.now
        for order in open {
            let book = market.orders(typeID: order.typeID, regionID: order.regionID)
            guard let fetchedAt = book.fetchedAt, now.timeIntervalSince(fetchedAt) < Self.bookTolerance,
                  let orders = book.value else { continue }
            apply(book: orders, to: order)
        }
    }

    /// The detail screen: the order's own book fresh, then the names and jumps around it.
    func loadDetail(_ order: CharacterOrder) async {
        await resolveNames()
        if order.state == .open {
            let book = market.orders(typeID: order.typeID, regionID: order.regionID)
            await book.ensureFresh()
            if let orders = book.value { apply(book: orders, to: order) }
            await resolveBestSystem(of: order)
        }
        if let characterSheet { await characterSheet.ensureLocationKnown() }
        var destinations: [Int64] = []
        if let id = systemID(of: order) { destinations.append(id) }
        if let id = bestSystems[order.id] { destinations.append(id) }
        if let origin = pilotSystemID {
            await market.resolveJumps(from: origin, to: destinations)
            await loadPilotSystem(origin)
        }
    }

    /// Pull-to-refresh on the detail screen: the order lists and the book.
    func refreshDetail(_ order: CharacterOrder) async {
        await sheet.refresh()
        if order.state == .open {
            let book = market.orders(typeID: order.typeID, regionID: order.regionID)
            await book.refresh()
        }
        await loadDetail(order)
    }

    private func apply(book: [MarketOrder], to order: CharacterOrder) {
        let entries = book.map { BookOrder(id: $0.id, isBuyOrder: $0.isBuyOrder, price: $0.price) }
        // The pilot's own orders are not competition.
        let position = OrderBookPosition(of: order, in: entries, ownOrderIDs: Set(open.map(\.id)))
        positions[order.id] = position
        if let best = position.bestOrderID, let other = book.first(where: { $0.id == best }) {
            bestSystems[order.id] = other.systemID
            bestPrices[order.id] = other.price
        } else {
            bestSystems[order.id] = nil
            bestPrices[order.id] = nil
        }
    }

    private func resolveBestSystem(of order: CharacterOrder) async {
        guard let id = bestSystems[order.id] else { return }
        await loadSystem(id)
    }

    private func loadPilotSystem(_ id: Int64) async { await loadSystem(id) }

    private func loadSystem(_ id: Int64) async {
        guard let database, systems[id] == nil else { return }
        let key = MarketFormat.systemID(id)
        if let rows = try? await database.database.read({ try $0.fetchAll(MarketBrowser.systems([key])) }) {
            for row in rows { systems[Int64(row.id.rawValue)] = row }
        }
    }
}
