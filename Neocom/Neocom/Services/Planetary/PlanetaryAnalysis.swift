import DogmaPlanetary
import Foundation

/// Names the analysis puts on what it reports, read out of the SDE beforehand
/// (`PlanetaryReport.make`). Kept as plain dictionaries so the analysis itself needs no
/// database — and runs the same in a preview.
nonisolated struct PlanetaryNames: Sendable {
    struct System: Sendable, Hashable {
        var name: String
        var securityStatus: Double
        var regionName: String
    }

    var types: [TypeID: String] = [:]
    var systems: [Int64: System] = [:]
}

/// ESI colonies → the values in `PlanetaryReport.swift`.
///
/// All of the arithmetic is `DogmaPlanetary`'s: the colony is restored from its snapshot once,
/// simulated from `last_update` to `now` (what has happened since the player last opened it in
/// game), and from `now` on in two independent copies of the simulation — to a day ahead and
/// to the horizon. Everything here only reads the resulting `Forecast`s and colonies: which
/// pin was busy, what was made, what was lost, when a storage filled.
nonisolated enum PlanetaryAnalysis {
    /// A factory that will wait longer than this gets a notification of its own.
    static let longWait: TimeInterval = 2 * 3600
    /// A top-tier factory that waits for this share of the remaining time or more gets an
    /// `outputLimited` issue.
    static let limitedShare = 0.25
    /// Customs tax for the export estimate: the office's real rate is not in ESI.
    static let assumedTaxRate = 0.10
    /// The forecast for a colony with no program running ahead.
    static let idleHorizon: TimeInterval = 86_400

    static func report(colonies: [ESIColony],
                       catalog: PlanetaryCatalog,
                       names: PlanetaryNames,
                       now: Date) -> PlanetaryReport {
        var details: [ColonyDetail] = []
        var failures: [ColonyFailure] = []
        for colony in colonies {
            do {
                details.append(try analyze(colony, catalog: catalog, names: names, now: now))
            } catch {
                failures.append(ColonyFailure(planet: planetInfo(colony, names: names),
                                              lastUpdate: colony.lastUpdate,
                                              reason: String(describing: error)))
            }
        }
        return PlanetaryReport(now: now, colonies: details, failures: failures)
    }

    static func analyze(_ esi: ESIColony,
                        catalog: PlanetaryCatalog,
                        names: PlanetaryNames,
                        now: Date) throws(ColonyError) -> ColonyDetail {
        let colony = try Colony(snapshot: ColonySnapshot(esi), catalog: catalog)
        var builder = Builder(esi: esi, colony: colony, names: names, now: now)
        return builder.build()
    }

    static func planetInfo(_ esi: ESIColony, names: PlanetaryNames) -> PlanetInfo {
        let system = names.systems[esi.solarSystemID]
        return PlanetInfo(planetID: esi.planetID,
                          name: esi.planetName,
                          kind: PlanetKind(esi: esi.planetType),
                          solarSystemID: esi.solarSystemID,
                          solarSystemName: system?.name,
                          securityStatus: system?.securityStatus,
                          regionName: system?.regionName,
                          commandCenterLevel: esi.upgradeLevel)
    }
}

// MARK: - Builder

