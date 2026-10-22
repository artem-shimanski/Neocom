import SDEKit
import SwiftUI

/// One facility of a colony — extractor, factory, storage, launchpad or command center —
/// pushed by `PlanetaryRoute.facility`. Each kind has a screen of its own; this one finds the
/// facility in the report and keeps the clock.
struct PlanetaryFacilityView: View {
    let model: PlanetaryModel
    let planetID: Int64
    let pinID: Int64

    /// Moved forward by the task below, when the next change of what the screen shows is due.
    /// Not a `TimelineView`: one around the screen, with the cycle bar's own per-second timeline
    /// inside, makes SwiftUI re-render every frame.
    @State private var clock = Date.now

    var body: some View {
        PlanetaryReportContent(model: model) { report in
            if let colony = report.colony(planetID: planetID), let facility = colony.facility(pinID: pinID) {
                let now = max(clock, colony.now)
                Group {
                    switch facility.role {
                    case let .extractor(extractor):
                        PlanetaryExtractorContent(colony: colony, facility: facility, extractor: extractor, now: now)
                    case let .factory(factory):
                        PlanetaryFactoryContent(colony: colony, facility: facility, factory: factory, now: now)
                    case let .storage(storage):
                        PlanetaryStorageContent(colony: colony, facility: facility, storage: storage, now: now)
                    }
                }
                .task(id: facility.nextChange(after: now)) {
                    guard let date = facility.nextChange(after: now) else { return }
                    try? await Task.sleep(for: .seconds(max(0, date.timeIntervalSinceNow)))
                    if Task.isCancelled { return }
                    clock = max(.now, date)
                }
                .navigationTitle(facility.screenTitle)
            } else {
                ContentUnavailableView("No Facility", systemImage: "shippingbox",
                                       description: Text("The colony has no such facility any more."))
            }
        }
        .hudScreen()
        .navigationBarTitleDisplayMode(.inline)
        .planetaryNotificationsButton()
    }
}

extension FacilityDetail {
    /// The earliest moment after `now` at which what the screen shows changes by itself: the next
    /// extractor cycle (and program end), the end of the factory's cycle or its wait, the moment a
    /// storage fills. `nil` — nothing to wait for.
    func nextChange(after now: Date) -> Date? {
        var dates: [Date] = []
        switch role {
        case let .extractor(extractor):
            if let program = extractor.program, program.cycleTime > 0 {
                let elapsed = now.timeIntervalSince(program.installTime)
                let k = max(0, (elapsed / program.cycleTime).rounded(.down) + 1)
                dates.append(program.installTime.addingTimeInterval(k * program.cycleTime))
                dates.append(program.expiryTime)
            }
        case let .factory(factory):
            switch factory.state {
            case let .running(_, cycleEnd): dates.append(cycleEnd)
            case let .idle(_, resumesAt): if let resumesAt { dates.append(resumesAt) }
            case .notSetUp: break
            }
        case let .storage(storage):
            if let fullAt = storage.fullAt { dates.append(fullAt) }
        }
        return dates.filter { $0 > now }.min()
    }

    /// The navigation title: what kind of screen this is.
    var screenTitle: String {
        switch kind {
        case .extractor: String(localized: "Extractor")
        case .basicIndustry, .advancedIndustry, .highTechIndustry: String(localized: "Factory")
        case .storage: String(localized: "Storage")
        case .launchpad: String(localized: "Launchpad")
        case .commandCenter: String(localized: "Command Center")
        }
    }
}

// MARK: - Shared pieces of the facility screens

/// The panel that heads a facility screen: the icon, the name in caps, a caption under it and the
/// state on the right; whatever else the screen puts at its top goes under them.
struct PlanetaryFacilityHeader<Content: View>: View {
    var tone: HUDTone = .normal
    let typeID: TypeID
    let title: Text
    let subtitle: Text
    var chip: HUDStatusChip?
    @ViewBuilder var content: Content

