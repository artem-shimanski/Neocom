import SwiftUI

/// An extractor: what it pulls, the yield of every cycle of its program (done and to come), the
/// cycle under way, the program, and where the output goes.
struct PlanetaryExtractorContent: View {
    let colony: ColonyDetail
    let facility: FacilityDetail
    let extractor: ExtractorDetail
    let now: Date

    @State private var selection: Int?

    var body: some View {
        HUDList {
            Section {
                header.hudBareRow()
            }
            if let program = extractor.program, !program.yields.isEmpty {
                yieldChart(program)
                currentCycle(program)
                programCard(program)
            } else {
                notSetUp
            }
            outputs
        }
    }

    // MARK: Header

    private var header: some View {
        let product = extractor.product
        let subtitle = String(localized: "Extractor \(facility.name) · \(extractor.headCount) / \(extractor.maxHeads) heads")
        return PlanetaryFacilityHeader(tone: extractor.state == .running ? .normal : .warn,
                                       typeID: product?.typeID ?? facility.typeID,
                                       title: Text(verbatim: product?.name ?? facility.kind.title),
                                       subtitle: Text(verbatim: subtitle),
                                       chip: chip) {
            if let program = extractor.program {
                HUDPanelRule()
                HUDStatStrip(items: [
                    .init(id: 0, label: Text("Avg per hour"), value: Text(verbatim: PlanetaryFormat.number(extractor.programPerHour))),
                    .init(id: 1, label: Text("Program"), value: Text(verbatim: PlanetaryFormat.quantity(program.total))),
                    .init(id: 2, label: Text("Still to come"), value: Text(verbatim: PlanetaryFormat.quantity(extractor.stillToCome)),
                          color: extractor.stillToCome > 0 ? .hudAccent : .hudInk),
                ], valueFont: HUDFont.display(20, weight: .semibold, relativeTo: .title3))
            }
        }
    }

    private var chip: HUDStatusChip {
        switch extractor.state {
        case .running: HUDStatusChip(text: Text("Running"), color: .hudOk, mark: .dot)
        case .finished: HUDStatusChip(text: Text("Finished"), color: .hudWarn, mark: .symbol("pause.fill"))
        case .notSetUp: HUDStatusChip(text: Text("No program"), color: .hudWarn)
        }
    }

    // MARK: Yield chart

    /// Now, in cycles from the program's start.
    private func nowPosition(_ program: ExtractorDetail.Program) -> Double {
        guard program.cycleTime > 0 else { return Double(program.cycleCount) }
        return min(Double(program.cycleCount), max(0, now.timeIntervalSince(program.installTime) / program.cycleTime))
    }

    private func yieldChart(_ program: ExtractorDetail.Program) -> some View {
        let position = nowPosition(program)
        let current = Int(position.rounded(.down))
        let selected = min(max(selection ?? max(0, min(current, program.cycleCount) - 1), 0), program.cycleCount - 1)
        let cumulative = program.yields.prefix(selected + 1).reduce(0, +)
        let elapsed = Double(selected + 1) * program.cycleTime
        let isPast = selected < current, isCurrent = selected == current
        let tag = isPast ? String(localized: "Extracted") : isCurrent ? String(localized: "In progress") : String(localized: "Forecast")

        return HUDListSection {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("Cycle \(selected + 1)")
                        .font(HUDFont.display(17, weight: .bold, relativeTo: .headline))
                        .tracking(0.5)
                        .textCase(.uppercase)
                    Text(verbatim: tag)
                        .font(.hudMicro)
                        .tracking(1)
                        .textCase(.uppercase)
                        .foregroundStyle(isPast ? Color.hudInkMuted : Color.hudAccent)
                    Spacer(minLength: 8)
                    Text(verbatim: PlanetaryFormat.quantity(program.yields[selected]))
                        .font(HUDFont.mono(20, weight: .semibold, relativeTo: .title3))
                        .foregroundStyle(isPast ? Color.hudInk : Color.hudAccent)
                        .contentTransition(.numericText())
                }
                HStack(alignment: .top, spacing: 8) {
                    figure(Text("Cumulative"), PlanetaryFormat.quantity(cumulative))
                    figure(Text("Elapsed"), EVETime.duration(elapsed))
                    figure(Text("Avg / h"), PlanetaryFormat.number(elapsed > 0 ? Double(cumulative) * 3600 / elapsed : 0))
                }
            }
            .hudRow(HUDRowStyle(minHeight: 0, verticalPadding: 12))