nonisolated private struct Builder {
    typealias PinIndex = Colony.PinIndex

    let esi: ESIColony
    let names: PlanetaryNames
    let catalog: PlanetaryCatalog
    let now: Date
    let horizon: Date
    let programEnd: Date?

    /// At the snapshot, at `now`, a day after `now`, at the horizon.
    let snapshot: Colony
    let current: Colony
    let dayColony: Colony
    let final: Colony

    /// `(lastUpdate, now]`, `(now, now + 24 h]`, `(now, horizon]`.
    let elapsed: Forecast
    let day: Forecast
    let toEnd: Forecast

    // Filled while building, read by the chain and the issues.
    private var waitTime: [Int: [TypeID: TimeInterval]] = [:]
    private var activity: [Int: [ActivitySpan]] = [:]

    init(esi: ESIColony, colony: Colony, names: PlanetaryNames, now requested: Date) {
        self.esi = esi
        self.names = names
        self.catalog = colony.catalog
        self.snapshot = colony
        // A clock behind the server's would put `now` before the snapshot.
        let now = max(requested, colony.snapshotTime)
        self.now = now

        let ends = colony.pins.compactMap { pin -> Date? in
            guard case .extractor(let extractor) = pin.role, let program = extractor.program else { return nil }
            return program.cycleCount > 0 ? program.cycleEnd(program.cycleCount - 1) : program.expiryTime
        }
        programEnd = ends.max()
        if let programEnd, programEnd > now {
            horizon = programEnd
        } else {
            horizon = now.addingTimeInterval(PlanetaryAnalysis.idleHorizon)
        }

        let options = ColonySimulation.Options(timeline: true)
        var simulation = ColonySimulation(colony)
        elapsed = simulation.run(until: now, options: options)
        current = simulation.colony

        var daySimulation = simulation
        day = daySimulation.run(until: now.addingTimeInterval(86_400), options: options)
        dayColony = daySimulation.colony

        var endSimulation = simulation
        toEnd = endSimulation.run(until: horizon, options: options)
        final = endSimulation.colony
    }

    // MARK: Values

    func commodity(_ typeID: TypeID) -> PlanetaryCommodity {
        let info = catalog.commodity(typeID)
        return PlanetaryCommodity(typeID: typeID,
                                  name: names.types[typeID] ?? String(localized: "Type \(typeID.rawValue)"),
                                  tier: Int(info?.tier.rawValue ?? 0),
                                  volume: info?.volume ?? 0)
    }

    func amounts(_ inventory: Inventory) -> [CommodityAmount] {
        inventory.map { CommodityAmount(commodity: commodity($0.typeID), quantity: $0.quantity) }
            .sorted { $0.volume > $1.volume }
    }

    func kind(of pin: Colony.Pin) -> FacilityKind {
        switch pin.kind {
        case .commandCenter: return .commandCenter
        case .storage: return .storage
        case .launchpad: return .launchpad
        case .extractor: return .extractor
        case .processor:
            let tier = catalog.schematics(for: pin.typeID)
                .compactMap { catalog.commodity($0.output.typeID)?.tier }
                .max() ?? .p1
            switch tier {
            case .p0, .p1: return .basicIndustry
            case .p4: return .highTechIndustry
            case .p2, .p3: return .advancedIndustry
            }
        }
    }

    func hours(_ forecast: Forecast) -> Double {
        forecast.duration / 3600
    }

    func perHour(_ quantity: Int, _ forecast: Forecast) -> Double {
        let hours = hours(forecast)
        return hours > 0 ? Double(quantity) / hours : 0
    }

    var pinIndices: [PinIndex] { snapshot.pins.map(\.id) }

    func schematic(_ pin: PinIndex) -> DogmaPlanetaryData.Schematic? {
        snapshot.schematic(of: pin)
    }

    func program(_ pin: PinIndex) -> ExtractorProgram? {
        guard case .extractor(let extractor) = snapshot[pin].role else { return nil }
        return extractor.program
    }

    func product(_ pin: PinIndex) -> TypeID? {
        switch snapshot[pin].role {
        case .extractor(let extractor): extractor.program == nil ? nil : extractor.productTypeID
        case .processor: schematic(pin)?.output.typeID
        case .storage: nil
        }
    }

    func isRunningNow(_ pin: PinIndex) -> Bool {
        switch current[pin].role {
        case .storage: false
        case .processor(let processor): processor.runningCycleEnd != nil
        case .extractor(let extractor): extractor.program != nil && extractor.pendingCycle != nil
        }
    }

    func isStorage(_ pin: PinIndex) -> Bool {
        snapshot[pin].role == .storage
    }

    /// What a pin puts out per hour in the `now` window.
    func nowOutput(_ pin: PinIndex) -> Double {
        switch current[pin].role {
        case .storage:
            return 0
        case .processor(let processor):
            guard processor.runningCycleEnd != nil, let schematic = schematic(pin), schematic.cycleTime > 0 else { return 0 }
            return Double(schematic.output.quantity) * 3600 / Double(schematic.cycleTime)
        case .extractor(let extractor):
            guard let program = extractor.program, let cycle = extractor.pendingCycle, program.cycleTime > 0 else { return 0 }
            return Double(program.yield(cycle: cycle)) * 3600 / Double(program.cycleTime)
        }
    }

    /// What a factory draws per hour of `typeID` in the `now` window.
    func nowInput(_ pin: PinIndex, _ typeID: TypeID) -> Double {
        guard isRunningNow(pin), let schematic = schematic(pin), schematic.cycleTime > 0,
              let input = schematic.inputs.first(where: { $0.typeID == typeID }) else { return 0 }
        return Double(input.quantity) * 3600 / Double(schematic.cycleTime)
    }

    func routeLine(_ route: Colony.Route, other: PinIndex) -> RouteLine {
        let pin = snapshot[other]
        return RouteLine(routeID: route.routeID,
                         pinID: pin.pinID,
                         pinName: pin.name,
                         pinKind: kind(of: pin),
                         commodity: commodity(route.typeID),
                         waypoints: route.waypoints.map { snapshot[$0].pinID })
    }

    // MARK: Build

    mutating func build() -> ColonyDetail {
        var facilities: [FacilityDetail] = []
        for pin in snapshot.pins {
            let role: FacilityDetail.Role
            switch pin.role {
            case .storage: role = .storage(storage(pin.id))
            case .processor: role = .factory(factory(pin.id))
            case .extractor: role = .extractor(extractor(pin.id))
            }
            facilities.append(FacilityDetail(
                id: pin.pinID,
                name: pin.name,
                typeID: pin.typeID,
                typeName: names.types[pin.typeID],
                kind: kind(of: pin),
                routesIn: snapshot.routes(to: pin.id).map { routeLine($0, other: $0.source) },
                routesOut: snapshot.routes(from: pin.id).map { routeLine($0, other: $0.destination) },
                role: role))
        }
        // The limit of each factory needs every factory's waits, so it is a second pass.
        for (offset, facility) in facilities.enumerated() {
            guard case .factory(var factory) = facility.role,
                  let index = snapshot.index(ofPinID: facility.id) else { continue }
            factory.limit = limit(of: index).map(commodity)
            facilities[offset].role = .factory(factory)
        }

        let issues = self.issues(facilities: facilities)
        let status = self.status(facilities: facilities)
        let products = self.products()
        let warnings = issues.filter(\.isWarning)
        let finish = issues.first(where: { if case .extractorsFinish = $0 { true } else { false } })
        let headline = warnings.first(where: { $0.date != nil }) ?? warnings.first ?? finish ?? issues.first
        let needsAttention = status != .running || issues.contains {
            switch $0 {
            case .extractorNotSetUp, .factoryNotSetUp, .stockRunsOut: true
            default: false
            }
        }
        let overview = ColonyOverview(planet: PlanetaryAnalysis.planetInfo(esi, names: names),
                                      status: status,
                                      needsAttention: needsAttention,
                                      products: products,
                                      headline: headline,
                                      otherIssues: issues.filter { $0 != headline },
                                      lastUpdate: snapshot.snapshotTime)
        let chain = self.chain(issues: issues)

        return ColonyDetail(overview: overview,
                            lastUpdate: snapshot.snapshotTime,
                            now: now,
                            programEnd: programEnd,
                            horizon: horizon,
                            commandCenter: commandCenter(),
                            issues: issues,
                            wastedToEnd: amounts(toEnd.wasted),
                            facilities: facilities,
                            chain: chain,
                            events: events(),
                            warnings: snapshot.warnings.map(\.description))
    }

    // MARK: Extractor

    func extractor(_ pin: PinIndex) -> ExtractorDetail {
        guard case .extractor(let original) = snapshot[pin].role,
              case .extractor(let now) = current[pin].role else { preconditionFailure("not an extractor") }
        let product = original.productTypeID.map(commodity)
        guard let program = original.program else {
            return ExtractorDetail(product: product, headCount: original.headCount, maxHeads: ColonyFitting.maxExtractorHeads,
                                   state: .notSetUp, program: nil, currentCycle: nil, currentCycleStart: nil,
                                   currentCycleEnd: nil, nextDelivery: nil, extractedSoFar: 0, stillToCome: 0,
                                   remainingPerHour: 0, programPerHour: 0, wastedToEnd: 0)
        }
        let yields = program.yields
        let total = yields.reduce(0, +)
        let cycle = now.pendingCycle
        let done = yields.prefix(cycle ?? yields.count).reduce(0, +)
        let programHours = Double(program.cycleCount * program.cycleTime) / 3600
        let state: ExtractorDetail.State = cycle == nil
            ? .finished(at: program.cycleCount > 0 ? program.cycleEnd(program.cycleCount - 1) : program.expiryTime)
            : .running
        return ExtractorDetail(
            product: product,
            headCount: original.headCount,
            maxHeads: ColonyFitting.maxExtractorHeads,
            state: state,
            program: .init(installTime: program.installTime, expiryTime: program.expiryTime,
                           cycleTime: TimeInterval(program.cycleTime), yields: yields, total: total),
            currentCycle: cycle,
            currentCycleStart: cycle.map(program.cycleStart),
            currentCycleEnd: cycle.map(program.cycleEnd),
            nextDelivery: cycle.map(program.yield(cycle:)),
            extractedSoFar: done,
            stillToCome: total - done,
            remainingPerHour: original.productTypeID.flatMap { current.hourlyRate(of: pin).outputs[$0] } ?? 0,
            programPerHour: programHours > 0 ? Double(total) / programHours : 0,
            wastedToEnd: toEnd[pin].wasted.reduce(0) { $0 + $1.quantity })
    }

    // MARK: Factory

    mutating func factory(_ pin: PinIndex) -> FactoryDetail {
        guard case .processor(let original) = snapshot[pin].role,
              case .processor(let now) = current[pin].role else { preconditionFailure("not a processor") }
        guard let schematic = schematic(pin) else {
            return FactoryDetail(schematicID: original.schematicID.map { Int($0.rawValue) }, output: nil, inputs: [],
                                 cycleTime: 0, state: .notSetUp, waitingFor: [], limit: nil, nominalPerHour: 0,
                                 averagePerHour: 0, madeSinceUpdate: 0, madeInDay: 0, madeToEnd: 0,
                                 utilizationSinceUpdate: 0, utilizationDay: 0, utilizationToEnd: 0,
                                 activity: [.init(start: self.now, end: horizon, isRunning: false)], wastedToEnd: 0)
        }
        let cycleTime = TimeInterval(schematic.cycleTime)
        let perHour = cycleTime > 0 ? 3600 / cycleTime : 0
        let output = schematic.output.typeID
        let contents = current[pin].contents

        let state: FactoryDetail.State
        if let end = now.runningCycleEnd {
            state = .running(cycleStart: now.lastCycleStart ?? end.addingTimeInterval(-cycleTime), cycleEnd: end)
        } else {
            var since = elapsed.idleSince(pin)
            // Idle at the snapshot already: it stopped when its last cycle ended, long before.
            if since == snapshot.snapshotTime, let start = original.lastCycleStart {
                since = min(start.addingTimeInterval(cycleTime), snapshot.snapshotTime)
            }
            let resumes = toEnd.firstEvent { if case .processorResumed(pin, _) = $0 { true } else { false } }?.date
            state = .idle(since: since, resumesAt: resumes)
        }

        let inputs = schematic.inputs.map { input in
            let inStorage = current.routes(to: pin)
                .filter { $0.typeID == input.typeID && isStorage($0.source) }
                .reduce(0) { $0 + current[$1.source].contents[input.typeID] }
            return FactoryDetail.Input(commodity: commodity(input.typeID),
                                       perCycle: Int(input.quantity),
                                       perHour: Double(input.quantity) * perHour,
                                       buffered: contents[input.typeID],
                                       inStorage: inStorage)
        }
        let missingNow = schematic.inputs.filter { contents[$0.typeID] < Int($0.quantity) }.map(\.typeID)

        // Running and waiting spans from `now` on, and what each wait is for.
        var spans: [ActivitySpan] = []
        var waits: [TypeID: TimeInterval] = [:]
        var running = isRunningNow(pin)
        var spanStart = self.now
        var missing = running ? [] : missingNow
        func close(at date: Date) {
            guard date > spanStart else { return }
            spans.append(.init(start: spanStart, end: date, isRunning: running))
            if !running {
                for typeID in missing { waits[typeID, default: 0] += date.timeIntervalSince(spanStart) }
            }
        }
        for event in toEnd.events {
            switch event {
            case .processorIdle(pin, let date) where running:
                close(at: date)
                running = false
                spanStart = date
                let buffer = toEnd.contents(of: pin, at: date) ?? contents
                missing = schematic.inputs.filter { buffer[$0.typeID] < Int($0.quantity) }.map(\.typeID)
            case .processorResumed(pin, let date) where !running:
                close(at: date)
                running = true
                spanStart = date
            default:
                break
            }
        }
        close(at: horizon)
        activity[Int(pin.rawValue)] = spans
        waitTime[Int(pin.rawValue)] = waits

        let made = toEnd[pin].produced[output]
        return FactoryDetail(
            schematicID: Int(schematic.id.rawValue),
            output: CommodityAmount(commodity: commodity(output), quantity: Int(schematic.output.quantity)),
            inputs: inputs,
            cycleTime: cycleTime,
            state: state,
            waitingFor: now.runningCycleEnd == nil ? missingNow.map(commodity) : [],
            limit: nil,
            nominalPerHour: Double(schematic.output.quantity) * perHour,
            averagePerHour: self.perHour(made, toEnd),
            madeSinceUpdate: elapsed[pin].produced[output],
            madeInDay: day[pin].produced[output],
            madeToEnd: made,
            utilizationSinceUpdate: elapsed.utilization(of: pin),
            utilizationDay: day.utilization(of: pin),
            utilizationToEnd: toEnd.utilization(of: pin),
            activity: spans,
            wastedToEnd: toEnd[pin].wasted.reduce(0) { $0 + $1.quantity })
    }

    /// The input a factory waited for longest between `now` and the horizon.
    func dominantWait(of pin: PinIndex) -> TypeID? {
        waitTime[Int(pin.rawValue)]?.max { ($0.value, $1.key.rawValue) < ($1.value, $0.key.rawValue) }?.key
    }

    /// The commodity at the root of a factory's shortage: what it waits for, followed up
    /// through the factories that make it for as long as they wait too.
    func limit(of pin: PinIndex, visited: Set<PinIndex> = []) -> TypeID? {
        guard let waited = dominantWait(of: pin) else { return nil }
        let producers = pinIndices.filter {
            !visited.contains($0) && $0 != pin && schematic($0)?.output.typeID == waited && dominantWait(of: $0) != nil
        }
        guard let starving = producers.max(by: {
            (waitTime[Int($0.rawValue)]?.values.reduce(0, +) ?? 0) < (waitTime[Int($1.rawValue)]?.values.reduce(0, +) ?? 0)
        }) else { return waited }
        return limit(of: starving, visited: visited.union([pin])) ?? waited
    }

    // MARK: Storage

    func storage(_ pin: PinIndex) -> StorageDetail {
        let capacity = snapshot[pin].capacity
        let usedNow = current.usedVolume(of: pin)

        var fill: [StorageDetail.FillSample] = elapsed.timeline.filter { $0.pin == pin }.map {
            .init(date: $0.date, volume: $0.contents.volume(in: catalog), isForecast: false)
        }
        fill.append(.init(date: now, volume: usedNow, isForecast: true))
        fill += toEnd.timeline.filter { $0.pin == pin }.map {
            .init(date: $0.date, volume: $0.contents.volume(in: catalog), isForecast: true)
        }
        let peak = fill.filter(\.isForecast).map(\.volume).max() ?? usedNow

        let stats = toEnd[pin]
        var typeIDs = Set(current[pin].contents.map(\.typeID))
        typeIDs.formUnion(stats.received.map(\.typeID))
        typeIDs.formUnion(stats.sent.map(\.typeID))
        typeIDs.formUnion(final[pin].contents.map(\.typeID))
        let routedOut = Set(snapshot.routes(from: pin).map(\.typeID))
        // What the colony makes piles up on purpose (the launchpad's output); only what it
        // neither makes nor moves is dead stock.
        let producedHere = Set(pinIndices.compactMap(product))
        let contents = typeIDs.map { typeID in
            let quantity = current[pin].contents[typeID]
            let stocked = commodity(typeID)
            return StorageDetail.Stock(
                commodity: stocked,
                quantity: quantity,
                volume: Double(quantity) * stocked.volume,
                inPerHour: perHour(stats.received[typeID], toEnd),
                outPerHour: perHour(stats.sent[typeID], toEnd),
                atEnd: final[pin].contents[typeID],
                isUnused: quantity > 0 && !routedOut.contains(typeID) && !producedHere.contains(typeID),
                isPassThrough: quantity == 0 && (stats.received[typeID] > 0 || stats.sent[typeID] > 0))
        }
        .sorted { ($0.volume, $0.inPerHour, $0.commodity.typeID.rawValue) > ($1.volume, $1.inPerHour, $1.commodity.typeID.rawValue) }

        // What the suppliers lose: each (source, commodity) once.
        var lost = Inventory()
        var seen = Set<[UInt32]>()
        for route in snapshot.routes(to: pin) where seen.insert([UInt32(route.source.rawValue), route.typeID.rawValue]).inserted {
            lost[route.typeID] += toEnd[route.source].wasted[route.typeID]
        }

        let inflow = stats.received.reduce(0.0) { $0 + Double($1.quantity) * (catalog.commodity($1.typeID)?.volume ?? 0) }
        return StorageDetail(capacity: capacity,
                             usedNow: usedNow,
                             usedAtEnd: final.usedVolume(of: pin),
                             peak: peak,
                             fullAt: toEnd.storageFull(pin) ?? elapsed.storageFull(pin),
                             inflowPerHour: hours(toEnd) > 0 ? inflow / hours(toEnd) : 0,
                             contents: contents,
                             fill: fill,
                             lostIfNotEmptied: amounts(lost),
                             exportFeeNow: Customs.exportFee(for: current[pin].contents,
                                                             taxRate: PlanetaryAnalysis.assumedTaxRate,
                                                             catalog: catalog))
    }

    // MARK: Colony

    func commandCenter() -> CommandCenterSummary {
        let fitting = snapshot.fitting
        return CommandCenterSummary(level: snapshot.upgradeLevel,
                                    cpuUsed: fitting.cpu.used,
                                    cpuTotal: fitting.cpu.total,
                                    powerUsed: fitting.power.used,
                                    powerTotal: fitting.power.total,
                                    pinCount: snapshot.pins.count,
                                    linkCount: snapshot.links.count,
                                    maxLinkLevel: snapshot.links.map(\.level).max() ?? 0,
                                    longestLink: fitting.links.compactMap(\.length).max(),
                                    isLinkCostEstimated: fitting.issues.contains(.linkLengthUnknown),
                                    routeCount: snapshot.routes.count,
                                    routesViaWaypoint: snapshot.routes.filter { !$0.waypoints.isEmpty }.count)
    }

    /// The top tier the colony makes, or the raw resources if it has no factories.
    func products() -> [ProductRate] {
        let producers = pinIndices.filter { product($0) != nil }
        let topTier = producers.compactMap { product($0).flatMap { catalog.commodity($0)?.tier } }.max()
        let top = producers.filter { product($0).flatMap { catalog.commodity($0)?.tier } == topTier }
        let typeIDs = Set(top.compactMap(product)).sorted { $0.rawValue < $1.rawValue }
        return typeIDs.map { typeID in
            let pins = top.filter { product($0) == typeID }
            let nominal = pins.reduce(0.0) { sum, pin in
                if let schematic = schematic(pin), schematic.cycleTime > 0 {
                    return sum + Double(schematic.output.quantity) * 3600 / Double(schematic.cycleTime)
                }
                return sum + (snapshot.hourlyRate(of: pin).outputs[typeID] ?? 0)
            }
            return ProductRate(commodity: commodity(typeID),
                               perHour: perHour(toEnd.produced[typeID], toEnd),
                               nominalPerHour: nominal,
                               madeSinceUpdate: elapsed.produced[typeID],
                               madeToEnd: toEnd.produced[typeID])
        }
        .sorted { $0.perHour > $1.perHour }
    }

    func status(facilities: [FacilityDetail]) -> ColonyStatus {
        let extracting = pinIndices.contains { program($0) != nil && isRunningNow($0) }
        let busyAhead = pinIndices.contains { schematic($0) != nil && toEnd[$0].busyTime > 0 }
        if !extracting && !busyAhead { return .stopped }
        let filling = !toEnd.wasted.isEmpty || facilities.contains {
            if case .storage(let storage) = $0.role { storage.fullAt != nil } else { false }
        }
        return filling ? .filling : .running
    }

    func issues(facilities: [FacilityDetail]) -> [ColonyIssue] {
        var issues: [ColonyIssue] = []

        // Extractors.
        let programs = pinIndices.compactMap { pin in program(pin).map { (pin, $0) } }
        let running = programs.filter { isRunningNow($0.0) }
        if running.isEmpty, !programs.isEmpty {
            let since = programs.map { $0.1.cycleCount > 0 ? $0.1.cycleEnd($0.1.cycleCount - 1) : $0.1.expiryTime }
                .filter { $0 <= now }.max()
            issues.append(.extractorsStopped(since: since))
        } else if let first = running.map({ $0.1.expiryTime }).min() {
            let end = running.map { $0.1.cycleEnd($0.1.cycleCount - 1) }.min() ?? first
            let count = running.filter { $0.1.cycleEnd($0.1.cycleCount - 1) == end }.count
            issues.append(.extractorsFinish(at: end, count: count))
        }

        let producedHere = Set(pinIndices.compactMap(product))
        for facility in facilities {
            guard let pin = snapshot.index(ofPinID: facility.id) else { continue }
            switch facility.role {
            case .extractor(let extractor):
                if extractor.state == .notSetUp { issues.append(.extractorNotSetUp(pinID: facility.id)) }
            case .factory(let factory):
                if factory.state == .notSetUp { issues.append(.factoryNotSetUp(pinID: facility.id)) }
            case .storage(let storage):
                if let full = storage.fullAt { issues.append(.storageFull(pinID: facility.id, at: full)) }
                for stock in storage.contents where stock.isUnused {
                    issues.append(.unusedStock(pinID: facility.id, commodity: stock.commodity, quantity: stock.quantity))
                }
                // Stock nothing here makes, drawn down to nothing.
                for stock in storage.contents where stock.quantity > 0 && stock.outPerHour > 0
                    && !producedHere.contains(stock.commodity.typeID) {
                    let typeID = stock.commodity.typeID
                    if let out = toEnd.timeline.first(where: { $0.pin == pin && $0.contents[typeID] == 0 }) {
                        issues.append(.stockRunsOut(pinID: facility.id, commodity: stock.commodity, at: out.date))
                    }
                }
            }
        }

        // Losses, per source and commodity.
        for pin in pinIndices {
            for item in toEnd[pin].wasted {
                let first = (elapsed.events + toEnd.events).first {
                    if case .outputWasted(pin, item.typeID, _) = $0 { true } else { false }
                }?.date ?? now
                issues.append(.outputWasted(pinID: snapshot[pin].pinID, commodity: commodity(item.typeID),
                                            at: first, quantity: item.quantity))
            }
        }

        // Top-tier factories that wait — while there is something to wait for: once the
        // programs are over, that is `extractorsStopped`.
        let topTier = pinIndices.compactMap { schematic($0).flatMap { catalog.commodity($0.output.typeID)?.tier } }.max()
        for pin in pinIndices {
            guard !running.isEmpty || programs.isEmpty,
                  let schematic = schematic(pin), catalog.commodity(schematic.output.typeID)?.tier == topTier,
                  let waited = dominantWait(of: pin) else { continue }
            let share = 1 - toEnd.utilization(of: pin)
            guard share >= PlanetaryAnalysis.limitedShare else { continue }
            issues.append(.outputLimited(pinID: snapshot[pin].pinID,
                                         product: commodity(schematic.output.typeID),
                                         waitingFor: commodity(waited),
                                         limit: commodity(limit(of: pin) ?? waited),
                                         share: share))
        }

        // Warnings before the rest; within each, dated ones soonest first.
        return issues.enumerated().sorted { lhs, rhs in
            let l = lhs.element, r = rhs.element
            if l.isWarning != r.isWarning { return l.isWarning }
            switch (l.date, r.date) {
            case let (a?, b?) where a != b: return a < b
            case (_?, nil): return true
            case (nil, _?): return false
            default: return lhs.offset < rhs.offset
            }
        }.map(\.element)
    }

    func events() -> [ColonyEvent] {
        let planetID = esi.planetID, planetName = esi.planetName
        var events: [ColonyEvent] = []
        var finishes: [Date: Int] = [:]
        for event in toEnd.events where event.date > now {
            switch event {
            case .extractorFinished(_, let date):
                finishes[date, default: 0] += 1
            case .storageFull(let pin, let date):
                events.append(.init(kind: .storageFull, date: date, planetID: planetID, planetName: planetName,
                                    pinID: snapshot[pin].pinID))
            case .outputWasted(let pin, let typeID, let date):
                events.append(.init(kind: .outputLost, date: date, planetID: planetID, planetName: planetName,
                                    pinID: snapshot[pin].pinID, commodity: commodity(typeID)))
            case .processorIdle, .processorResumed:
                break
            }
        }
        for (date, count) in finishes {
            events.append(.init(kind: .extractorsFinish, date: date, planetID: planetID, planetName: planetName, count: count))
        }
        for pin in pinIndices {
            guard let spans = activity[Int(pin.rawValue)], let output = schematic(pin)?.output.typeID else { continue }
            // The first long wait of each factory only: a starved factory waits every few hours,
            // and the schedule is rebuilt with every fetch anyway.
            for span in spans where !span.isRunning && span.start > now {
                // A wait that the horizon cuts off is open-ended.
                let open = span.end >= horizon
                let length = span.end.timeIntervalSince(span.start)
                guard length > PlanetaryAnalysis.longWait else { continue }
                // Running dry as the programs end is the extractor event, not this one.
                if open, let programEnd, programEnd.timeIntervalSince(span.start) <= PlanetaryAnalysis.longWait { continue }
                events.append(.init(kind: .factoryStarved, date: span.start, planetID: planetID, planetName: planetName,
                                    pinID: snapshot[pin].pinID, commodity: commodity(output),
                                    duration: open ? nil : length))
                break
            }
        }
        return events.sorted { ($0.date, $0.id) < ($1.date, $1.id) }
    }

    // MARK: Chain

    func chain(issues: [ColonyIssue]) -> ProductionChain {
        // Nodes: one per extractor and storage, one per group of identical factories.
        struct GroupKey: Hashable {
            var schematic: UInt16?
            var inputs: [[Int64]]
            var outputs: [[Int64]]
        }
        var nodeOf: [PinIndex: String] = [:]
        var members: [String: [PinIndex]] = [:]
        var order: [String] = []
        var groups: [GroupKey: String] = [:]
        for pin in pinIndices {
            let id: String
            if case .processor(let processor) = snapshot[pin].role {
                let key = GroupKey(
                    schematic: processor.schematicID?.rawValue,
                    inputs: snapshot.routes(to: pin).map { [snapshot[$0.source].pinID, Int64($0.typeID.rawValue)] }.sorted { $0.lexicographicallyPrecedes($1) },
                    outputs: snapshot.routes(from: pin).map { [snapshot[$0.destination].pinID, Int64($0.typeID.rawValue)] }.sorted { $0.lexicographicallyPrecedes($1) })
                if let existing = groups[key] {
                    id = existing
                } else {
                    id = "group-\(snapshot[pin].pinID)"
                    groups[key] = id
                }
            } else {
                id = "pin-\(snapshot[pin].pinID)"
            }
            nodeOf[pin] = id
            if members[id] == nil { order.append(id) }
            members[id, default: []].append(pin)
        }

        // Columns: extraction, then each factory tier, a storage right of what it receives.
        func tier(_ typeID: TypeID) -> Int { Int(catalog.commodity(typeID)?.tier.rawValue ?? 0) }
        var rawStage: [String: Int] = [:]
        for id in order {
            let pin = members[id]![0]
            switch snapshot[pin].role {
            case .extractor: rawStage[id] = 0
            case .processor: rawStage[id] = 2 * max(1, schematic(pin).map { tier($0.output.typeID) } ?? 1)
            case .storage:
                let incoming = snapshot.routes(to: pin).map { tier($0.typeID) }.max()
                rawStage[id] = incoming.map { 2 * $0 + 1 } ?? 1
            }
        }
        let columns = Set(rawStage.values).sorted()
        let stage = rawStage.mapValues { columns.firstIndex(of: $0)! }

        // Edges, aggregated per (from, to, commodity).
        struct EdgeKey: Hashable { var from: String; var to: String; var typeID: UInt32 }
        var edgeRates: [EdgeKey: [ChainWindow: Double]] = [:]
        var edgeOrder: [EdgeKey] = []
        let windows: [(ChainWindow, Forecast)] = [(.day, day), (.toEnd, toEnd)]
        for route in snapshot.routes {
            let key = EdgeKey(from: nodeOf[route.source]!, to: nodeOf[route.destination]!, typeID: route.typeID.rawValue)
            if edgeRates[key] == nil { edgeOrder.append(key) }
            var rates = edgeRates[key] ?? [:]
            for (window, forecast) in windows {
                rates[window, default: 0] += perHour(flow(route, in: forecast), forecast)
            }
            rates[.now, default: 0] += nowFlow(route)
            edgeRates[key] = rates
        }
        let edges = edgeOrder.map {
            ChainEdge(from: $0.from, to: $0.to, commodity: commodity(TypeID(rawValue: $0.typeID)), perHour: edgeRates[$0]!)
        }

        let nodes = order.map { id -> ChainNode in
            let pins = members[id]!
            let first = pins[0]
            let facilityKind = kind(of: snapshot[first])
            let made = product(first).map(commodity)
            let isHub = facilityKind.isStorage && snapshot.routes(from: first).contains {
                (stage[nodeOf[$0.destination]!] ?? 0) < (stage[id] ?? 0)
            }
            var figures: [ChainWindow: ChainFigures] = [:]
            figures[.now] = nowFigures(pins, kind: facilityKind)
            figures[.day] = windowFigures(pins, kind: facilityKind, forecast: day, colony: dayColony)
            figures[.toEnd] = windowFigures(pins, kind: facilityKind, forecast: toEnd, colony: final)
            let headCount = pins.reduce(0) { sum, pin in
                if case .extractor(let extractor) = snapshot[pin].role { sum + extractor.headCount } else { sum }
            }
            return ChainNode(id: id, stage: stage[id] ?? 0, kind: facilityKind, pinIDs: pins.map { snapshot[$0].pinID },
                             name: made?.name ?? names.types[snapshot[first].typeID] ?? snapshot[first].name,
                             product: made, isHub: isHub, headCount: headCount, figures: figures)
        }

        var balances: [ChainWindow: [CommodityBalance]] = [:]
        for (window, forecast) in windows {
            var typeIDs = Set(forecast.produced.map(\.typeID))
            typeIDs.formUnion(forecast.consumed.map(\.typeID))
            balances[window] = typeIDs.sorted { (tier($0), $0.rawValue) < (tier($1), $1.rawValue) }.map {
                CommodityBalance(commodity: commodity($0), made: forecast.produced[$0],
                                 used: forecast.consumed[$0], wasted: forecast.wasted[$0])
            }
        }
        var made: [TypeID: Double] = [:], used: [TypeID: Double] = [:]
        for pin in pinIndices {
            if let product = product(pin) { made[product, default: 0] += nowOutput(pin) }
            for input in schematic(pin)?.inputs ?? [] { used[input.typeID, default: 0] += nowInput(pin, input.typeID) }
        }
        balances[.now] = Set(made.keys).union(used.keys).sorted { (tier($0), $0.rawValue) < (tier($1), $1.rawValue) }.map {
            CommodityBalance(commodity: commodity($0), made: Int((made[$0] ?? 0).rounded()),
                             used: Int((used[$0] ?? 0).rounded()), wasted: 0)
        }

        let bottleneck = issues.lazy.compactMap { issue -> PlanetaryCommodity? in
            if case let .outputLimited(_, _, _, limit, _) = issue { limit } else { nil }
        }.first

        return ProductionChain(nodes: nodes, edges: edges, balances: balances, bottleneck: bottleneck)
    }

    /// What went over one route in a window. `Forecast` counts per pin, not per route, so a
    /// pin with several routes for the same commodity is split by what each destination took.
    func flow(_ route: Colony.Route, in forecast: Forecast) -> Int {
        let siblings = snapshot.routes(from: route.source).filter { $0.typeID == route.typeID }
        let sent = forecast[route.source].sent[route.typeID]
        if siblings.count == 1 { return sent }
        let incoming = snapshot.routes(to: route.destination).filter { $0.typeID == route.typeID }
        let received = forecast[route.destination].received[route.typeID]
        if incoming.count == 1 { return received }
        let total = siblings.reduce(0) { $0 + forecast[$1.destination].received[route.typeID] }
        return total > 0 ? Int((Double(sent) * Double(received) / Double(total)).rounded()) : 0
    }

    /// The `now` rate of a route: what a running factory at its end draws, or what its source
    /// puts out, split evenly over the routes that carry it.
    func nowFlow(_ route: Colony.Route) -> Double {
        if schematic(route.destination) != nil {
            let incoming = snapshot.routes(to: route.destination).filter { $0.typeID == route.typeID }.count
            return nowInput(route.destination, route.typeID) / Double(max(1, incoming))
        }
        guard product(route.source) == route.typeID else { return 0 }
        let siblings = snapshot.routes(from: route.source).filter { $0.typeID == route.typeID }.count
        return nowOutput(route.source) / Double(max(1, siblings))
    }

    func nowFigures(_ pins: [PinIndex], kind: FacilityKind) -> ChainFigures {
        if kind.isStorage {
            let pin = pins[0]
            let inflow = snapshot.routes(to: pin).reduce(0.0) {
                $0 + nowFlow($1) * (catalog.commodity($1.typeID)?.volume ?? 0)
            }
            return ChainFigures(perHour: inflow, utilization: nil, fill: current.fill(of: pin), fullAt: nil, wasted: 0)
        }
        let perHour = pins.reduce(0.0) { $0 + nowOutput($1) }
        let utilization: Double?
        if kind == .extractor {
            utilization = pins.compactMap { pin -> Double? in
                guard case .extractor(let extractor) = current[pin].role, let program = extractor.program,
                      program.cycleCount > 0 else { return nil }
                return Double(extractor.pendingCycle ?? program.cycleCount) / Double(program.cycleCount)
            }.average
        } else {
            utilization = Double(pins.filter(isRunningNow).count) / Double(pins.count)
        }
        return ChainFigures(perHour: perHour, utilization: utilization, fill: nil, fullAt: nil, wasted: 0)
    }

    func windowFigures(_ pins: [PinIndex], kind: FacilityKind, forecast: Forecast, colony: Colony) -> ChainFigures {
        let wasted = pins.reduce(0) { sum, pin in sum + forecast[pin].wasted.reduce(0) { $0 + $1.quantity } }
        if kind.isStorage {
            let pin = pins[0]
            let inflow = forecast[pin].received.reduce(0.0) {
                $0 + Double($1.quantity) * (catalog.commodity($1.typeID)?.volume ?? 0)
            }
            return ChainFigures(perHour: hours(forecast) > 0 ? inflow / hours(forecast) : 0, utilization: nil,
                                fill: colony.fill(of: pin), fullAt: forecast.storageFull(pin), wasted: wasted)
        }
        let made = pins.reduce(0) { sum, pin in sum + (product(pin).map { forecast[pin].produced[$0] } ?? 0) }
        let utilization: Double?
        if kind == .extractor {
            utilization = pins.compactMap { pin -> Double? in
                guard let program = program(pin), program.cycleCount > 0 else { return nil }
                let done = program.completedCycles(from: program.installTime.addingTimeInterval(-1), to: forecast.to).count
                return Double(done) / Double(program.cycleCount)
            }.average
        } else {
            utilization = pins.map { forecast.utilization(of: $0) }.average
        }
        return ChainFigures(perHour: perHour(made, forecast), utilization: utilization, fill: nil, fullAt: nil, wasted: wasted)
    }
}

nonisolated private extension Array where Element == Double {
    var average: Double? { isEmpty ? nil : reduce(0, +) / Double(count) }
}
