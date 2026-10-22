import DogmaPlanetary
import Foundation

// What the Planetary Interaction screens draw: plain, `Sendable` values worked out once per
// fetch (and per "now") by `PlanetaryAnalysis`, from `DogmaPlanetary`'s own simulation.
// Nothing from the engine travels past this file — no `Colony`, no `Forecast`, no pin
// indices — so a screen can neither run the simulation by accident nor hold on to engine
// state that the next refresh replaces.
//
// Every time-dependent figure is relative to `PlanetaryReport.now`. EVE recomputes a colony
// only when the player opens it in game, so everything after `lastUpdate` is simulated:
// first from `lastUpdate` to `now` (what has happened since), then from `now` on.

/// Every colony of one character, simulated up to `now` and on to each colony's horizon.
nonisolated struct PlanetaryReport: Sendable {
    var now: Date
    var colonies: [ColonyDetail]
    /// Colonies ESI reported but the model could not build — a layout that contradicts
    /// itself or the catalog. Shown as a row with the reason rather than dropped.
    var failures: [ColonyFailure]

    var overviews: [ColonyOverview] { colonies.map(\.overview) }

    /// Every upcoming event of every colony, soonest first — the notification schedule.
    var schedule: [ColonyEvent] {
        colonies.flatMap(\.events).sorted { $0.date < $1.date }
    }

    func colony(planetID: Int64) -> ColonyDetail? {
        colonies.first { $0.id == planetID }
    }
}

nonisolated struct ColonyFailure: Sendable, Hashable, Identifiable {
    var planet: PlanetInfo
    var lastUpdate: Date
    var reason: String
    var id: Int64 { planet.planetID }
}

// MARK: - Shared values

nonisolated enum PlanetKind: String, Sendable, Hashable, CaseIterable {
    case barren, gas, ice, lava, oceanic, plasma, storm, temperate
    case unknown

    /// The planet's typeID in the SDE (`Planet (Barren)` and so on).
    var typeID: TypeID? {
        switch self {
        case .temperate: 11
        case .ice: 12
        case .gas: 13
        case .oceanic: 2014
        case .lava: 2015
        case .barren: 2016
        case .storm: 2017
        case .plasma: 2063
        case .unknown: nil
        }
    }
}

nonisolated struct PlanetInfo: Sendable, Hashable {
    var planetID: Int64
    /// `Osoggur I`. `nil` when `/universe/planets` could not be reached.
    var name: String?
    var kind: PlanetKind
    var solarSystemID: Int64
    /// From the SDE; `nil` until it is open.
    var solarSystemName: String?
    var securityStatus: Double?
    var regionName: String?
    /// 0…5 — the command center upgrade level.
    var commandCenterLevel: Int
}

/// A P0…P4 commodity, named.
nonisolated struct PlanetaryCommodity: Sendable, Hashable, Identifiable {
    var typeID: TypeID
    var name: String
    /// 0 for raw resources (P0), 1…4 for P1…P4.
    var tier: Int
    /// m³ per unit.
    var volume: Double
    var id: TypeID { typeID }
}

nonisolated struct CommodityAmount: Sendable, Hashable {
    var commodity: PlanetaryCommodity
    var quantity: Int
    var volume: Double { Double(quantity) * commodity.volume }
}

// MARK: - The list row

nonisolated enum ColonyStatus: Sendable, Hashable {
    /// Extractors running, nothing about to overflow.
    case running
    /// A storage or the launchpad fills up, or output is already being lost, before the
    /// horizon.
    case filling
    /// Nothing runs at `now` and nothing will: programs ended, factories idle.
    case stopped
}

nonisolated struct ColonyOverview: Sendable, Hashable, Identifiable {
    var planet: PlanetInfo
    var status: ColonyStatus
    /// The list puts these first: anything but `.running`, or a part that is not set up.
    var needsAttention: Bool
    /// What the colony makes, top tier first. Usually one line.
    var products: [ProductRate]
    /// The one thing the row shows big — the most urgent issue, or when the extractors
    /// finish if nothing is wrong.
    var headline: ColonyIssue?
    /// Everything else worth a mention, most urgent first.
    var otherIssues: [ColonyIssue]
    var lastUpdate: Date
    var id: Int64 { planet.planetID }
}

nonisolated struct ProductRate: Sendable, Hashable {
    var commodity: PlanetaryCommodity
    /// Average from `now` to the horizon, units per hour — idle time included.
    var perHour: Double
    /// What the factories making it would do if they never waited for input.
    var nominalPerHour: Double
    /// Made between `lastUpdate` and `now`.
    var madeSinceUpdate: Int
    /// Made between `now` and the horizon.
    var madeToEnd: Int
}

