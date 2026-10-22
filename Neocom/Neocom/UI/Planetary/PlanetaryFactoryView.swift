import SwiftUI

/// A factory: its cycle (or what it waits for), the schematic with what lies in its buffer, how
/// busy it is until the horizon, and its routes.
struct PlanetaryFactoryContent: View {
    let colony: ColonyDetail
    let facility: FacilityDetail
    let factory: FactoryDetail
    let now: Date

    var body: some View {
        HUDList {
            Section {
                header.hudBareRow()
            }
            if !factory.inputs.isEmpty || factory.output != nil {
                schematic
                activity
            }
            routes
        }
    }

    private var isIdle: Bool {
        if case .idle = factory.state { true } else { false }
    }

    // MARK: Header

    private var header: some View {
        let chip: HUDStatusChip
        switch factory.state {
        case .running: chip = HUDStatusChip(text: Text("Running"), color: .hudAccent, mark: .dot)
        case .idle: chip = HUDStatusChip(text: Text("Idle"), color: .hudWarn, mark: .symbol("pause.fill"))
        case .notSetUp: chip = HUDStatusChip(text: Text("Not set up"), color: .hudWarn)
        }
        return PlanetaryFacilityHeader(tone: isIdle || factory.state == .notSetUp ? .warn : .normal,
                                       typeID: factory.output?.commodity.typeID ?? facility.typeID,
                                       title: Text(verbatim: factory.output?.commodity.name ?? facility.kind.title),
                                       subtitle: Text("\(facility.kind.title) facility"),
                                       chip: chip) {
            switch factory.state {
            case let .running(cycleStart, cycleEnd):
                let output = factory.output.map { "+\(PlanetaryFormat.quantity($0.quantity)) \($0.commodity.name) " } ?? ""
                HUDCycleProgress(start: cycleStart, end: cycleEnd,
                                 trailing: Text(verbatim: output + String(localized: "at \(EVETime.time(cycleEnd))")))
                    .padding(.horizontal, HUDMetrics.gutter)
                    .padding(.bottom, 14)
            case let .idle(since, resumesAt):
                waiting(since: since)
                    .padding(.horizontal, HUDMetrics.gutter)
                    .padding(.bottom, 14)
                HUDWarnNote(Text(verbatim: idleSentence(resumesAt: resumesAt)))
            case .notSetUp:
                HUDWarnNote(Text("Factory \(facility.name) has no schematic and makes nothing. Pick a schematic in game."))
            }
        }
    }

