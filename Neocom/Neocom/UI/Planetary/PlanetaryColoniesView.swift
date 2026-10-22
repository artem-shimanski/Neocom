import SDEKit
import SwiftUI

/// The Planetary Interaction section: the character's colonies, simulated from their last
/// update in game to now — the ones that need attention first, then the ones that run.
///
/// `PlanetsSheet` fetches, `PlanetaryModel` simulates; every screen pushed from here reads the
/// same model, through `PlanetaryRoute`.
struct PlanetaryColoniesView: View {
    var body: some View {
        SDESectionView { database in
            PlanetaryColoniesBody(database: database)
        }
        .hudScreen()
        .navigationTitle("Planetary Interaction")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct PlanetaryColoniesBody: View {
    let database: SDEDatabase

    @Environment(AccountStore.self) private var accounts

    var body: some View {
        if let sheet = accounts.currentPlanets {
            PlanetaryColoniesScreen(sheet: sheet, database: database)
                // Another character is another model, not this one refilled.
                .id(ObjectIdentifier(sheet))
        }
    }
}

private struct PlanetaryColoniesScreen: View {
    @State private var model: PlanetaryModel

    init(sheet: PlanetsSheet, database: SDEDatabase) {
        _model = State(initialValue: PlanetaryModel(sheet: sheet, database: database))
    }

    var body: some View {
        PlanetaryReportContent(model: model) { report in
            TimelineView(.everyMinute) { context in
                PlanetaryColoniesList(report: report, now: context.date)
            }
        }
        .planetaryNotificationsButton()
        .navigationDestination(for: PlanetaryRoute.self) { route in
            route.destination(model: model)
        }
    }
}

/// The list itself, at the moment `now` (the clock of the screen, which ticks between the
/// report's rebuilds).
struct PlanetaryColoniesList: View {
    let report: PlanetaryReport
    let now: Date

    var body: some View {
        let attention = report.colonies.filter(\.overview.needsAttention)
        let running = report.colonies.filter { !$0.overview.needsAttention }
        HUDList {
            if report.colonies.isEmpty && report.failures.isEmpty {
                Section {
                    HUDEmptyPanel(title: Text("No Colonies"),
                                  message: Text("This character has no planetary colonies."))
                        .hudBareRow()
                }
            }

            if !attention.isEmpty || !report.failures.isEmpty {
                Section {
                    ForEach(attention) { colony in
                        link(colony, isLast: colony.id == attention.last?.id && report.failures.isEmpty)
                    }
                    ForEach(report.failures) { failure in
                        PlanetaryFailureCard(failure: failure)
                            .padding(.bottom, failure.id == report.failures.last?.id ? 0 : HUDMetrics.headerSpacing)
                            .hudBareRow()
                    }
                } header: {
                    HUDSectionHeader(Text("Needs Attention · \(attention.count + report.failures.count)"))
                        .hudListHeader()
                }
            }

            if !running.isEmpty {
                Section {
                    ForEach(running) { colony in
                        link(colony, isLast: colony.id == running.last?.id)
                    }
                } header: {
                    HUDSectionHeader(Text("Running · \(running.count)"))
                        .hudListHeader()
                }
            }

            if !report.colonies.isEmpty || !report.failures.isEmpty {
                Section {
                    updates.hudBareRow()
                }
            }
        }
    }

    private func link(_ colony: ColonyDetail, isLast: Bool) -> some View {
        NavigationLink(value: PlanetaryRoute.colony(planetID: colony.id)) {
            PlanetaryColonyCard(colony: colony, now: now)
        }
        .buttonStyle(.hudTile)
        .padding(.bottom, isLast ? 0 : HUDMetrics.headerSpacing)
        .hudBareRow()
    }

    /// How fresh each colony is: the one thing the simulation cannot change.
    private var updates: some View {
        struct Line: Identifiable {
            var planet: PlanetInfo
            var lastUpdate: Date
            var id: Int64 { planet.planetID }
        }
        let lines = report.colonies.filter(\.overview.needsAttention).map { Line(planet: $0.planet, lastUpdate: $0.lastUpdate) }
            + report.failures.map { Line(planet: $0.planet, lastUpdate: $0.lastUpdate) }
            + report.colonies.filter { !$0.overview.needsAttention }.map { Line(planet: $0.planet, lastUpdate: $0.lastUpdate) }
        return VStack(alignment: .leading, spacing: 12) {
            HUDFootnote("EVE updates a colony only when you open it in the game client. Each colony is simulated from its last update to now; open it in game to refresh.")
            VStack(alignment: .leading, spacing: 6) {
                ForEach(lines) { line in
                    HStack {
                        Text(verbatim: line.planet.displayName.uppercased())
                        Spacer(minLength: 8)
                        Text("Updated \(EVETime.dateTime(line.lastUpdate))")
                            .textCase(.uppercase)
                    }
                }
            }
            .font(HUDFont.mono(11, weight: .regular, relativeTo: .caption))
            .foregroundStyle(Color.hudInkFaint)
            .padding(.horizontal, HUDMetrics.headerFaceInset)
        }
    }
}

/// One colony of the list: the planet, what it makes, and the one thing to know about it.
private struct PlanetaryColonyCard: View {
    let colony: ColonyDetail
    let now: Date

    var body: some View {
        let overview = colony.overview
        let headline = overview.headline.map { colony.describe($0, now: now) }
        let others = overview.otherIssues.map { colony.describe($0, now: now) }
        HUDPanel(tone: overview.needsAttention ? .warn : .normal) {
            HStack(alignment: .center, spacing: 12) {
                if let typeID = overview.planet.kind.typeID {
                    HUDItemIcon(typeID: typeID, size: 48)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(verbatim: overview.planet.displayName)
                        .font(HUDFont.display(18, weight: .bold, relativeTo: .headline))
                        .tracking(0.5)
                        .textCase(.uppercase)
                        .lineLimit(1)
                    meta
                        .font(HUDFont.mono(11, weight: .regular, relativeTo: .caption))
                        .foregroundStyle(Color.hudInkMuted)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                overview.status.chip
                    .frame(maxHeight: .infinity, alignment: .top)
                    .padding(.top, 2)
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, HUDMetrics.gutter)
            .padding(.top, 14)
            .padding(.bottom, 12)

            if !overview.products.isEmpty {
                products(overview.products)
                    .padding(.horizontal, HUDMetrics.gutter)
                    .padding(.bottom, 12)
            }

            if let headline {
                HUDPanelRule()
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(verbatim: headline.label)
                        .tracking(1)
                        .textCase(.uppercase)
                        .foregroundStyle(headline.isWarning ? Color.hudWarn : Color.hudInkMuted)
                        .lineLimit(1)
                        .layoutPriority(1)
                    HUDLeader().frame(minWidth: 12)
                    Text(verbatim: headline.when)
                        .foregroundStyle(headline.isWarning ? Color.hudWarn : Color.hudInk)
                        .lineLimit(1)
                        .layoutPriority(2)
                }
                .font(.hudReadout)
                .padding(.horizontal, HUDMetrics.gutter)
                .padding(.vertical, 11)

                if !others.isEmpty {
                    Text(verbatim: "+\(others.count) · " + others.map(\.label).joined(separator: ", "))
                        .font(.hudReadout)
                        .tracking(1)
                        .textCase(.uppercase)
                        .foregroundStyle(Color.hudInkMuted)
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, HUDMetrics.gutter)
                        .padding(.bottom, 11)
                }

                if headline.isWarning, let advice = headline.advice {
                    HUDWarnNote(verbatim: advice)
                }
            }
        }
        .multilineTextAlignment(.leading)
        .foregroundStyle(Color.hudInk)
    }

    /// `BARREN · CC 4 · OSOGGUR 0.5`.
    private var meta: Text {
        let planet = colony.planet
        var text = Text("\(Text(verbatim: "\(planet.kind.title.uppercased()) · "))\(Text("CC \(planet.commandCenterLevel)"))")
        if let system = planet.systemText {
            text = Text("\(text)\(Text(verbatim: " · "))\(system)")
        }
        return text
    }

    private func products(_ products: [ProductRate]) -> some View {
        let tier = products.map(\.commodity.tier).max() ?? 0
        let rate = products.reduce(0) { $0 + $1.perHour }
        return HStack(spacing: 10) {
            HUDItemIcon(typeID: products[0].commodity.typeID, size: 28)
            Text(verbatim: products.map(\.commodity.name).joined(separator: ", "))
                .font(HUDFont.display(15, weight: .semibold, relativeTo: .body))
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(verbatim: "\(PlanetaryFormat.tier(tier)) · \(PlanetaryFormat.rate(rate))")
                .font(HUDFont.mono(11, weight: .regular, relativeTo: .caption))
                .textCase(.uppercase)
                .foregroundStyle(Color.hudInkMuted)
                .lineLimit(1)
        }
    }
}

/// A colony the model could not build: named, with the reason, and nothing to open.
private struct PlanetaryFailureCard: View {
    let failure: ColonyFailure