/// Something the player should know about. `date` is when it happens (or happened — a storage
/// that filled before `now` keeps its date in the past).
nonisolated enum ColonyIssue: Sendable, Hashable {
    /// All extractor programs that run at `now` end by then.
    case extractorsFinish(at: Date, count: Int)
    /// No extractor runs at `now`; the last program ended then.
    case extractorsStopped(since: Date?)
    /// The storage first refuses cargo at that moment; from then on output with nowhere to go
    /// is lost.
    case storageFull(pinID: Int64, at: Date)
    /// Output first lost at that moment; `quantity` is the loss up to the horizon.
    case outputWasted(pinID: Int64, commodity: PlanetaryCommodity, at: Date, quantity: Int)
    /// A factory makes less than it could because an input does not arrive in time.
    /// `waitingFor` is the input it waits for, `limit` the commodity at the root of the
    /// shortage (the same, or a raw resource further up the chain); `share` is the part of
    /// the remaining time it waits.
    case outputLimited(pinID: Int64, product: PlanetaryCommodity, waitingFor: PlanetaryCommodity,
                       limit: PlanetaryCommodity, share: Double)
    /// A stock nothing in the colony produces runs out at that moment (an import on the
    /// launchpad, typically).
    case stockRunsOut(pinID: Int64, commodity: PlanetaryCommodity, at: Date)
    /// Stored, and no route takes it anywhere.
    case unusedStock(pinID: Int64, commodity: PlanetaryCommodity, quantity: Int)
    case extractorNotSetUp(pinID: Int64)
    case factoryNotSetUp(pinID: Int64)

    var date: Date? {
        switch self {
        case let .extractorsFinish(at, _): at
        case let .extractorsStopped(since): since
        case let .storageFull(_, at): at
        case let .outputWasted(_, _, at, _): at
        case let .stockRunsOut(_, _, at): at
        case .outputLimited, .unusedStock, .extractorNotSetUp, .factoryNotSetUp: nil
        }
    }

    /// `false` for the informational ones: a program end that is still ahead, unused stock,
    /// a factory that runs below capacity.
    var isWarning: Bool {
        switch self {
        case .extractorsFinish, .outputLimited, .unusedStock: false
        default: true
        }
    }

    var pinID: Int64? {
        switch self {
        case .extractorsFinish, .extractorsStopped: nil
        case let .storageFull(pin, _), let .outputWasted(pin, _, _, _), let .outputLimited(pin, _, _, _, _),
             let .stockRunsOut(pin, _, _), let .unusedStock(pin, _, _), let .extractorNotSetUp(pin),
             let .factoryNotSetUp(pin):
            pin
        }
    }
}

/// One entry of the notification schedule: something that happens after `now`.
nonisolated struct ColonyEvent: Sendable, Hashable, Identifiable {
    enum Kind: String, Sendable, Hashable {
        case extractorsFinish
        case storageFull
        /// A factory that will wait for input longer than `PlanetaryAnalysis.longWait`.
        case factoryStarved
        case outputLost
    }

    var kind: Kind
    var date: Date
    var planetID: Int64
    var planetName: String?
    var pinID: Int64?
    var commodity: PlanetaryCommodity?
    /// `extractorsFinish`: how many programs end at `date`.
    var count: Int = 1
    /// `factoryStarved`: how long the wait lasts (`nil` — not over before the horizon).
    var duration: TimeInterval?

    var id: String { "\(planetID)-\(kind.rawValue)-\(pinID ?? 0)-\(date.timeIntervalSince1970)" }
}

// MARK: - The colony screen

nonisolated struct ColonyDetail: Sendable, Identifiable {
    var overview: ColonyOverview
    var lastUpdate: Date
    var now: Date
    /// The latest extractor program end; `nil` when no program is set.
    var programEnd: Date?
    /// Where the forecast stops: `programEnd` if it is ahead, else a day after `now`.
    var horizon: Date
    var commandCenter: CommandCenterSummary
    /// Every issue, most urgent first (the overview's headline and others come from here).
    var issues: [ColonyIssue]
    /// Lost between `now` and the horizon, all sources together. Empty — nothing is wasted.
    var wastedToEnd: [CommodityAmount]
    var facilities: [FacilityDetail]
    var chain: ProductionChain
    /// Upcoming events, soonest first.
    var events: [ColonyEvent]
    /// What the model could not take as it is (an unknown commodity, a misaligned cycle).
    var warnings: [String]

    var id: Int64 { overview.id }
    var planet: PlanetInfo { overview.planet }
    /// How long the colony has been simulated past its last update.
    var simulatedFor: TimeInterval { max(0, now.timeIntervalSince(lastUpdate)) }

    func facility(pinID: Int64) -> FacilityDetail? {
        facilities.first { $0.id == pinID }
    }
}