    private func waiting(since: Date?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(verbatim: since.map { String(localized: "Waiting \(EVETime.duration(now.timeIntervalSince($0)))") }
                    ?? String(localized: "Waiting"))
                    .font(HUDFont.mono(13, weight: .regular, relativeTo: .subheadline))
                    .textCase(.uppercase)
                    .foregroundStyle(Color.hudWarn)
                Spacer(minLength: 8)
                Text(verbatim: since.map { String(localized: "Since \(EVETime.time($0))") }
                    ?? String(localized: "Since before the last update"))
                    .font(.hudCaption)
                    .textCase(.uppercase)
                    .foregroundStyle(Color.hudInkBodyMuted)
            }
            HUDHatch()
                .frame(height: 6)
                .clipShape(.capsule)
        }
    }

    private func idleSentence(resumesAt: Date?) -> String {
        var parts: [String] = []
        if let input = factory.inputs.first(where: { factory.waitingFor.contains($0.commodity) }) {
            parts.append(String(localized: "Needs \(PlanetaryFormat.quantity(input.perCycle)) \(input.commodity.name) per cycle and has \(PlanetaryFormat.quantity(input.buffered))."))
        }
        if let resumesAt {
            parts.append(String(localized: "Starts again at \(EVETime.time(resumesAt)), \(EVETime.relative(resumesAt, now: now))."))
        } else {
            parts.append(colony.horizonIsProgramEnd
                ? String(localized: "It does not start again before program end.")
                : String(localized: "It does not start again in the next 24 hours."))
        }
        return parts.joined(separator: " ")
    }

    // MARK: Schematic

    private static let columnWidth: CGFloat = 52
    private static let bufferWidth: CGFloat = 96

    private var schematic: some View {
        HUDListSection {
            HStack(spacing: 6) {
                Spacer(minLength: 0)
                column(Text("Cycle"))
                column(Text("Hour"))
                column(Text("Buffer"), width: Self.bufferWidth)
            }
            .font(.hudMicro)
            .tracking(1.5)
            .textCase(.uppercase)
            .foregroundStyle(Color.hudInkMuted)
            .hudRow(HUDRowStyle(minHeight: 0, verticalPadding: 8))

            ForEach(factory.inputs, id: \.commodity) { input in
                inputRow(input)
            }
            if let output = factory.output {
                let perHour = factory.cycleTime > 0 ? Double(output.quantity) * 3600 / factory.cycleTime : 0
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(verbatim: "→ \(output.commodity.name)")
                        .font(HUDFont.display(15, weight: .semibold, relativeTo: .body))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    column(Text(verbatim: PlanetaryFormat.quantity(output.quantity)))
                    column(Text(verbatim: PlanetaryFormat.number(perHour)))
                    column(Text(verbatim: "\(PlanetaryFormat.tier(output.commodity.tier)) · \(PlanetaryFormat.unitVolume(output.commodity.volume))")
                        .font(.hudMicro).foregroundStyle(Color.hudInkMuted), width: Self.bufferWidth)
                }
                .font(.hudCaption)
                .foregroundStyle(Color.hudAccent)
                .hudRow(HUDRowStyle(minHeight: 0, verticalPadding: 12))
            }
        } header: {
            HUDSectionHeader(Text("Schematic")) {
                Text("\(PlanetaryFormat.cycle(factory.cycleTime)) cycle")
            }
        }
    }

    private func column(_ text: Text, width: CGFloat = columnWidth) -> some View {
        text
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .frame(width: width, alignment: .trailing)
    }

    private func inputRow(_ input: FactoryDetail.Input) -> some View {
        let isShort = factory.waitingFor.contains(input.commodity)
        let caption: String
        if isShort {
            caption = input.inStorage == 0
                ? String(localized: "In · none in storage")
                : String(localized: "In · only \(PlanetaryFormat.quantity(input.inStorage)) in storage")
        } else {
            caption = String(localized: "In · \(PlanetaryFormat.quantity(input.inStorage)) ready in storage")
        }
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(verbatim: input.commodity.name)
                    .font(HUDFont.display(15, weight: .semibold, relativeTo: .body))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                column(Text(verbatim: PlanetaryFormat.quantity(input.perCycle)))
                column(Text(verbatim: PlanetaryFormat.number(input.perHour)).foregroundStyle(Color.hudInkBodyMuted))
                column(Text(verbatim: "\(PlanetaryFormat.quantity(input.buffered)) / \(PlanetaryFormat.quantity(input.perCycle))")
                    .foregroundStyle(isShort ? Color.hudWarn : Color.hudInk), width: Self.bufferWidth)
            }
            .font(.hudCaption)
            if isShort && input.buffered > 0 && input.perCycle > 0 {
                HUDResourceBar(fraction: Double(input.buffered) / Double(input.perCycle), color: .hudWarn)
            }
            Text(verbatim: caption)
                .font(.hudMicro)
                .textCase(.uppercase)
                .foregroundStyle(isShort ? Color.hudWarn : Color.hudInkMuted)
        }
        .hudRow(HUDRowStyle(minHeight: 0, verticalPadding: 10))
    }

    // MARK: Activity

    private var activity: some View {
        let spans = factory.activity.map { HUDActivityStrip.Span(start: $0.start, end: $0.end, isActive: $0.isRunning) }
        let start = colony.now, end = colony.horizon
        let running = factory.utilizationToEnd
        let limited = colony.issues.first { issue in
            if case let .outputLimited(pin, _, _, _, _) = issue { pin == facility.id } else { false }
        }
        return HUDListSection {
            VStack(alignment: .leading, spacing: 8) {
                HUDActivityStrip(spans: spans, start: start, end: end, marks: marks(start: start, end: end))
                HUDChartLegend(items: [
                    .init(id: 0, swatch: .block(.hudAccent), text: Text("Running \(FitStatFormat.percent(running))")),
                    .init(id: 1, swatch: .hatch, text: Text("Waiting for input \(FitStatFormat.percent(max(0, 1 - running)))")),
                ])
            }
            .hudRow(HUDRowStyle(minHeight: 0, verticalPadding: 14))

            HUDReadoutRow(Text("Made since \(EVETime.monthDayTime(colony.lastUpdate))"),
                          value: PlanetaryFormat.quantity(factory.madeSinceUpdate))
            HUDReadoutRow(Text(verbatim: colony.horizonIsProgramEnd ? String(localized: "By program end") : String(localized: "Next 24 h"))) {
                Text("\(PlanetaryFormat.gain(factory.madeToEnd)) · \(PlanetaryFormat.quantity(factory.madeSinceUpdate + factory.madeToEnd)) in all")
                    .foregroundStyle(Color.hudAccent)
            }
            HUDReadoutRow(Text("Average"),
                          value: String(localized: "\(PlanetaryFormat.rate(factory.averagePerHour)) of \(PlanetaryFormat.rate(factory.nominalPerHour))"))
            HUDReadoutRow(Text("Busy"),
                          value: String(localized: "\(FitStatFormat.percent(factory.utilizationSinceUpdate)) so far · \(FitStatFormat.percent(factory.utilizationDay)) next 24 h"))
            HUDReadoutRow("Wasted") {
                Text(verbatim: PlanetaryFormat.quantity(factory.wastedToEnd))
                    .foregroundStyle(factory.wastedToEnd > 0 ? Color.hudWarn : Color.hudOk)
            }
            if case let .outputLimited(_, _, waitingFor, limit, share)? = limited {
                let sentence = limit != waitingFor
                    ? String(localized: "Waits for \(waitingFor.name): their factory gets too few \(limit.name).")
                    : String(localized: "Waits for \(waitingFor.name) \(FitStatFormat.percent(share)) of the remaining time.")
                PlanetaryCardNote(text: Text(verbatim: sentence), color: .hudWarnNoteInk,
                                  route: .chain(planetID: colony.id))
            }
        } header: {
            HUDSectionHeader(Text(verbatim: colony.horizonPhrase)) {
                Text(verbatim: EVETime.duration(end.timeIntervalSince(now)))
            }
        }
    }

    /// `NOW`, each midnight (EVE time) along the way, `END`.
    private func marks(start: Date, end: Date) -> [HUDActivityStrip.Mark] {
        var marks = [HUDActivityStrip.Mark(date: start, label: Text("Now"))]
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        var day = calendar.startOfDay(for: start).addingTimeInterval(86_400)
        while day < end {
            marks.append(.init(date: day, label: Text(verbatim: String(EVETime.monthDayTime(day).prefix(5)))))
            day.addTimeInterval(86_400)
        }
        marks.append(.init(date: end, label: Text("End")))
        return marks
    }

    // MARK: Routes

    @ViewBuilder
    private var routes: some View {
        let incoming = grouped(facility.routesIn)
        let outgoing = grouped(facility.routesOut)
        HUDListSection {
            ForEach(incoming, id: \.pinID) { group in
                PlanetaryRouteRow(tag: Text("In"), title: Text(verbatim: colony.facilityName(group.pinID)),
                                  subtitle: Text(verbatim: group.commodities.map(\.name).joined(separator: " · ")),
                                  route: .facility(planetID: colony.id, pinID: group.pinID))
            }
            ForEach(outgoing, id: \.pinID) { group in
                PlanetaryRouteRow(tag: Text("Out"), title: Text(verbatim: colony.facilityName(group.pinID)),
                                  subtitle: Text(verbatim: outgoingSubtitle(group)),
                                  route: .facility(planetID: colony.id, pinID: group.pinID))
            }
        } header: {
            HUDSectionHeader(Text("Routes"))
        } footer: {
            HUDFootnote(colony.simulatedFootnote)
        }
    }

    private struct RouteGroup {
        var pinID: Int64
        var commodities: [PlanetaryCommodity]
    }

    private func grouped(_ routes: [RouteLine]) -> [RouteGroup] {
        var groups: [RouteGroup] = []
        for route in routes {
            if let index = groups.firstIndex(where: { $0.pinID == route.pinID }) {
                if !groups[index].commodities.contains(route.commodity) { groups[index].commodities.append(route.commodity) }
            } else {
                groups.append(RouteGroup(pinID: route.pinID, commodities: [route.commodity]))
            }
        }
        return groups
    }

    /// `BIOCELLS · 1 100 THERE NOW · 8%`: what lies at the other end, if it is a storage.
    private func outgoingSubtitle(_ group: RouteGroup) -> String {
        var parts = [group.commodities.map(\.name).joined(separator: ", ")]
        if let destination = colony.facility(pinID: group.pinID), case let .storage(storage) = destination.role {
            let there = storage.contents.filter { group.commodities.contains($0.commodity) }.reduce(0) { $0 + $1.quantity }
            parts.append(String(localized: "\(PlanetaryFormat.quantity(there)) there now"))
            if storage.capacity > 0 {
                parts.append(FitStatFormat.percent(storage.fillNow))
            }
        }
        return parts.joined(separator: " · ")
    }
}

#if DEBUG
#Preview("Factory") {
    let model = PlanetaryModel.preview()
    let colony = model.report!.colonies[0]
    let pin = colony.facilities.first { $0.kind == .advancedIndustry }?.id ?? colony.facilities[0].id
    NavigationStack {
        PlanetaryFacilityView(model: model, planetID: colony.id, pinID: pin)
    }
}

#Preview("Factory · idle") {
    let model = PlanetaryModel.preview()
    let colony = model.report!.colonies[0]
    let pin = colony.facilities.first { $0.kind == .basicIndustry }?.id ?? colony.facilities[0].id
    NavigationStack {
        PlanetaryFacilityView(model: model, planetID: colony.id, pinID: pin)
    }
}
#endif