            VStack(alignment: .leading, spacing: 6) {
                HUDCycleBarChart(values: program.yields.map(Double.init), nowPosition: position,
                                 selection: Binding(get: { selected }, set: { selection = $0 }))
                HStack {
                    Text(verbatim: EVETime.monthDayTime(program.installTime))
                    Spacer()
                    Text(verbatim: EVETime.monthDayTime(program.expiryTime))
                }
                .font(.hudMicro)
                .foregroundStyle(Color.hudInkMuted)
                .padding(.leading, 36)
                HUDChartLegend(items: [
                    .init(id: 0, swatch: .block(.hudAccent), text: Text("Extracted")),
                    .init(id: 1, swatch: .block(.hudAccent.opacity(0.28)), text: Text("Forecast")),
                    .init(id: 2, swatch: .block(.hudInk), text: Text("Selected")),
                ])
                .padding(.top, 6)
            }
            .hudRow(HUDRowStyle(minHeight: 0, verticalPadding: 14))
        } header: {
            HUDSectionHeader(Text("Yield per cycle")) {
                Text(verbatim: "\(program.cycleCount) × \(PlanetaryFormat.cycle(program.cycleTime))")
            }
        }
    }

    private func figure(_ label: Text, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            label
                .font(.hudMicro)
                .tracking(1.5)
                .textCase(.uppercase)
                .foregroundStyle(Color.hudInkMuted)
                .lineLimit(1)
            Text(verbatim: value)
                .font(HUDFont.mono(13, weight: .regular, relativeTo: .subheadline))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    // MARK: Current cycle

    @ViewBuilder
    private func currentCycle(_ program: ExtractorDetail.Program) -> some View {
        if extractor.state == .running, let index = extractor.currentCycle,
           let start = extractor.currentCycleStart, let end = extractor.currentCycleEnd {
            HUDListSection(Text("Current cycle · \(index + 1)")) {
                VStack(alignment: .leading, spacing: 8) {
                    HUDCycleProgress(start: start, end: end,
                                     trailing: Text("Ends \(EVETime.time(end))"),
                                     figureFont: HUDFont.mono(18, weight: .semibold, relativeTo: .headline))
                    if let delivery = extractor.nextDelivery {
                        Text(verbatim: deliverySentence(delivery))
                            .font(HUDFont.mono(11, weight: .regular, relativeTo: .caption))
                            .textCase(.uppercase)
                            .foregroundStyle(Color.hudInkMuted)
                    }
                }
                .hudRow(HUDRowStyle(minHeight: 0, verticalPadding: 14))
            }
        }
    }

    private func deliverySentence(_ quantity: Int) -> String {
        let volume = PlanetaryFormat.cubicMetres(Double(quantity) * (extractor.product?.volume ?? 0))
        if let destination = facility.routesOut.first {
            return String(localized: "Delivers \(PlanetaryFormat.quantity(quantity)) to \(colony.facilityName(destination.pinID)) · \(volume)")
        }
        return String(localized: "Delivers \(PlanetaryFormat.quantity(quantity)) · \(volume), with no route to take it")
    }

    // MARK: Program

    private func programCard(_ program: ExtractorDetail.Program) -> some View {
        let volume = extractor.product?.volume ?? 0
        return HUDListSection(Text("Program")) {
            HUDReadoutRow("Started", value: EVETime.dateTime(program.installTime))
            HUDReadoutRow("Ends", value: EVETime.dateTime(program.expiryTime))
            if program.expiryTime > now {
                HUDReadoutRow("Time left", value: EVETime.duration(program.expiryTime.timeIntervalSince(now)))
            }
            HUDReadoutRow(Text("Cycle"), value: String(localized: "\(PlanetaryFormat.cycle(program.cycleTime)) · \(program.cycleCount) cycles"))
            HUDReadoutRow(Text("Extracted so far"),
                          value: "\(PlanetaryFormat.quantity(extractor.extractedSoFar)) · \(PlanetaryFormat.cubicMetres(Double(extractor.extractedSoFar) * volume))")
            if let product = extractor.product {
                HUDReadoutRow(Text("Product"), value: "\(PlanetaryFormat.tier(product.tier)) · \(PlanetaryFormat.unitVolume(product.volume))")
            }
            if extractor.wastedToEnd > 0 {
                HUDReadoutRow("Wasted") {
                    Text(verbatim: PlanetaryFormat.quantity(extractor.wastedToEnd)).foregroundStyle(Color.hudWarn)
                }
            }
            if extractor.state == .running {
                PlanetaryCardNote(text: Text(verbatim: restartSentence(program)))
            } else {
                PlanetaryCardNote(text: Text("The program ended \(EVETime.dateTime(program.expiryTime)). Restart it in game."),
                                  color: .hudWarnNoteInk)
            }
        }
    }

    private func restartSentence(_ program: ExtractorDetail.Program) -> String {
        let end = EVETime.dateTime(program.expiryTime)
        if let factory = consumers.first {
            return String(localized: "Restart the program in game before \(end) to keep the \(colony.producerName(factory.facility.id)) fed.")
        }
        return String(localized: "Restart the program in game before \(end).")
    }

    // MARK: Not set up

    private var notSetUp: some View {
        Section {
            HUDPanel(tone: .warn) {
                HUDRowTitle(title: Text("No program"),
                            subtitle: Text("\(extractor.headCount) heads · nothing selected"))
                    .padding(.horizontal, HUDMetrics.gutter)
                    .padding(.vertical, 12)
                HUDWarnNote(Text("Placed but never started, so it is left out of the simulation. Set a program in game."))
            }
            .hudBareRow()
        }
    }

    // MARK: Output

    /// Factories that take this extractor's product from where its routes deliver it.
    private var consumers: [(facility: FacilityDetail, input: FactoryDetail.Input)] {
        guard let product = extractor.product else { return [] }
        let destinations = Set(facility.routesOut.map(\.pinID))
        return colony.facilities.compactMap { other in
            guard case let .factory(factory) = other.role,
                  other.routesIn.contains(where: { $0.commodity == product && (destinations.contains($0.pinID) || $0.pinID == facility.id) }),
                  let input = factory.inputs.first(where: { $0.commodity == product }) else { return nil }
            return (other, input)
        }
    }

    @ViewBuilder
    private var outputs: some View {
        let routes = facility.routesOut
        let consumers = consumers
        if !routes.isEmpty || !consumers.isEmpty {
            HUDListSection {
                ForEach(routes) { route in
                    PlanetaryRouteRow(tag: Text("Route"),
                                      title: Text(verbatim: colony.facilityName(route.pinID)),
                                      subtitle: routes.count == 1 ? Text("All output") : Text(verbatim: route.commodity.name),
                                      route: .facility(planetID: colony.id, pinID: route.pinID))
                }
                ForEach(consumers, id: \.facility.id) { consumer in
                    PlanetaryRouteRow(tag: Text("Then"),
                                      title: Text(verbatim: colony.producerName(consumer.facility.id)),
                                      subtitle: Text("\(consumer.facility.kind.title) · \(PlanetaryFormat.quantity(consumer.input.perCycle)) per cycle"),
                                      route: .facility(planetID: colony.id, pinID: consumer.facility.id))
                }
            } header: {
                HUDSectionHeader(Text("Output goes to"))
            } footer: {
                HUDFootnote(Text("Yields come from the program set in game; the bars after now are the forecast. As of last update \(EVETime.dateTime(colony.lastUpdate))."))
            }
        } else {
            Section {
            } footer: {
                HUDFootnote(colony.simulatedFootnote).hudListFooter()
            }
        }
    }
}

#if DEBUG
#Preview("Extractor") {
    let model = PlanetaryModel.preview()
    let colony = model.report!.colonies[0]
    let pin = colony.facilities.first { $0.kind == .extractor }!.id
    NavigationStack {
        PlanetaryFacilityView(model: model, planetID: colony.id, pinID: pin)
    }
}
#endif