    var body: some View {
        HUDPanel(tone: .warn) {
            HStack(spacing: 12) {
                if let typeID = failure.planet.kind.typeID {
                    HUDItemIcon(typeID: typeID, size: 48)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(verbatim: failure.planet.displayName)
                        .font(HUDFont.display(18, weight: .bold, relativeTo: .headline))
                        .tracking(0.5)
                        .textCase(.uppercase)
                    Text("Could not be simulated")
                        .font(HUDFont.mono(11, weight: .regular, relativeTo: .caption))
                        .textCase(.uppercase)
                        .foregroundStyle(Color.hudInkMuted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, HUDMetrics.gutter)
            .padding(.vertical, 14)
            HUDWarnNote(verbatim: failure.reason)
        }
    }
}

#if DEBUG
#Preview("Colonies") {
    NavigationStack {
        PlanetaryColoniesList(report: .fixture(), now: PlanetaryFixture.lastUpdate.addingTimeInterval(55 * 3600))
            .navigationTitle("Planetary Interaction")
            .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview("Colonies · programs over") {
    NavigationStack {
        PlanetaryColoniesList(report: .fixture(simulatedFor: 6 * 86_400),
                              now: PlanetaryFixture.lastUpdate.addingTimeInterval(6 * 86_400))
            .navigationTitle("Planetary Interaction")
            .navigationBarTitleDisplayMode(.inline)
    }
}
#endif
