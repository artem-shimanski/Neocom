import SwiftUI

/// A colony's production chain, top to bottom: extraction, each tier of factories, the storages
/// between them, and what flows across each step — for the moment (`Now`), the next day or the
/// rest of the program. A tap on a node traces its path through the chain and opens its figures
/// in a sheet.
///
/// The graph is the colony's own (`ProductionChain`, laid out by `ChainLayout`), whatever its
/// shape: identical factories are one tile, a hub feeding several tiers sits above the first
/// one it feeds, and what factories return to it is drawn as a flow back up.
struct PlanetaryChainView: View {
    let model: PlanetaryModel
    let planetID: Int64

    @State private var window: ChainWindow = .toEnd
    @State private var selection: String?

    var body: some View {
        PlanetaryReportContent(model: model) { report in
            if let colony = report.colony(planetID: planetID) {
                TimelineView(.everyMinute) { context in
                    PlanetaryChainContent(colony: colony, now: max(context.date, colony.now),
                                          window: $window, selection: $selection)
                }
                .navigationSubtitle(colony.planet.displayName)
                .sheet(isPresented: Binding(get: { selection != nil }, set: { if !$0 { selection = nil } })) {
                    if let id = selection, let node = colony.chain.node(id: id) {
                        PlanetaryChainNodeSheet(colony: colony, node: node, window: window)
                    }
                }
            } else {
                ContentUnavailableView("No Colony", systemImage: "globe",
                                       description: Text("The character has no colony on this planet any more."))
            }
        }
        .hudScreen()
        .navigationTitle("Production Chain")
        .navigationBarTitleDisplayMode(.inline)
    }
}

extension ChainWindow {
    var title: LocalizedStringKey {
        switch self {
        case .now: "Now"
        case .day: "24 h"
        case .toEnd: "To end"
        }
    }
}

struct PlanetaryChainContent: View {
    let colony: ColonyDetail
    let now: Date
    @Binding var window: ChainWindow
    @Binding var selection: String?

    private var chain: ProductionChain { colony.chain }