nonisolated struct CommandCenterSummary: Sendable, Hashable {
    var level: Int
    var cpuUsed: Double
    var cpuTotal: Double
    var powerUsed: Double
    var powerTotal: Double
    var pinCount: Int
    var linkCount: Int
    var maxLinkLevel: Int
    /// km; `nil` without the planet's radius.
    var longestLink: Double?
    /// The planet's radius is not known, so links are costed without their length and the
    /// CPU and power figures above are too low.
    var isLinkCostEstimated: Bool
    var routeCount: Int
    var routesViaWaypoint: Int
}

// MARK: - Facilities

nonisolated enum FacilityKind: Sendable, Hashable {
    case commandCenter
    case extractor
    case basicIndustry
    case advancedIndustry
    case highTechIndustry
    case storage
    case launchpad

    var isFactory: Bool {
        self == .basicIndustry || self == .advancedIndustry || self == .highTechIndustry
    }

    var isStorage: Bool {
        self == .commandCenter || self == .storage || self == .launchpad
    }
}

nonisolated struct FacilityDetail: Sendable, Identifiable {
    /// `pin_id`.
    var id: Int64
    /// The in-game label, `G3-M5R`.
    var name: String
    var typeID: TypeID
    /// From the SDE, `Barren Storage Facility`; `nil` until it is open.
    var typeName: String?
    var kind: FacilityKind
    var routesIn: [RouteLine]
    var routesOut: [RouteLine]
    var role: Role

    enum Role: Sendable {
        case extractor(ExtractorDetail)
        case factory(FactoryDetail)
        /// Command center, storage facility, launchpad.
        case storage(StorageDetail)
    }
}

nonisolated struct RouteLine: Sendable, Hashable, Identifiable {
    var routeID: Int64
    /// The facility at the other end.
    var pinID: Int64
    var pinName: String
    var pinKind: FacilityKind
    var commodity: PlanetaryCommodity
    /// Pins the route passes through on the way, usually the command center.
    var waypoints: [Int64]
    var id: Int64 { routeID }
}

nonisolated struct ExtractorDetail: Sendable {
    enum State: Sendable, Hashable {
        case running
        case finished(at: Date)
        /// No program, or one ESI reports only in part — left out of the simulation.
        case notSetUp
    }

    struct Program: Sendable, Hashable {
        var installTime: Date
        var expiryTime: Date
        /// Seconds.
        var cycleTime: TimeInterval
        /// Yield of every cycle, in order — the bar chart.
        var yields: [Int]
        var total: Int
        var cycleCount: Int { yields.count }
    }

    var product: PlanetaryCommodity?
    var headCount: Int
    var maxHeads: Int
    var state: State
    var program: Program?
    /// The cycle running at `now` (0-based) and its bounds.
    var currentCycle: Int?
    var currentCycleStart: Date?
    var currentCycleEnd: Date?
    /// What the current cycle delivers at `currentCycleEnd`.
    var nextDelivery: Int?
    /// Cycles completed by `now`.
    var extractedSoFar: Int
    var stillToCome: Int
    /// Average over the rest of the program — the yield falls toward its end.
    var remainingPerHour: Double
    /// Average over the whole program.
    var programPerHour: Double
    var wastedToEnd: Int
}

nonisolated struct ActivitySpan: Sendable, Hashable {
    var start: Date
    var end: Date
    var isRunning: Bool
}

nonisolated struct FactoryDetail: Sendable {
    enum State: Sendable, Hashable {
        case running(cycleStart: Date, cycleEnd: Date)
        /// Waits for input since `since` (`nil` — since before the last update); starts again
        /// at `resumesAt` (`nil` — not before the horizon).
        case idle(since: Date?, resumesAt: Date?)
        case notSetUp
    }

    struct Input: Sendable, Hashable {
        var commodity: PlanetaryCommodity
        var perCycle: Int
        var perHour: Double
        /// In the factory's own buffer at `now`.
        var buffered: Int
        /// In the storages its routes draw from, at `now`.
        var inStorage: Int
    }

    var schematicID: Int?
    var output: CommodityAmount?
    var inputs: [Input]
    /// Seconds.
    var cycleTime: TimeInterval
    var state: State
    /// Inputs short of one cycle at `now`.
    var waitingFor: [PlanetaryCommodity]
    /// The commodity at the root of the shortage, traced up the chain.
    var limit: PlanetaryCommodity?
    var nominalPerHour: Double
    var averagePerHour: Double
    var madeSinceUpdate: Int
    var madeInDay: Int
    var madeToEnd: Int
    /// Running share of each window, 0…1.
    var utilizationSinceUpdate: Double
    var utilizationDay: Double
    var utilizationToEnd: Double
    /// Running and waiting spans from `now` to the horizon.
    var activity: [ActivitySpan]
    var wastedToEnd: Int
}

