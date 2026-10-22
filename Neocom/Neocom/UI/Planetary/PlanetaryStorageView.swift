import SwiftUI

/// A storage facility, launchpad or command center: how full it is and will be, the fill over
/// the forecast, what lies in it and what moves through, what is lost if nobody empties it, and
/// its routes.
struct PlanetaryStorageContent: View {
    let colony: ColonyDetail
    let facility: FacilityDetail
    let storage: StorageDetail
    let now: Date

    private var isFilling: Bool { storage.fullAt != nil }
    private var stateColor: Color { isFilling ? .hudWarn : .hudAccent }
    private var name: String { colony.facilityName(facility.id) }

    var body: some View {
        HUDList {
            Section {
                header.hudBareRow()
            }
            if storage.capacity > 0 && storage.fill.count > 1 {
                fillChart
            }
            contents
            unused
            haul
            if facility.kind == .commandCenter {
                commandCenter
            }
            alsoOnColony
            routes
        }
    }

    // MARK: Header

    private var header: some View {
        let chip: HUDStatusChip? = storage.fullAt.map { at in
            at <= now
                ? HUDStatusChip(text: Text("Full"), color: .hudWarn, mark: .dot)
                : HUDStatusChip(text: Text("Filling"), color: .hudWarn, mark: .dot)
        }
        let capacity = String(localized: "Capacity \(PlanetaryFormat.volume(storage.capacity)) m³")
        let sameKind = colony.facilities.filter { $0.kind == facility.kind }.count
        return PlanetaryFacilityHeader(tone: isFilling ? .warn : .normal, typeID: facility.typeID,
                                       title: Text(verbatim: facility.kind.title),
                                       subtitle: Text(verbatim: sameKind > 1 ? "\(facility.name) · \(capacity)" : capacity),
                                       chip: chip) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(verbatim: FitStatFormat.percent(storage.fillNow))
                        .font(.hudFigureXL)
                        .foregroundStyle(stateColor)
                    Text(verbatim: "\(PlanetaryFormat.volume(storage.usedNow)) / \(PlanetaryFormat.volume(storage.capacity)) m³")
                        .font(.hudCaption)
                        .foregroundStyle(Color.hudInkMuted)
                    Spacer(minLength: 0)
                }
                HUDResourceBar(fraction: storage.fillNow, color: stateColor, height: 6,
                               forecast: storage.capacity > 0 ? storage.usedAtEnd / storage.capacity : nil)
            }
            .padding(.horizontal, HUDMetrics.gutter)
            .padding(.bottom, 14)

            HUDPanelRule()
            HUDStatStrip(items: stats, valueFont: HUDFont.display(20, weight: .semibold, relativeTo: .title3),
                         unitCase: nil)

            if let fullAt = storage.fullAt {
                HUDWarnNote(Text(verbatim: fullAt <= now
                    ? String(localized: "Full since \(EVETime.dateTime(fullAt)). New output has nowhere to go and is lost. Empty the \(name) in game.")
                    : String(localized: "Full at \(EVETime.dateTime(fullAt)). After that new output has nowhere to go and is lost. Empty the \(name) in game before then.")))
            }
        }
    }

    private var stats: [HUDStatStrip.Item] {
        if let fullAt = storage.fullAt {
            return [
                .init(id: 0, label: fullAt <= now ? Text("Full for") : Text("Full in"),
                      value: Text(verbatim: EVETime.duration(abs(fullAt.timeIntervalSince(now)))), color: .hudWarn),
                .init(id: 1, label: Text("Inflow"), value: Text(verbatim: PlanetaryFormat.number(storage.inflowPerHour)),
                      unit: Text(verbatim: "m³/h")),
                .init(id: 2, label: Text("Free"), value: Text(verbatim: PlanetaryFormat.volume(max(0, storage.capacity - storage.usedNow))),
                      unit: Text(verbatim: "m³")),
            ]
        }
        return [
            .init(id: 0, label: Text("At end"), value: Text(verbatim: PlanetaryFormat.volume(storage.usedAtEnd)), unit: Text(verbatim: "m³")),
            .init(id: 1, label: Text(String(localized: "planetary.storage.peak", defaultValue: "Peak", comment: "The highest fill of a storage, noun")), value: Text(verbatim: PlanetaryFormat.volume(storage.peak)), unit: Text(verbatim: "m³")),
            .init(id: 2, label: Text("Full"), value: Text("Never"), color: .hudOk),
        ]
    }

    // MARK: Fill chart

    private var fillChart: some View {
        let points = storage.fill.map { HUDFillChart.Point(date: $0.date, value: $0.volume, isForecast: $0.isForecast) }
        let lost = !storage.lostIfNotEmptied.isEmpty || colony.issues.contains { issue in
            if case let .storageFull(pin, _) = issue { pin == facility.id } else { false }
        }
        var legend: [HUDChartLegend.Item] = [
            .init(id: 0, swatch: .line(stateColor), text: Text("Simulated")),
            .init(id: 1, swatch: .dashedLine(stateColor), text: Text("Forecast")),
        ]
        if isFilling {
            legend.append(.init(id: 2, swatch: .dashedLine(.hudInkMuted), text: Text("Capacity")))
        } else {
            legend.append(.init(id: 2, swatch: .none,
                                text: colony.horizonIsProgramEnd ? Text("Not full before end") : Text("Not full in 24 h"),
                                color: .hudOk))
        }
        return HUDListSection {
            VStack(alignment: .leading, spacing: 6) {
                HUDFillChart(points: points, capacity: storage.capacity, now: now, limit: storage.fullAt,
                             limitLabel: storage.fullAt.map { Text("Full \(EVETime.monthDayTime($0))") },
                             beyondLimitLabel: lost ? Text("Output lost") : nil,
                             capacityLabel: isFilling ? nil : Text("Capacity"),
                             color: stateColor)
                HStack {
                    Text(verbatim: EVETime.monthDayTime(points.first?.date ?? colony.lastUpdate))
                    Spacer()
                    Text(verbatim: EVETime.monthDayTime(points.last?.date ?? colony.horizon))
                }
                .font(.hudMicro)
                .foregroundStyle(Color.hudInkMuted)
                .padding(.leading, 36)
                HUDChartLegend(items: legend)
                    .padding(.top, 4)
            }
            .hudRow(HUDRowStyle(minHeight: 0, verticalPadding: 14))
        } header: {
            HUDSectionHeader(colony.horizonIsProgramEnd ? Text("Fill over the program") : Text("Fill over the next 24 h"))
        }
    }

    // MARK: Contents

    private var contents: some View {
        let movesOut = storage.contents.contains { $0.outPerHour > 0 }
        return HUDListSection {
            if storage.contents.isEmpty {
                Text("Empty")
                    .font(.hudReadout)
                    .foregroundStyle(Color.hudInkMuted)
                    .hudRow()
            }
            ForEach(storage.contents) { stock in
                stockRow(stock)
            }
            if !storage.contents.isEmpty {
                PlanetaryCardNote(text: colony.horizonIsProgramEnd
                    ? Text("In and out are averages from now to program end.")
                    : Text("In and out are averages over the next 24 hours."))
            }
        } header: {
            HUDSectionHeader(Text("Contents · now")) {
                Text(movesOut ? String(localized: "In / out per h") : String(localized: "In per h"))
            }
        }
    }

    private func stockRow(_ stock: StorageDetail.Stock) -> some View {
        var subtitle = "\(PlanetaryFormat.quantity(stock.quantity)) · "
        if stock.isPassThrough {
            subtitle += String(localized: "Passes through")
        } else {
            subtitle += PlanetaryFormat.cubicMetres(stock.volume)
            if stock.atEnd != stock.quantity {
                subtitle += " · " + String(localized: "\(PlanetaryFormat.quantity(stock.atEnd)) at end")
            }
        }
        return HStack(spacing: 12) {
            HUDItemIcon(typeID: stock.commodity.typeID, size: 32)
            HUDRowTitle(title: Text(verbatim: stock.commodity.name), subtitle: Text(verbatim: subtitle), subtitleCase: nil)
            Spacer(minLength: 8)
            if stock.isUnused {
                HUDStatusChip(text: Text("Unused"), color: .hudWarn)
            } else if stock.inPerHour > 0 || stock.outPerHour > 0 {
                VStack(alignment: .trailing, spacing: 1) {
                    if stock.inPerHour > 0 {
                        Text(verbatim: "+" + PlanetaryFormat.number(stock.inPerHour))
                    }
                    if stock.outPerHour > 0 {
                        Text(verbatim: "−" + PlanetaryFormat.number(stock.outPerHour))
                            .foregroundStyle(Color.hudInkMuted)
                    } else {
                        Text(verbatim: PlanetaryFormat.cubicMetres(stock.inPerHour * stock.commodity.volume))
                            .foregroundStyle(Color.hudInkMuted)
                    }
                }
                .font(.hudCaption)
            }
        }
        .hudRow(HUDRowStyle(minHeight: 60, verticalPadding: 10))
    }

    // MARK: Unused stock

    @ViewBuilder
    private var unused: some View {
        if let stock = storage.contents.filter(\.isUnused).max(by: { $0.volume < $1.volume }), storage.usedNow > 0 {
            Section {
                HUDPanel(tone: .warn) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(stock.commodity.name) are \(FitStatFormat.percent(stock.volume / storage.usedNow)) of what is stored")
                            .font(HUDFont.display(15, weight: .semibold, relativeTo: .body))
                        Text("No factory on this colony takes them and no route moves them, so the \(PlanetaryFormat.quantity(stock.quantity)) stay put.")
                            .font(HUDFont.mono(11, weight: .regular, relativeTo: .caption))
                            .lineSpacing(3)
                            .foregroundStyle(Color.hudInkBodyMuted)
                    }
                    .padding(.horizontal, HUDMetrics.gutter)
                    .padding(.vertical, 12)
                    HUDWarnNote(Text("Haul them out, or set up a factory that takes them, in game."))
                }
                .hudBareRow()
            }
        }
    }

    // MARK: If not emptied

    @ViewBuilder
    private var haul: some View {
        let showsFee = facility.kind != .storage && storage.exportFeeNow > 0
        if !storage.lostIfNotEmptied.isEmpty || showsFee {
            HUDListSection {
                ForEach(storage.lostIfNotEmptied, id: \.commodity) { amount in
                    HUDReadoutRow(Text("\(amount.commodity.name) lost")) {
                        Text(verbatim: "≈ \(PlanetaryFormat.quantity(amount.quantity))").foregroundStyle(Color.hudWarn)
                    }
                }
                HUDReadoutRow(Text("To haul now"), value: "\(PlanetaryFormat.volume(storage.usedNow)) m³")
                if showsFee {
                    HUDReadoutRow(Text("Export fee now"), value: "≈ \(Int(storage.exportFeeNow.rounded()).formatted()) ISK")
                }
            } header: {
                if storage.lostIfNotEmptied.isEmpty {
                    HUDSectionHeader(Text("Haul"))
                } else {
                    HUDSectionHeader(Text("If not emptied")) {
                        Text(String(localized: "planetary.storage.until", defaultValue: "To \(EVETime.monthDayTime(colony.horizon))", comment: "Up to a date and time: the end of the forecast"))
                    }
                }
            } footer: {
                if showsFee {
                    HUDFootnote(Text("Customs fee at an assumed \(FitStatFormat.percent(PlanetaryAnalysis.assumedTaxRate)) tax. The office's real rate is not in ESI."))
                }
            }
        }
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
            HUDReadoutRow(Text("Routes"), value: center.routeCount.formatted())
        } header: {
            HUDSectionHeader(Text("Command Center")) {
                Text("Level \(center.level)")
            }
        }
    }

    // MARK: Also on this colony

    @ViewBuilder
    private var alsoOnColony: some View {
        let others = colony.issues.filter { issue in
            guard issue.isWarning, issue.pinID != facility.id else { return false }
            switch issue {
            case .outputWasted, .storageFull, .extractorsStopped: return false
            default: return true
            }
        }
        if !others.isEmpty {
            let style = HUDRowStyle(minHeight: 0, verticalPadding: 12)
            HUDListSection(Text("Also on this colony")) {
                ForEach(others, id: \.self) { issue in
                    let text = colony.describe(issue, now: now)
                    let row = HUDEventRow(when: Text(verbatim: text.when), whenDetail: text.whenDetail.map { Text(verbatim: $0) },
                                          whenColor: .hudWarn, title: Text(verbatim: text.title),
                                          detail: Text(verbatim: text.advice ?? text.detail),
                                          showsChevron: text.route != nil)
                    if let route = text.route {
                        NavigationLink(value: route) { row.hudRow(style) }
                            .hudRowButton(style)
                    } else {
                        row.hudRow(style)
                    }
                }
            }
        }
    }

    // MARK: Routes

    private struct RouteGroup {
        var tag: Text
        var pinIDs: [Int64]
        var commodities: [PlanetaryCommodity]
    }

    /// Routes in and out, one line per kind of facility at the other end.
    private func groups(_ routes: [RouteLine], incoming: Bool) -> [RouteGroup] {
        var order: [FacilityKind] = []
        var byKind: [FacilityKind: (pins: [Int64], commodities: [PlanetaryCommodity])] = [:]
        for route in routes {
            if byKind[route.pinKind] == nil { order.append(route.pinKind) }
            var entry = byKind[route.pinKind] ?? ([], [])
            if !entry.pins.contains(route.pinID) { entry.pins.append(route.pinID) }
            if !entry.commodities.contains(route.commodity) { entry.commodities.append(route.commodity) }
            byKind[route.pinKind] = entry
        }
        return order.compactMap { kind in
            guard let entry = byKind[kind] else { return nil }
            let direction = incoming ? String(localized: "In") : String(localized: "Out")
            let what = entry.pins.count > 1 ? "\(kind.shortTitle) × \(entry.pins.count)" : kind.shortTitle
            return RouteGroup(tag: Text(verbatim: "\(direction) · \(what)"), pinIDs: entry.pins, commodities: entry.commodities)
        }
    }

    @ViewBuilder
    private var routes: some View {
        let all = groups(facility.routesIn, incoming: true) + groups(facility.routesOut, incoming: false)
        if all.isEmpty {
            Section {
            } footer: {
                HUDFootnote(colony.simulatedFootnote).hudListFooter()
            }
        } else {
            HUDListSection {
                ForEach(all.indices, id: \.self) { index in
                    let group = all[index]
                    let row = HUDReadoutRow(group.tag) {
                        Text(verbatim: group.commodities.map(\.name).joined(separator: ", "))
                            .lineLimit(2)
                    }
                    if group.pinIDs.count == 1, let pin = group.pinIDs.first {
                        NavigationLink(value: PlanetaryRoute.facility(planetID: colony.id, pinID: pin)) { row }
                            .hudRowButton(.readout)
                    } else {
                        row
                    }
                }
            } header: {
                HUDSectionHeader(Text("Routes · \(facility.routesIn.count + facility.routesOut.count)"))
            } footer: {
                HUDFootnote(colony.simulatedFootnote)
            }
        }
    }
}

#if DEBUG
#Preview("Storage") {
    let model = PlanetaryModel.preview()
    let colony = model.report!.colonies[0]
    let pin = colony.facilities.first { $0.kind == .storage }?.id ?? colony.facilities[0].id
    NavigationStack {
        PlanetaryFacilityView(model: model, planetID: colony.id, pinID: pin)
    }
}

#Preview("Launchpad · programs over") {
    let model = PlanetaryModel.preview(.fixture(simulatedFor: 6 * 86_400))
    let colony = model.report!.colonies[0]
    let pin = colony.facilities.first { $0.kind == .launchpad }?.id ?? colony.facilities[0].id
    NavigationStack {
        PlanetaryFacilityView(model: model, planetID: colony.id, pinID: pin)
    }
}
#endif
