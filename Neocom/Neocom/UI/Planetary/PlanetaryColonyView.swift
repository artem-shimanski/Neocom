import SwiftUI

/// One colony: what it makes, what happens next, and every facility, simulated from the
/// colony's last update to now and on to program end.
struct PlanetaryColonyView: View {
    let model: PlanetaryModel
    let planetID: Int64

    var body: some View {
        PlanetaryReportContent(model: model) { report in
            if let colony = report.colony(planetID: planetID) {
                TimelineView(.everyMinute) { context in
                    PlanetaryColonyContent(colony: colony, now: max(context.date, colony.now))
                }
                .navigationTitle(colony.planet.displayName)
            } else {
                ContentUnavailableView("No Colony", systemImage: "globe",
                                       description: Text("The character has no colony on this planet any more."))
            }
        }
        .hudScreen()
        .navigationBarTitleDisplayMode(.inline)
        .planetaryNotificationsButton()
    }
}

/// The screen's content at the moment `now` (the clock, which runs ahead of `colony.now`
/// between the report's rebuilds: countdowns follow it, simulated quantities do not).
struct PlanetaryColonyContent: View {
    let colony: ColonyDetail
    let now: Date

    private static let eventStyle = HUDRowStyle(minHeight: 0, verticalPadding: 12)
    private static let facilityStyle = HUDRowStyle(minHeight: 0, verticalPadding: 12)

    var body: some View {
        HUDList {
            Section {
                summary.hudBareRow()
            }

            forecast

            Section {
                chainLink
            }

            extractors
            factories
            storages
            commandCenter
        }
    }

    // MARK: Summary

    private var summary: some View {
        let planet = colony.planet
        return HUDPanel {
            HStack(alignment: .center, spacing: 14) {
                if let typeID = planet.kind.typeID {
                    HUDItemIcon(typeID: typeID, size: 72)
                }
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .center, spacing: 8) {
                        Text(verbatim: planet.displayName)
                            .font(HUDFont.display(24, weight: .bold, relativeTo: .title2))
                            .tracking(0.5)
                            .textCase(.uppercase)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        Spacer(minLength: 4)
                        colony.overview.status.chip
                    }
                    Text("\(planet.kind.title) · Command Center \(planet.commandCenterLevel)")
                        .font(HUDFont.mono(11, weight: .regular, relativeTo: .caption))
                        .tracking(1)
                        .textCase(.uppercase)
                        .foregroundStyle(Color.hudInkMuted)
                    if let system = planet.systemText {
                        (Text("\(system)\(Text(verbatim: planet.regionName.map { " · " + $0.uppercased() } ?? ""))"))
                            .font(.hudCaption)
                            .foregroundStyle(Color.hudInkMuted)
                    }
                }
            }
            .padding(.horizontal, HUDMetrics.gutter)
            .padding(.top, 16)
            .padding(.bottom, 14)

            HUDPanelRule()
            HUDStatStrip(items: summaryItems, valueFont: HUDFont.display(20, weight: .semibold, relativeTo: .title3))