    var body: some View {
        let layout = chain.layout
        let path = selection.map { chain.path(through: $0) }
        HUDList {
            Section {
                Picker("Forecast window", selection: $window) {
                    ForEach(ChainWindow.allCases, id: \.self) { window in
                        Text(window.title).tag(window)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .hudBareRow()
            }

            Section {
                bottleneck.hudBareRow()
            }

            Section {
                flow(layout, path: path).hudBareRow()
            } header: {
                HUDSectionHeader(Text("Flow · \(layout.rows.reduce(0) { $0 + $1.pinCount }) pins")) {
                    Text("Tap to trace")
                }
                .hudListHeader()
            }

            commandCenter
        }
    }

    // MARK: Bottleneck

    private var bottleneck: some View {
        let issues = colony.issues
        let warnings = issues.filter(\.isWarning).count
        return HUDPanel(tone: warnings > 0 ? .warn : .normal) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text("Bottleneck")
                        .font(.hudMicro)
                        .tracking(1.5)
                        .textCase(.uppercase)
                        .foregroundStyle(Color.hudInkMuted)
                    Spacer(minLength: 8)
                    if !issues.isEmpty {
                        Text("\(issues.count) issues")
                            .font(.hudMicro)
                            .tracking(1)
                            .textCase(.uppercase)
                            .foregroundStyle(warnings > 0 ? Color.hudWarn : Color.hudInkMuted)
                    }
                }
                Text(verbatim: bottleneckSentence)
                    .font(HUDFont.display(15, weight: .semibold, relativeTo: .body))
                    .lineSpacing(2)
            }
            .padding(.horizontal, HUDMetrics.gutter)
            .padding(.vertical, 12)

            ForEach(issues, id: \.self) { issue in
                let text = colony.describe(issue, now: now)
                let node = issue.pinID.flatMap(chain.node(containing:))
                Rectangle().fill(Color.hudLineSubtle).frame(height: 1)
                Button {
                    if let node { selection = node.id }
                } label: {
                    HUDEventRow(when: Text(verbatim: text.when),
                                whenDetail: text.whenDetail.map { Text(verbatim: $0) },
                                whenColor: text.isWarning ? .hudWarn : .hudInkMuted,
                                title: Text(verbatim: text.title),
                                detail: Text(verbatim: text.detail),
                                whenWidth: 70,
                                titleFont: HUDFont.display(14, weight: .semibold, relativeTo: .subheadline))
                        .padding(.horizontal, HUDMetrics.gutter)
                        .padding(.vertical, 10)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.hudRow)
                .disabled(node == nil)
            }
        }
        .multilineTextAlignment(.leading)
    }

    private var bottleneckSentence: String {
        let limited = colony.issues.lazy.compactMap { issue -> (PlanetaryCommodity, PlanetaryCommodity, PlanetaryCommodity, Double)? in
            if case let .outputLimited(_, product, waitingFor, limit, share) = issue { (product, waitingFor, limit, share) } else { nil }
        }.first
        if let limited {
            let (product, waitingFor, limit, share) = limited
            var sentence = String(localized: "\(limit.name). The \(product.name) factory waits for \(waitingFor.name) \(FitStatFormat.percent(share)) of the remaining time.")
            if limit != waitingFor {
                sentence += " " + String(localized: "\(waitingFor.name) wait for \(limit.name) in turn.")
            }
            return sentence
        }
        if !chain.nodes.contains(where: \.kind.isFactory) {
            return String(localized: "None. The colony only extracts.")
        }
        return String(localized: "None. Every factory gets what it needs.")
    }

    // MARK: Flow

    private func flow(_ layout: ChainLayout, path: Set<String>?) -> some View {
        let topTier = layout.rows.compactMap(\.outputTier).max()
        return VStack(spacing: 0) {
            ForEach(layout.rows) { row in
                if row.isStorage {
                    VStack(spacing: 8) {
                        ForEach(row.nodes) { node in
                            nodeButton(node) {
                                hub(node, number: row.id + 1, path: path)
                            }
                        }
                    }
                } else {
                    VStack(spacing: 6) {
                        caption(row, isTop: row.outputTier == topTier)
                        let columns = Array(repeating: GridItem(.flexible(), spacing: 8, alignment: .top),
                                            count: min(3, max(1, row.nodes.count)))
                        LazyVGrid(columns: columns, spacing: 8) {
                            ForEach(row.nodes) { node in
                                nodeButton(node) {
                                    tile(node, path: path)
                                }
                            }
                        }
                    }
                }
                let step = layout.step(after: row.id, window: window)
                if !step.isEmpty {
                    HUDChainConnector(
                        flows: step.down.map { Text(verbatim: String(localized: "\(PlanetaryFormat.number($0.perHour)) \(PlanetaryFormat.tier($0.tier))/h")) },
                        returns: step.back.map { flow in
                            let target = chain.node(id: flow.nodeID)?.kind.title ?? ""
                            return Text("\(PlanetaryFormat.number(flow.perHour)) \(PlanetaryFormat.tier(flow.tier))/h back to \(target)")
                        })
                } else if row.id != layout.rows.last?.id {
                    Color.clear.frame(height: 12)
                }
            }
        }
    }

    private func nodeButton(_ node: ChainNode, @ViewBuilder label: () -> some View) -> some View {
        Button {
            selection = selection == node.id ? nil : node.id
        } label: {
            label()
        }
        .buttonStyle(.hudTile)
    }

    /// `3 · BASIC INDUSTRY · 6` over a row of tiles, with the tiers it turns into each other
    /// — or, for the top tier, what it makes in the window.
    private func caption(_ row: ChainLayout.Row, isTop: Bool) -> some View {
        let title = row.kind == .extractor
            ? String(localized: "\(row.id + 1) · Extract")
            : "\(row.id + 1) · \(row.kind.title) · \(row.pinCount)"
        let trailing: String
        if let tier = row.outputTier, tier > 0 {
            if isTop {
                let products = Set(row.nodes.compactMap(\.product?.typeID))
                if window == .now {
                    trailing = PlanetaryFormat.rate(row.nodes.reduce(0) { $0 + ($1.figures[.now]?.perHour ?? 0) })
                } else {
                    let made = (chain.balances[window] ?? []).filter { products.contains($0.commodity.typeID) }
                        .reduce(0) { $0 + $1.made }
                    trailing = PlanetaryFormat.gain(made)
                }
            } else {
                trailing = "\(PlanetaryFormat.tier(tier == 4 ? 3 : tier - 1)) → \(PlanetaryFormat.tier(tier))"
            }
        } else {
            trailing = PlanetaryFormat.tier(0)
        }
        return HStack {
            Text(verbatim: title)
            Spacer(minLength: 8)
            Text(verbatim: trailing)
        }
        .font(.hudMicro)
        .tracking(1.5)
        .textCase(.uppercase)
        .foregroundStyle(Color.hudInkMuted)
        .padding(.horizontal, HUDMetrics.headerFaceInset)
    }

    /// The issue of the colony that is about this node, if there is one worth a warn colour.
    private func problem(of node: ChainNode) -> ColonyIssue? {
        colony.issues.first { issue in
            guard let pin = issue.pinID, node.pinIDs.contains(pin) else { return false }
            switch issue {
            case .unusedStock: return false
            default: return true
            }
        }
    }

    private func tile(_ node: ChainNode, path: Set<String>?) -> HUDChainTile {
        let figures = node.figures[window]
        let problem = problem(of: node)
        let tone: HUDTone = problem != nil || (figures?.wasted ?? 0) > 0 ? .warn : .normal
        let utilization = figures?.utilization
        let tag: String
        var note: String?
        if node.kind == .extractor {
            let heads = String(localized: "\(node.headCount) heads")
            tag = node.count > 1 ? "\(node.kind.shortTitle) ×\(node.count) · \(heads)" : "\(node.kind.shortTitle) · \(heads)"
            note = utilization.map { String(localized: "Program \(FitStatFormat.percent($0))") }
        } else {
            tag = "\(node.kind.shortTitle) ×\(node.count)"
            note = utilization.map { String(localized: "Busy \(FitStatFormat.percent($0))") }
            if case let .outputLimited(_, _, waitingFor, _, _) = problem, let busy = note {
                note = busy + " · " + String(localized: "Waits for \(waitingFor.name)")
            }
        }
        if case .extractorNotSetUp = problem { note = String(localized: "Not set up") }
        if case .factoryNotSetUp = problem { note = String(localized: "Not set up") }
        return HUDChainTile(tag: Text(verbatim: tag),
                            name: Text(verbatim: node.product?.name ?? node.name),
                            rate: Text(verbatim: PlanetaryFormat.rate(figures?.perHour ?? 0)),
                            progress: utilization,
                            note: note.map { Text(verbatim: $0) },
                            tone: tone,
                            isSelected: selection == node.id,
                            isDimmed: path.map { !$0.contains(node.id) } ?? false)
    }

    private func hub(_ node: ChainNode, number: Int, path: Set<String>?) -> HUDChainHub {
        let figures = node.figures[window]
        let fillNow = node.figures[.now]?.fill ?? 0
        let storage = node.pinIDs.first.flatMap(colony.facility(pinID:)).flatMap { facility -> StorageDetail? in
            if case let .storage(storage) = facility.role { storage } else { nil }
        }
        let capacity = storage?.capacity ?? 0
        // The `now` window has no span to fill up in; it says when the storage will, as the
        // forecast to the end does.
        let fullAt = window == .now ? storage?.fullAt : figures?.fullAt
        let fillEnd = figures?.fill ?? fillNow

        let status: String
        if let fullAt {
            status = fullAt <= now ? String(localized: "Full") : String(localized: "Full in \(EVETime.duration(fullAt.timeIntervalSince(now)))")
        } else if window == .now || abs(fillEnd - fillNow) < 0.005 {
            status = FitStatFormat.percent(fillNow)
        } else {
            status = "\(FitStatFormat.percent(fillNow)) → \(FitStatFormat.percent(fillEnd))"
        }

        let leading: String
        if window == .now {
            leading = "\(PlanetaryFormat.volume(storage?.usedNow ?? fillNow * capacity)) / \(PlanetaryFormat.volume(capacity)) m³"
        } else if let fullAt = figures?.fullAt {
            leading = String(localized: "Full \(EVETime.monthDayTime(fullAt))")
        } else {
            leading = "→ \(PlanetaryFormat.volume(fillEnd * capacity)) m³"
        }
        let flow = chain.throughput(of: node.id, window: window)
        let trailing = String(localized: "In \(PlanetaryFormat.number(flow.in)) · out \(PlanetaryFormat.number(flow.out)) /h")

        return HUDChainHub(tag: Text(verbatim: "\(number) · \(node.kind.shortTitle)"),
                           name: Text(verbatim: colony.facilityName(node.pinIDs.first ?? 0)),
                           status: Text(verbatim: status),
                           fill: fillNow,
                           forecast: window == .now ? nil : fillEnd,
                           leading: Text(verbatim: leading),
                           trailing: Text(verbatim: trailing.uppercased()),
                           tone: fullAt != nil || (figures?.wasted ?? 0) > 0 ? .warn : .normal,
                           isSelected: selection == node.id,
                           isDimmed: path.map { !$0.contains(node.id) } ?? false)
    }

    // MARK: Command center

    private var commandCenter: some View {
        let center = colony.commandCenter
        var counts = [String(localized: "\(center.pinCount) pins"), String(localized: "\(center.linkCount) links"),
                      String(localized: "\(center.routeCount) routes")].joined(separator: " · ")
        if center.routesViaWaypoint > 0 {
            counts += ", " + String(localized: "\(center.routesViaWaypoint) of them via a waypoint")
        }
        return HUDListSection {
            HStack(alignment: .top, spacing: 14) {
                HUDResourceCell(title: Text("CPU"), used: center.cpuUsed, total: center.cpuTotal)
                HUDResourceCell(title: Text("Powergrid"), used: center.powerUsed, total: center.powerTotal)
            }
            .hudRow(HUDRowStyle(minHeight: 0, verticalPadding: 14))
            Text(verbatim: counts)
                .font(HUDFont.mono(11, weight: .regular, relativeTo: .caption))
                .textCase(.uppercase)
                .foregroundStyle(Color.hudInkMuted)
                .hudRow(HUDRowStyle(minHeight: 0, verticalPadding: 10))
        } header: {
            HUDSectionHeader(Text("Command Center")) {
                Text("Level \(center.level)")
            }
        } footer: {
            HUDFootnote(Text("Identical factories are grouped; figures are per group. Simulated from the last update, \(EVETime.dateTime(colony.lastUpdate)). Open the colony in game to refresh."))
        }
    }
}

