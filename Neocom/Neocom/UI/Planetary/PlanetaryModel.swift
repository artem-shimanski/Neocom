import Foundation
import Observation
import SDEKit
import SwiftUI

/// What the Planetary Interaction screens share: the character's `PlanetsSheet` and the report
/// simulated from its snapshot.
///
/// One per section, created by the colonies list and handed to every screen pushed from it, so
/// the colony, its chain and its facilities all read the same simulation and a refresh lands on
/// all of them at once. The report is rebuilt off the main actor when the snapshot changes, and
/// again once it is `resimulateInterval` old — a storage fills and a factory runs dry while the
/// screen is open. Between rebuilds the screens only move their clock (`TimelineView`), so the
/// countdowns tick every minute without simulating anything.
@Observable
@MainActor
final class PlanetaryModel {
    static let resimulateInterval: TimeInterval = 300

    let sheet: PlanetsSheet
    let database: SDEDatabase?

    private(set) var report: PlanetaryReport?
    private(set) var reportError: (any Error)?

    @ObservationIgnored private var builtRevision: Int?
    @ObservationIgnored private var building: Task<Void, Never>?
    /// A preview model schedules nothing.
    @ObservationIgnored private var isPreview = false

    init(sheet: PlanetsSheet, database: SDEDatabase?) {
        self.sheet = sheet
        self.database = database
    }

    /// What to say when there is no report to show: a failed simulation, or a fetch that failed
    /// with nothing cached.
    var failure: (any Error)? {
        if let reportError { return reportError }
        if report == nil, sheet.snapshot.value == nil, case let .failed(error) = sheet.snapshot.state { return error }
        return nil
    }

    /// Keeps `report` current for as long as the calling task runs: every screen of the section
    /// runs it from its own `.task`, since a screen covered by a pushed one has its task
    /// cancelled. Two screens running it at once share one rebuild.
    func keepCurrent() async {
        while !Task.isCancelled {
            await rebuildIfNeeded()
            let age = report.map { Date.now.timeIntervalSince($0.now) } ?? 0
            try? await Task.sleep(for: .seconds(max(5, Self.resimulateInterval - age)))
        }
    }

    private func rebuildIfNeeded() async {
        if let building {
            await building.value
        }
        guard let colonies = sheet.snapshot.value else { return }
        let revision = sheet.snapshot.revision
        if builtRevision == revision, let report,
           Date.now.timeIntervalSince(report.now) < Self.resimulateInterval {
            return
        }
        let task = Task {
            do {
                let made = try await PlanetaryReport.make(colonies: colonies, database: database)
                report = made
                reportError = nil
                // Every new report is a new schedule: what changed in it, and what the clock
                // moved past.
                PlanetaryNotifications.reschedule(characterID: sheet.characterID, report: made)
            } catch {
                reportError = error
            }
            builtRevision = revision
        }
        building = task
        await task.value
        building = nil
    }

    /// Reschedules from the report at hand, for a change of settings on the notifications screen.
    func rescheduleNotifications() {
        guard let report, !isPreview else { return }
        PlanetaryNotifications.reschedule(characterID: sheet.characterID, report: report)
    }

    #if DEBUG
    /// A model over a ready report, for previews: nothing is fetched or simulated.
    static func preview(_ report: PlanetaryReport = .fixture()) -> PlanetaryModel {
        let model = PlanetaryModel(sheet: PlanetsSheet(characterID: 0, client: ESIService.publicClient),
                                   database: nil)
        model.report = report
        model.builtRevision = Int.max
        model.isPreview = true
        return model
    }
    #endif
}

/// Every screen the section pushes, keyed on plain ids so a route survives a rebuilt report.
enum PlanetaryRoute: Hashable {
    case colony(planetID: Int64)
    case chain(planetID: Int64)
    /// A facility of a colony: extractor, factory or storage screen.
    case facility(planetID: Int64, pinID: Int64)
    /// The notification schedule.
    case notifications

    @ViewBuilder
    func destination(model: PlanetaryModel) -> some View {
        switch self {
        case let .colony(planetID):
            PlanetaryColonyView(model: model, planetID: planetID)
        case let .chain(planetID):
            PlanetaryChainView(model: model, planetID: planetID)
        case let .facility(planetID, pinID):
            PlanetaryFacilityView(model: model, planetID: planetID, pinID: pinID)
        case .notifications:
            PlanetaryNotificationsView(model: model)
        }
    }
}

extension View {
    /// The refresh every screen of the section takes: fetch if stale, keep the report current,
    /// pull to refresh.
    func planetaryRefresh(_ model: PlanetaryModel) -> some View {
        self
            .task { await model.sheet.ensureFresh() }
            .task(id: model.sheet.snapshot.revision) { await model.keepCurrent() }
            .refreshableCommand { await model.sheet.refresh() }
    }

    /// The bell every screen of the section has in its toolbar.
    func planetaryNotificationsButton() -> some View {
        toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink(value: PlanetaryRoute.notifications) {
                    Label("Notifications", systemImage: "bell")
                }
            }
        }
    }
}

/// The three states a screen of the section can be in before it has its colony: no report yet,
/// a failure, or the report.
struct PlanetaryReportContent<Content: View>: View {
    let model: PlanetaryModel
    @ViewBuilder var content: (PlanetaryReport) -> Content

    var body: some View {
        Group {
            if let report = model.report {
                content(report)
            } else if let error = model.failure {
                ContentUnavailableView {
                    Label("Colonies Unavailable", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(error.localizedDescription)
                } actions: {
                    Button("Retry") {
                        Task { await model.sheet.refresh() }
                    }
                }
            } else {
                ProgressView()
                    .controlSize(.large)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .planetaryRefresh(model)
    }
}