nonisolated struct StorageDetail: Sendable {
    struct Stock: Sendable, Hashable, Identifiable {
        var commodity: PlanetaryCommodity
        var quantity: Int
        var volume: Double
        /// Averages from `now` to the horizon.
        var inPerHour: Double
        var outPerHour: Double
        var atEnd: Int
        /// Lies here and no route takes it anywhere.
        var isUnused: Bool
        /// Nothing here at `now`, but it comes and goes.
        var isPassThrough: Bool
        var id: TypeID { commodity.typeID }
    }

    struct FillSample: Sendable, Hashable {
        var date: Date
        var volume: Double
        /// `false` — between the last update and `now`; `true` — after `now`.
        var isForecast: Bool
    }

    /// m³.
    var capacity: Double
    var usedNow: Double
    var usedAtEnd: Double
    var peak: Double
    var fillNow: Double { capacity > 0 ? usedNow / capacity : 0 }
    /// First refusal of cargo; may be before `now`. `nil` — never full before the horizon.
    var fullAt: Date?
    /// Volume in m³ per hour coming in, `now` to the horizon.
    var inflowPerHour: Double
    var contents: [Stock]
    /// From the last update to the horizon; one sample per change.
    var fill: [FillSample]
    /// What its suppliers lose between `now` and the horizon because it is full.
    var lostIfNotEmptied: [CommodityAmount]
    /// Customs export fee for what lies here now, at `PlanetaryAnalysis.assumedTaxRate`
    /// (the office's real rate is not in ESI).
    var exportFeeNow: Double
}

// MARK: - The production chain

nonisolated enum ChainWindow: String, Sendable, Hashable, CaseIterable {
    /// The state at `now`: running factories at their schematic rate, extractors at the
    /// yield of their current cycle. Counts in this window are per hour.
    case now
    /// `now` to 24 hours later.
    case day
    /// `now` to the horizon.
    case toEnd
}

nonisolated struct ProductionChain: Sendable {
    var nodes: [ChainNode]
    var edges: [ChainEdge]
    /// Per window, every commodity the colony makes or uses.
    var balances: [ChainWindow: [CommodityBalance]]
    /// What limits the top product, if anything does (`ColonyIssue.outputLimited.limit`).
    var bottleneck: PlanetaryCommodity?

    func node(id: String) -> ChainNode? {
        nodes.first { $0.id == id }
    }

    /// Node ids upstream and downstream of `id` — what the screen highlights on a tap.
    func path(through id: String) -> Set<String> {
        var result: Set<String> = [id]
        var frontier = [id]
        while let next = frontier.popLast() {
            for edge in edges where edge.from == next && result.insert(edge.to).inserted {
                frontier.append(edge.to)
            }
        }
        frontier = [id]
        var upstream: Set<String> = [id]
        while let next = frontier.popLast() {
            for edge in edges where edge.to == next && upstream.insert(edge.from).inserted {
                frontier.append(edge.from)
            }
        }
        return result.union(upstream)
    }
}

nonisolated struct ChainNode: Sendable, Identifiable {
    /// Stable within one report: `pin-<pin_id>` or `group-<first pin_id>`.
    var id: String
    /// Column of the flow, 0 = extraction, left to right. Factories of one tier share a
    /// column; a storage sits right of the highest tier it receives, so a hub that feeds back
    /// into an earlier column has edges that go backwards (`isHub`).
    var stage: Int
    var kind: FacilityKind
    /// The pins behind the node: identical factories (same schematic, same routes) are one
    /// node.
    var pinIDs: [Int64]
    var name: String
    /// What it makes (extractors, factories).
    var product: PlanetaryCommodity?
    /// A storage that feeds factories in an earlier column than its own.
    var isHub: Bool
    /// Extractor heads, summed over the group.
    var headCount: Int
    var figures: [ChainWindow: ChainFigures]
    var count: Int { pinIDs.count }
}

nonisolated struct ChainFigures: Sendable, Hashable {
    /// Output per hour (extractors, factories); m³ per hour in (storages).
    var perHour: Double
    /// Factories: running share, averaged over the group. Extractors: the part of the
    /// program done by the end of the window.
    var utilization: Double?
    /// Storages: fill at the end of the window, 0…1.
    var fill: Double?
    /// Storages: when it first refuses cargo within the window.
    var fullAt: Date?
    var wasted: Int
}

nonisolated struct ChainEdge: Sendable, Identifiable {
    var from: String
    var to: String
    var commodity: PlanetaryCommodity
    /// Units per hour.
    var perHour: [ChainWindow: Double]
    var id: String { "\(from)>\(to)>\(commodity.typeID.rawValue)" }
}

nonisolated struct CommodityBalance: Sendable, Hashable, Identifiable {
    var commodity: PlanetaryCommodity
    var made: Int
    var used: Int
    var wasted: Int
    /// Made − used − wasted: what piles up (positive) or is drawn down from stock.
    var balance: Int { made - used - wasted }
    var id: TypeID { commodity.typeID }
}