// MARK: - Node sheet

/// The figures of one node of the chain, in the window the screen shows: a system sheet over
/// the chain, which stays visible and tappable above it at the medium detent.
struct PlanetaryChainNodeSheet: View {
    let colony: ColonyDetail
    let node: ChainNode
    let window: ChainWindow

    @Environment(\.dismiss) private var dismiss

    private struct Readout: Identifiable {
        var id: Int
        var label: String
        var value: String
        var isWarning = false
    }

    var body: some View {
        let detail = self.detail
        NavigationStack {
            HUDList(isTransparent: true) {
                HUDListSection {
                    ForEach(detail.rows) { row in
                        HUDReadoutRow(Text(verbatim: row.label)) {
                            Text(verbatim: row.value)
                                .foregroundStyle(row.isWarning ? Color.hudWarn : Color.hudInk)
                        }
                    }
                } header: {
                    HUDSectionHeader(Text(verbatim: detail.subtitle))
                } footer: {
                    HUDFootnote(Text(verbatim: detail.note), color: detail.noteIsWarning ? .hudWarnNoteInk : .hudInkMuted)
                }
            }
            .navigationTitle(Text(verbatim: detail.title))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationBackgroundInteraction(.enabled(upThrough: .medium))
    }

    private var windowLabel: String {
        switch window {
        case .now: String(localized: "Now")
        case .day: String(localized: "Avg 24 h")
        case .toEnd: String(localized: "Avg to end")
        }
    }

    private var destinations: String {
        let names = colony.chain.edges.filter { $0.from == node.id }.compactMap { edge in
            colony.chain.node(id: edge.to).map { target in
                target.kind.isStorage ? colony.facilityName(target.pinIDs.first ?? 0) : (target.product?.name ?? target.name)
            }
        }
        return Array(NSOrderedSet(array: names)).compactMap { $0 as? String }.joined(separator: ", ")
    }

    private var problem: ColonyIssue? {
        colony.issues.first { issue in
            guard let pin = issue.pinID else { return false }
            return node.pinIDs.contains(pin)
        }
    }

    private var detail: (title: String, subtitle: String, rows: [Readout], note: String, noteIsWarning: Bool) {
        let figures = node.figures[window]
        var rows: [Readout] = []
        func add(_ label: String, _ value: String, warn: Bool = false) {
            rows.append(Readout(id: rows.count, label: label, value: value, isWarning: warn))
        }
        let facilities = node.pinIDs.compactMap(colony.facility(pinID:))
        let issueText = problem.map { colony.describe($0, now: colony.now) }

        switch node.kind {
        case .extractor:
            let extractors = facilities.compactMap { facility -> ExtractorDetail? in
                if case let .extractor(extractor) = facility.role { extractor } else { nil }
            }
            if let program = extractors.first?.program {
                add(String(localized: "Program"),
                    "\(EVETime.monthDayTime(program.installTime)) → \(EVETime.monthDayTime(program.expiryTime))")
            }
            add(String(localized: "Heads"), "\(node.headCount)")
            add(windowLabel, PlanetaryFormat.rate(figures?.perHour ?? 0))
            if let utilization = figures?.utilization {
                add(String(localized: "Program done"), FitStatFormat.percent(utilization))
            }
            add(String(localized: "Extracted"), PlanetaryFormat.quantity(extractors.reduce(0) { $0 + $1.extractedSoFar }))
            add(String(localized: "Still to come"), PlanetaryFormat.quantity(extractors.reduce(0) { $0 + $1.stillToCome }))
            if !destinations.isEmpty { add(String(localized: "planetary.route.to", defaultValue: "To", comment: "Where the output goes: the facilities it is routed to"), destinations) }
            if let wasted = figures?.wasted, wasted > 0 {
                add(String(localized: "Lost"), PlanetaryFormat.quantity(wasted), warn: true)
            }
            let isLimit = node.product != nil && node.product == colony.chain.bottleneck
            let note = isLimit
                ? String(localized: "The bottleneck: more heads here, or a richer spot, would raise the colony's output. Change it in game.")
                : issueText?.detail ?? String(localized: "The yield falls toward the end of the program.")
            return (node.product?.name ?? node.name,
                    node.count > 1 ? String(localized: "\(node.count) extractors") : String(localized: "Extractor"),
                    rows, note, isLimit || problem != nil)

        case .basicIndustry, .advancedIndustry, .highTechIndustry:
            let factories = facilities.compactMap { facility -> FactoryDetail? in
                if case let .factory(factory) = facility.role { factory } else { nil }
            }
            if let factory = factories.first, let output = factory.output {
                let inputs = factory.inputs.map { "\(PlanetaryFormat.quantity($0.perCycle)) \($0.commodity.name)" }
                    .joined(separator: " + ")
                add(String(localized: "Schematic"),
                    "\(inputs) → \(PlanetaryFormat.quantity(output.quantity)) / \(EVETime.duration(factory.cycleTime))")
            }
            if node.count > 1 { add(String(localized: "Factories"), "\(node.count)") }
            var isLimited = false
            if case let .outputLimited(_, _, waitingFor, _, _) = problem {
                isLimited = true
                add(String(localized: "Waits for"), waitingFor.name, warn: true)
            }
            if let utilization = figures?.utilization {
                add(String(localized: "Busy"), FitStatFormat.percent(utilization), warn: isLimited)
            }
            add(windowLabel, PlanetaryFormat.rate(figures?.perHour ?? 0))
            if !destinations.isEmpty { add(String(localized: "planetary.route.to", defaultValue: "To", comment: "Where the output goes: the facilities it is routed to"), destinations) }
            switch window {
            case .now: break
            case .day: add(String(localized: "Made in 24 h"), PlanetaryFormat.gain(factories.reduce(0) { $0 + $1.madeInDay }))
            case .toEnd: add(String(localized: "Made by end"), PlanetaryFormat.gain(factories.reduce(0) { $0 + $1.madeToEnd }))
            }
            if let wasted = figures?.wasted, wasted > 0 {
                add(String(localized: "Lost"), PlanetaryFormat.quantity(wasted), warn: true)
            }
            let waiting = factories.flatMap(\.waitingFor)
            let note = issueText?.detail
                ?? (waiting.isEmpty
                    ? String(localized: "Runs at its schematic rate whenever its inputs are in.")
                    : String(localized: "Idle now: needs \(Set(waiting.map(\.name)).sorted().joined(separator: ", ")).")
                )
            return (node.product?.name ?? node.name,
                    "\(node.kind.title) · \(EVETime.duration(factories.first?.cycleTime ?? 0)) cycle",
                    rows, note, problem != nil)

        case .storage, .launchpad, .commandCenter:
            let pinID = node.pinIDs.first ?? 0
            guard let facility = facilities.first, case let .storage(storage) = facility.role else {
                return (node.name, node.kind.title, rows, "", false)
            }
            let capacity = storage.capacity
            add(String(localized: "Now"),
                "\(PlanetaryFormat.volume(storage.usedNow)) / \(PlanetaryFormat.volume(capacity)) m³ · \(FitStatFormat.percent(storage.fillNow))")
            let fullAt = window == .now ? storage.fullAt : figures?.fullAt
            if let fullAt { add(String(localized: "Full at"), EVETime.dateTime(fullAt), warn: true) }
            let flow = colony.chain.throughput(of: node.id, window: window)
            add(String(localized: "In"), PlanetaryFormat.rate(flow.in))
            add(String(localized: "Out"), PlanetaryFormat.rate(flow.out))
            if window != .now, let fill = figures?.fill {
                add(window == .day ? String(localized: "In 24 h") : String(localized: "At end"),
                    "\(PlanetaryFormat.volume(fill * capacity)) m³ · \(FitStatFormat.percent(fill))")
            }
            for stock in storage.contents.filter({ $0.quantity > 0 }).prefix(3) {
                add(String(localized: "Holds"), "\(PlanetaryFormat.quantity(stock.quantity)) \(stock.commodity.name)")
            }
            let lost = storage.lostIfNotEmptied.map { "\(PlanetaryFormat.quantity($0.quantity)) \($0.commodity.name)" }
            if !lost.isEmpty { add(String(localized: "Lost by end"), lost.joined(separator: ", "), warn: true) }
            let note = issueText.map { $0.advice ?? $0.detail }
                ?? String(localized: "Nothing here fills up before the end of the forecast.")
            return (colony.facilityName(pinID),
                    node.isHub ? String(localized: "\(node.kind.title) · Hub") : node.kind.title,
                    rows, note, issueText?.isWarning ?? false)
        }
    }
}

#if DEBUG
#Preview("Chain") {
    let model = PlanetaryModel.preview()
    NavigationStack {
        PlanetaryChainView(model: model, planetID: PlanetaryFixture.colonies[0].planetID)
    }
}

#Preview("Chain · hub selected") {
    @Previewable @State var window: ChainWindow = .toEnd
    @Previewable @State var selection: String? = PlanetaryReport.fixture().colonies[0].chain.nodes
        .first(where: \.isHub)?.id
    let colony = PlanetaryReport.fixture().colonies[0]
    NavigationStack {
        PlanetaryChainContent(colony: colony, now: colony.now, window: $window, selection: $selection)
            .navigationTitle("Production Chain")
            .navigationBarTitleDisplayMode(.inline)
    }
}
#endif