    var body: some View {
        HUDPanel(tone: tone) {
            HStack(alignment: .center, spacing: 14) {
                HUDItemIcon(typeID: typeID, size: 48)
                VStack(alignment: .leading, spacing: 4) {
                    title
                        .font(HUDFont.display(20, weight: .bold, relativeTo: .title3))
                        .tracking(0.5)
                        .textCase(.uppercase)
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)
                    subtitle
                        .font(HUDFont.mono(11, weight: .regular, relativeTo: .caption))
                        .tracking(1)
                        .textCase(.uppercase)
                        .foregroundStyle(Color.hudInkMuted)
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if let chip {
                    chip.frame(maxHeight: .infinity, alignment: .top)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, HUDMetrics.gutter)
            .padding(.vertical, 14)
            content
        }
        .multilineTextAlignment(.leading)
    }
}

/// A row of a routes card: a mono tag (`IN`, `ROUTE`, `THEN`), the facility at the other end and
/// what goes along, and a chevron when it leads to that facility.
struct PlanetaryRouteRow: View {
    let tag: Text
    let title: Text
    let subtitle: Text
    var route: PlanetaryRoute?

    static let style = HUDRowStyle(minHeight: 56, verticalPadding: 12)

    var body: some View {
        if let route {
            NavigationLink(value: route) {
                label(showsChevron: true).hudRow(Self.style)
            }
            .hudRowButton(Self.style)
        } else {
            label(showsChevron: false).hudRow(Self.style)
        }
    }

    private func label(showsChevron: Bool) -> some View {
        HStack(spacing: 12) {
            tag
                .font(.hudMicro)
                .tracking(1)
                .textCase(.uppercase)
                .foregroundStyle(Color.hudInkMuted)
                .frame(width: 38, alignment: .leading)
            HUDRowTitle(title: title, subtitle: subtitle)
            Spacer(minLength: 8)
            if showsChevron {
                HUDChevron()
            }
        }
    }
}

/// A plain sentence as the last row of a card: what the figures above rest on, or what to do.
struct PlanetaryCardNote: View {
    let text: Text
    var color: Color = .hudInkMuted
    var route: PlanetaryRoute?

    private static let style = HUDRowStyle(minHeight: 0, verticalPadding: 10)

    var body: some View {
        if let route {
            NavigationLink(value: route) {
                HStack(spacing: 10) {
                    sentence
                    HUDChevron()
                }
                .hudRow(Self.style)
            }
            .hudRowButton(Self.style)
        } else {
            sentence.hudRow(Self.style)
        }
    }

    private var sentence: some View {
        text
            .font(HUDFont.mono(11, weight: .regular, relativeTo: .caption))
            .lineSpacing(3)
            .foregroundStyle(color)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension ColonyDetail {
    /// The footnote every facility screen ends with.
    var simulatedFootnote: Text {
        Text("Simulated from the last update, \(EVETime.dateTime(lastUpdate)). Open the colony in game to refresh.")
    }

    /// `to program end` or `next 24 h`, for a header's trailing slot or a sentence.
    var horizonPhrase: String {
        horizonIsProgramEnd ? String(localized: "To program end") : String(localized: "Next 24 h")
    }
}

extension PlanetaryFormat {
    /// `2 h`, `30 min`: a cycle length.
    static func cycle(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds / 60)
        if minutes >= 60 && minutes % 60 == 0 { return String(localized: "\(minutes / 60) h") }
        if minutes >= 60 { return EVETime.duration(seconds) }
        return String(localized: "\(minutes) min")
    }

    /// `0.005 m³`, `0.75 m³`: the volume of one unit.
    static func unitVolume(_ volume: Double) -> String {
        "\(volume.formatted(.number.precision(.significantDigits(1...3)))) m³"
    }

    /// `883 m³`, `15.7 m³`.
    static func cubicMetres(_ volume: Double) -> String {
        "\(volume.formatted(.number.precision(.fractionLength(volume < 100 ? 1 : 0)))) m³"
    }
}

#if DEBUG
#Preview("Facilities") {
    let model = PlanetaryModel.preview()
    let colony = model.report!.colonies[0]
    NavigationStack {
        HUDList {
            HUDListSection("Facilities") {
                ForEach(colony.facilities) { facility in
                    NavigationLink(value: PlanetaryRoute.facility(planetID: colony.id, pinID: facility.id)) {
                        Text(verbatim: "\(facility.kind.title) \(facility.name)").hudRow()
                    }
                    .hudRowButton()
                }
            }
        }
        .navigationDestination(for: PlanetaryRoute.self) { $0.destination(model: model) }
    }
}
#endif