            HUDPanelRule()
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 12, weight: .semibold))
                    .accessibilityHidden(true)
                Text("As of last update \(EVETime.dateTime(colony.lastUpdate)) · simulated \(EVETime.duration(now.timeIntervalSince(colony.lastUpdate))) since. Open the colony in game to refresh.")
            }
            .font(HUDFont.mono(11, weight: .regular, relativeTo: .caption))
            .lineSpacing(3)
            .foregroundStyle(Color.hudInkMuted)
            .padding(.horizontal, HUDMetrics.gutter)
            .padding(.top, 10)
            .padding(.bottom, 12)
        }
        .multilineTextAlignment(.leading)
    }

    private var summaryItems: [HUDStatStrip.Item] {
        let products = colony.overview.products
        var items: [HUDStatStrip.Item] = []
        if products.isEmpty {
            items.append(.init(id: 0, label: Text("Output"), value: Text(verbatim: "—")))
        } else {
            let rate = products.reduce(0) { $0 + $1.perHour }
            let nominal = products.reduce(0) { $0 + $1.nominalPerHour }
            let made = products.reduce(0) { $0 + $1.madeToEnd }
            items.append(.init(id: 0, label: Text(verbatim: products.count == 1 ? products[0].commodity.name : String(localized: "Output")),
                               value: Text(verbatim: PlanetaryFormat.number(rate)),
                               unit: Text("/h · of \(PlanetaryFormat.number(nominal))")))
            items.append(.init(id: 1, label: colony.horizonIsProgramEnd ? Text("To end") : Text("Next 24 h"),
                               value: Text(verbatim: PlanetaryFormat.gain(made)), color: .hudAccent))
        }
        if let fullest = colony.fullestStorage {
            items.append(.init(id: 2, label: Text(verbatim: fullest.facility.kind.shortTitle),
                               value: Text(verbatim: FitStatFormat.percent(fullest.storage.usedAtEnd / fullest.storage.capacity)),
                               color: fullest.storage.fullAt == nil ? .hudInk : .hudWarn,
                               unit: Text("At end")))
        }
        return items
    }

    // MARK: Forecast

    private var forecast: some View {
        HUDListSection(Text("Forecast")) {
            ForEach(colony.issues, id: \.self) { issue in
                let text = colony.describe(issue, now: now)
                event(text, color: color(of: issue, text: text))
            }
            wasteRow
        }
    }

    /// Colour is state: what the player has to act on is `warn`, unused stock is a fact.
    private func color(of issue: ColonyIssue, text: ColonyIssueText) -> Color {
        if case .unusedStock = issue { return .hudInkMuted }
        return .hudWarn
    }

    @ViewBuilder
    private func event(_ text: ColonyIssueText, color: Color) -> some View {
        let row = HUDEventRow(when: Text(verbatim: text.when), whenDetail: text.whenDetail.map { Text(verbatim: $0) },
                              whenColor: color, title: Text(verbatim: text.title), detail: Text(verbatim: text.detail),
                              showsChevron: text.route != nil)
        if let route = text.route {
            NavigationLink(value: route) {
                row.hudRow(Self.eventStyle)
            }
            .hudRowButton(Self.eventStyle)
        } else {
            row.hudRow(Self.eventStyle)
        }
    }

    /// The last line of the forecast: what is lost by the horizon, or that nothing is.
    private var wasteRow: some View {
        let until = colony.horizonIsProgramEnd ? String(localized: "until program end") : String(localized: "over the next 24 h")
        let storages = colony.facilities.compactMap { facility -> StorageDetail? in
            if case let .storage(storage) = facility.role, storage.capacity > 0 { storage } else { nil }
        }
        let text: ColonyIssueText
        if colony.wastedToEnd.isEmpty {
            let peak = storages.map { $0.peak / $0.capacity }.max() ?? 0
            // Rounded up to the next 5%: "under 15%" is the claim, the figure is not.
            let bound = min(1, (peak * 20).rounded(.up) / 20)
            let detail = peak > 0 && bound < 1
                ? String(localized: "Every storage stays under \(FitStatFormat.percent(bound)) \(until).")
                : String(localized: "Everything made has somewhere to go \(until).")
            text = ColonyIssueText(label: "", title: String(localized: "Nothing wasted"), detail: detail, advice: nil,
                                   when: String(localized: "to end"), whenDetail: nil, isWarning: false, route: nil)
        } else {
            let lost = colony.wastedToEnd.map { "\(PlanetaryFormat.quantity($0.quantity)) \($0.commodity.name)" }
            text = ColonyIssueText(label: "", title: String(localized: "Output lost \(until)"),
                                   detail: lost.joined(separator: ", "), advice: nil,
                                   when: String(localized: "to end"), whenDetail: nil, isWarning: true, route: nil)
        }
        return event(text, color: text.isWarning ? .hudWarn : .hudOk)
    }

    // MARK: Chain

    private var chainLink: some View {
        let tiers = Set(colony.chain.nodes.compactMap(\.product?.tier)).sorted()
        var subtitle = tiers.map(PlanetaryFormat.tier).joined(separator: " → ")
        if let bottleneck = colony.chain.bottleneck {
            subtitle += " · " + String(localized: "Limit \(bottleneck.name)")
        }
        return NavigationLink(value: PlanetaryRoute.chain(planetID: colony.id)) {
            HStack(spacing: 12) {
                Image(systemName: "point.3.connected.trianglepath.dotted")
                    .font(.system(size: 20, weight: .regular))
                    .foregroundStyle(Color.hudAccent)
                    .accessibilityHidden(true)
                HUDRowTitle(title: Text("Production chain"), subtitle: Text(verbatim: subtitle), font: .hudTileTitle)
                Spacer(minLength: 8)
                HUDChevron()
            }
            .hudRow()
        }
        .hudRowButton()
    }

    // MARK: Extractors

    private var extractorFacilities: [(FacilityDetail, ExtractorDetail)] {
        colony.facilities.compactMap { facility in
            if case let .extractor(extractor) = facility.role { (facility, extractor) } else { nil }
        }
    }

    @ViewBuilder
    private var extractors: some View {
        let rows = extractorFacilities
        if !rows.isEmpty {
            HUDListSection {
                ForEach(rows, id: \.0.id) { facility, extractor in
                    facilityLink(facility) {
                        extractorRow(facility, extractor)
                    }
                }
            } header: {
                HUDSectionHeader(Text("Extractors · \(rows.count)")) {
                    if let cycle = rows.lazy.compactMap({ row -> String? in
                        guard let current = row.1.currentCycle, let program = row.1.program else { return nil }
                        return String(localized: "Cycle \(current + 1) / \(program.cycleCount)")
                    }).first {
                        Text(verbatim: cycle)
                    }
                }
            }
        }
    }

    private func extractorRow(_ facility: FacilityDetail, _ extractor: ExtractorDetail) -> some View {
        let heads = String(localized: "\(extractor.headCount) heads")
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                HUDItemIcon(typeID: extractor.product?.typeID ?? facility.typeID, size: 32)
                HUDRowTitle(title: Text(verbatim: extractor.product?.name ?? facility.kind.title),
                            subtitle: Text(verbatim: "\(facility.name) · \(heads)"))
                Spacer(minLength: 8)
                switch extractor.state {
                case .running:
                    let rate = extractor.program.map { program in
                        program.cycleTime > 0 ? Double(extractor.nextDelivery ?? 0) * 3600 / program.cycleTime : 0
                    } ?? 0
                    let unit = Text(verbatim: "/H").font(.hudMicro).foregroundStyle(Color.hudInkMuted)
                    Text("\(Text(verbatim: PlanetaryFormat.number(rate)))\(unit)")
                        .font(.hudReadout)
                case .finished:
                    HUDStatusChip(text: Text("Finished"), color: .hudWarn, mark: .symbol("pause.fill"))
                case .notSetUp:
                    HUDStatusChip(text: Text("Not set up"), color: .hudWarn)
                }
                HUDChevron()
            }
            if let program = extractor.program {
                let span = program.expiryTime.timeIntervalSince(program.installTime)
                HUDResourceBar(fraction: span > 0 ? colony.now.timeIntervalSince(program.installTime) / span : 1,
                               color: extractor.state == .running ? .hudAccent : .hudWarn)
                    .padding(.leading, 44)
            }
        }
        .hudRow(Self.facilityStyle)
    }

    // MARK: Factories

    private var factoryFacilities: [(FacilityDetail, FactoryDetail)] {
        colony.facilities.compactMap { facility in
            if case let .factory(factory) = facility.role { (facility, factory) } else { nil }
        }
        .sorted { ($1.1.output?.commodity.tier ?? 0, $0.0.id) < ($0.1.output?.commodity.tier ?? 0, $1.0.id) }
    }

    @ViewBuilder
    private var factories: some View {
        let rows = factoryFacilities
        if !rows.isEmpty {
            HUDListSection {
                ForEach(rows, id: \.0.id) { facility, factory in
                    facilityLink(facility) {
                        factoryRow(facility, factory)
                    }
                }
            } header: {
                HUDSectionHeader(Text("Factories · \(rows.count)")) {
                    Text(colony.horizonIsProgramEnd ? String(localized: "Busy to end") : String(localized: "Busy next 24 h"))
                }
            }
        }
    }

    private func factoryRow(_ facility: FacilityDetail, _ factory: FactoryDetail) -> some View {
        let state: String
        let chip: HUDStatusChip
        switch factory.state {
        case let .running(_, cycleEnd):
            state = String(localized: "Cycle ends \(EVETime.time(cycleEnd))")
            chip = HUDStatusChip(text: Text("Running"), color: .hudAccent, mark: .dot)
        case .idle:
            state = factory.waitingFor.isEmpty
                ? String(localized: "Idle")
                : String(localized: "Needs \(factory.waitingFor.map(\.name).joined(separator: ", "))")
            chip = HUDStatusChip(text: Text("Idle"), color: .hudWarn, mark: .symbol("pause.fill"))
        case .notSetUp:
            state = String(localized: "No schematic")
            chip = HUDStatusChip(text: Text("Not set up"), color: .hudWarn)
        }
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                HUDItemIcon(typeID: factory.output?.commodity.typeID ?? facility.typeID, size: 32)
                HUDRowTitle(title: Text(verbatim: factory.output?.commodity.name ?? facility.kind.title),
                            subtitle: Text(verbatim: "\(facility.kind.shortTitle) · \(state)"))
                Spacer(minLength: 8)
                chip
                HUDChevron()
            }
            HStack(spacing: 10) {
                HUDResourceBar(fraction: factory.utilizationToEnd)
                Text(verbatim: FitStatFormat.percent(factory.utilizationToEnd))
                    .font(HUDFont.mono(11, weight: .regular, relativeTo: .caption))
                    .foregroundStyle(Color.hudInkBodyMuted)
                    .frame(minWidth: 34, alignment: .trailing)
            }
            .padding(.leading, 44)
        }
        .hudRow(Self.facilityStyle)
    }

    // MARK: Storage

    private var storageFacilities: [(FacilityDetail, StorageDetail)] {
        func order(_ kind: FacilityKind) -> Int {
            switch kind {
            case .storage: 0
            case .launchpad: 1
            default: 2
            }
        }
        return colony.facilities.compactMap { facility in
            if case let .storage(storage) = facility.role { (facility, storage) } else { nil }
        }
        .sorted { (order($0.0.kind), $0.0.id) < (order($1.0.kind), $1.0.id) }
    }

    @ViewBuilder
    private var storages: some View {
        let rows = storageFacilities
        if !rows.isEmpty {
            let fee = rows.filter { $0.0.kind != .storage }.reduce(0) { $0 + $1.1.exportFeeNow }
            HUDListSection {
                ForEach(rows, id: \.0.id) { facility, storage in
                    facilityLink(facility) {
                        storageRow(facility, storage)
                    }
                }
                if fee > 0 {
                    exportRow(fee: fee)
                }
            } header: {
                HUDSectionHeader(Text("Storage")) {
                    Text("Now → End")
                }
            }
        }
    }

    private func storageRow(_ facility: FacilityDetail, _ storage: StorageDetail) -> some View {
        let products = Set(colony.overview.products.map(\.commodity))
        let stocked = storage.contents.filter { products.contains($0.commodity) }
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(verbatim: colony.facilityName(facility.id))
                    .font(HUDFont.display(15, weight: .semibold, relativeTo: .body))
                    .lineLimit(1)
                Spacer(minLength: 8)
                let used = Text(verbatim: storage.usedNow == storage.usedAtEnd
                                ? PlanetaryFormat.volume(storage.usedNow)
                                : "\(PlanetaryFormat.volume(storage.usedNow)) → \(PlanetaryFormat.volume(storage.usedAtEnd))")
                let capacity = Text(verbatim: " / \(PlanetaryFormat.volume(storage.capacity)) m³")
                    .font(.hudMicro).foregroundStyle(Color.hudInkMuted)
                Text("\(used)\(capacity)")
                    .font(.hudCaption)
                    .lineLimit(1)
                    .layoutPriority(1)
                HUDChevron()
            }
            HUDResourceBar(fraction: storage.capacity > 0 ? storage.usedNow / storage.capacity : 0,
                           color: storage.fullAt == nil ? .hudAccent : .hudWarn, height: 6,
                           forecast: storage.capacity > 0 ? storage.usedAtEnd / storage.capacity : nil)
            ForEach(stocked) { stock in
                Text("\(PlanetaryFormat.quantity(stock.quantity)) \(stock.commodity.name) now · \(PlanetaryFormat.quantity(stock.atEnd)) at end")
                    .font(HUDFont.mono(11, weight: .regular, relativeTo: .caption))
                    .textCase(.uppercase)
                    .foregroundStyle(Color.hudInkMuted)
            }
        }
        .hudRow(Self.facilityStyle)
    }

    /// The customs fee for what lies on the launchpads and the command center now, with the
    /// assumption it rests on under it.
    private func exportRow(fee: Double) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Export fee now")
                    .tracking(1)
                    .textCase(.uppercase)
                    .foregroundStyle(Color.hudInkMuted)
                    .layoutPriority(1)
                HUDLeader().frame(minWidth: 12)
                Text(verbatim: "≈ \(Int(fee.rounded()).formatted()) ISK")
                    .layoutPriority(2)
            }
            .font(.hudReadout)
            Text("Customs fee at an assumed \(FitStatFormat.percent(PlanetaryAnalysis.assumedTaxRate)) tax. The office's real rate is not in ESI.")
                .font(.hudMicro)
                .lineSpacing(3)
                .foregroundStyle(Color.hudInkMuted)
        }
        .hudRow(.readout)
    }

    // MARK: Command center

    private var commandCenter: some View {
        let center = colony.commandCenter
        return HUDListSection {
            HStack(alignment: .top, spacing: 14) {
                HUDResourceCell(title: Text("CPU"), used: center.cpuUsed, total: center.cpuTotal)
                HUDResourceCell(title: Text("Powergrid"), used: center.powerUsed, total: center.powerTotal)
            }
            .hudRow(HUDRowStyle(minHeight: 0, verticalPadding: 14))
            HUDReadoutRow("Pins", value: center.pinCount.formatted())
            HUDReadoutRow(Text("Links"), value: String(localized: "\(center.linkCount) · Level \(center.maxLinkLevel)"))
            if let longest = center.longestLink {
                HUDReadoutRow("Longest link",
                              value: String(localized: "\(longest.formatted(.number.precision(.fractionLength(0...1)))) km"))
            }
            HUDReadoutRow(Text("Routes"), value: center.routesViaWaypoint > 0
                          ? String(localized: "\(center.routeCount) · \(center.routesViaWaypoint) via waypoint")
                          : center.routeCount.formatted())
        } header: {
            HUDSectionHeader(Text("Command Center")) {
                Text("Level \(center.level)")
            }
        } footer: {
            HUDFootnote(Text(verbatim: footnote))
        }
    }

    private var footnote: String {
        var parts = [colony.horizonIsProgramEnd
            ? String(localized: "Everything after \(EVETime.dateTime(colony.lastUpdate)) is simulated from the colony's layout. Rates are averages from now to program end, \(EVETime.dateTime(colony.horizon)).")
            : String(localized: "Everything after \(EVETime.dateTime(colony.lastUpdate)) is simulated from the colony's layout. Rates are averages over the next 24 hours.")]
        if colony.commandCenter.isLinkCostEstimated {
            parts.append(String(localized: "Link lengths are not known, so CPU and powergrid read lower than in game."))
        }
        parts += colony.warnings
        return parts.joined(separator: " ")
    }

    // MARK: Links

    private func facilityLink(_ facility: FacilityDetail, @ViewBuilder label: () -> some View) -> some View {
        NavigationLink(value: PlanetaryRoute.facility(planetID: colony.id, pinID: facility.id)) {
            label()
        }
        .hudRowButton(Self.facilityStyle)
    }
}

#if DEBUG
#Preview("Colony") {
    let model = PlanetaryModel.preview()
    NavigationStack {
        PlanetaryColonyView(model: model, planetID: PlanetaryFixture.colonies[0].planetID)
            .navigationDestination(for: PlanetaryRoute.self) { $0.destination(model: model) }
    }
}

#Preview("Colony · programs over") {
    let model = PlanetaryModel.preview(.fixture(simulatedFor: 6 * 86_400))
    NavigationStack {
        PlanetaryColonyView(model: model, planetID: PlanetaryFixture.colonies[0].planetID)
    }
}
#endif
