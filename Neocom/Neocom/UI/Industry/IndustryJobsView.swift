import BusinessKit
import LiteRowUI
import SDEKit
import SwiftUI

/// The Industry section: the character's jobs (ready, running, paused) and, on request, those
/// completed in the last 90 days. A job's state is derived from the clock
/// (`IndustryJob.phase(at:)`), so it turns ready at its end date rather than on the next fetch.
struct IndustryJobsView: View {
    var body: some View {
        SDESectionView { database in
            IndustryJobsBody(database: database)
        }
        .hudScreen()
        .navigationTitle("Industry")
        .navigationBarTitleDisplayMode(.inline)
    }
}

enum IndustryJobRoute: Hashable {
    case job(Int64)
}

private struct IndustryJobsBody: View {
    let database: SDEDatabase

    @Environment(AccountStore.self) private var accounts

    var body: some View {
        if let sheet = accounts.currentIndustry {
            IndustryJobsScreen(sheet: sheet)
                // Another character gets its own screen.
                .id(ObjectIdentifier(sheet))
                .navigationDestination(for: IndustryJobRoute.self) { route in
                    switch route {
                    case let .job(id):
                        IndustryJobView(sheet: sheet, assets: accounts.currentAssets, jobID: id)
                            .liteDatabase(database.database)
                    }
                }
        }
    }
}

private struct IndustryJobsScreen: View {
    let sheet: IndustrySheet

    @Environment(AccountStore.self) private var accounts

    var body: some View {
        Group {
            if sheet.isMissingScope {
                HUDList {
                    Section {
                        HUDGrantAccessPanel(title: Text("No Industry Access"),
                                            message: Text("Your industry jobs need one more permission. Sign in to EVE again and allow Neocom to read your industry jobs."))
                            .hudBareRow()
                    }
                }
            } else if let value = sheet.value {
                let jobs = value.jobs
                IndustryContextReader(data: value, jobs: jobs, characterID: sheet.characterID,
                                      assetNames: accounts.currentAssets?.value?.names ?? [:]) { context in
                    // Progress is counted against the clock; EVE resends jobs every five minutes.
                    TimelineView(.periodic(from: .now, by: 15)) { clock in
                        IndustryJobsList(context: context, fetchedAt: sheet.fetchedAt,
                                         failure: sheet.state.error, isLoading: sheet.state.isLoading,
                                         now: clock.date)
                    }
                }
            } else if case let .failed(error) = sheet.state {
                HUDList {
                    Section {
                        HUDEmptyPanel(title: Text("Industry Unavailable"), message: Text(error.localizedDescription)) {
                            Button("Retry") {
                                Task { await sheet.refresh() }
                            }
                            .hudProminentButton()
                        }
                        .hudBareRow()
                    }
                }
            } else {
                ProgressView()
                    .controlSize(.large)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task { await sheet.ensureFresh() }
        .refreshableCommand { await sheet.refresh() }
    }
}

/// The list at the moment `now`.
private struct IndustryJobsList: View {
    let context: IndustryContext
    let fetchedAt: Date?
    let failure: (any Error)?
    let isLoading: Bool
    let now: Date

    @AppStorage("industry.showsCompletedJobs") private var showsCompleted = true

    var body: some View {
        let jobs = context.data.jobs
        let ready = jobs.filter { $0.phase(at: now) == .ready }.sorted { $0.endDate < $1.endDate }
        let active = jobs.activeSortedByEnd(at: now)
        let paused = jobs.filter { $0.phase(at: now) == .paused }.sorted { $0.endDate < $1.endDate }
        let completed = jobs.completedLatestFirst(at: now)
        let hasRunning = !(ready.isEmpty && active.isEmpty && paused.isEmpty)

        HUDList {
            if !hasRunning && completed.isEmpty {
                Section {
                    HUDEmptyPanel(title: Text("No Industry Jobs"),
                                  message: Text("This character has no industry jobs running, and none finished in the last 90 days."))
                        .hudBareRow()
                }
            } else {
                summary(jobs)
            }

            if !ready.isEmpty {
                group(Text("Ready to Deliver · \(ready.count)"), trailing: nil, jobs: ready,
                      note: readyNote(ready), style: .default, noteColor: .hudInkMuted)
            }
            if !active.isEmpty {
                group(Text("Active · \(active.count)"), trailing: Text("Time Left"), jobs: active,
                      note: nil, style: .default, noteColor: .hudInkMuted)
            }
            if !paused.isEmpty {
                group(Text("Paused · \(paused.count)"), trailing: nil, jobs: paused,
                      note: pausedNote(paused), style: HUDRowStyle(border: .hudWarnLine),
                      noteColor: .hudWarnNoteInk)
            }

            if hasRunning || !completed.isEmpty {
                Section {
                    Toggle(isOn: $showsCompleted) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Completed jobs")
                                .font(.body)
                            Text("Delivered, cancelled, reverted · 90 days")
                                .font(.hudLabel)
                                .textCase(.uppercase)
                                .foregroundStyle(Color.hudInkMuted)
                        }
                    }
                    .hudRow()
                }
            }

            if showsCompleted && !completed.isEmpty {
                HUDListSection {
                    ForEach(completed) { job in
                        NavigationLink(value: IndustryJobRoute.job(job.id)) {
                            IndustryCompletedRow(context: context, job: job, now: now)
                        }
                        .hudRowButton()
                        .hudTypeContextMenu(typeID: context.iconType(of: job), name: context.title(of: job))
                    }
                } header: {
                    HUDSectionHeader(Text("Completed · \(completed.count)"))
                }
            }

            if hasRunning || !completed.isEmpty {
                HUDListSection {
                    IndustryLegend()
                        .hudRow()
                } header: {
                    HUDSectionHeader(Text("Activities"))
                } footer: {
                    HUDFootnote("EVE sends jobs every 5 minutes; progress is counted here against the clock. Deliver, pause or cancel a job in the EVE client.")
                }
            }
        }
    }

    // MARK: Pieces

    @ViewBuilder
    private func summary(_ jobs: [IndustryJob]) -> some View {
        let summary = IndustrySummary(jobs, now: now)
        Section {
            HUDPanel {
                HUDStatStrip(items: [
                    .init(id: 0, label: Text("Ready"), value: Text(verbatim: "\(summary.readyCount)"),
                          color: summary.readyCount > 0 ? .hudOk : .hudInk),
                    .init(id: 1, label: Text(String(localized: "industry.jobs.active", defaultValue: "Active", comment: "An industry job that is running; also the count of such jobs")), value: Text(verbatim: "\(summary.activeCount)")),
                    .init(id: 2, label: Text("Paused"), value: Text(verbatim: "\(summary.pausedCount)"),
                          color: summary.pausedCount > 0 ? .hudWarn : .hudInk),
                    .init(id: 3, label: Text(String(localized: "industry.jobs.next", defaultValue: "Next", comment: "Time until the nearest job completes")),
                          value: Text(verbatim: summary.nextCompletion.map { EVETime.duration($0.timeIntervalSince(now)) } ?? "—")),
                ])
            }
            .padding(.bottom, HUDMetrics.headerSpacing)
            .hudBareRow()
            freshness
                .hudBareRow()
        }
    }

    private var freshness: some View {
        HUDFreshnessChip(fetchedAt: fetchedAt, now: now, isLoading: isLoading, error: failure)
    }

    private func group(_ title: Text, trailing: Text?, jobs: [IndustryJob], note: String?,
                       style: HUDRowStyle, noteColor: Color) -> some View {
        HUDListSection {
            ForEach(jobs) { job in
                NavigationLink(value: IndustryJobRoute.job(job.id)) {
                    IndustryJobRow(context: context, job: job, now: now, style: style)
                }
                .hudRowButton(style)
                .hudTypeContextMenu(typeID: context.iconType(of: job), name: context.title(of: job))
            }
            if let note {
                Text(verbatim: note)
                    .font(.hudCaption)
                    .lineSpacing(3)
                    .foregroundStyle(noteColor)
                    .hudRow(HUDRowStyle(border: style.border, minHeight: 0, verticalPadding: 10))
            }
        } header: {
            if let trailing {
                HUDSectionHeader(title) { trailing }
            } else {
                HUDSectionHeader(title)
            }
        }
    }

    private func readyNote(_ ready: [IndustryJob]) -> String {
        let places = Set(ready.map { context.facilityName(of: $0) })
        if places.count == 1, let place = places.first {
            return String(localized: "Deliver at \(place) in the EVE client.")
        }
        return String(localized: "Deliver in the EVE client, at the facility each job ran in.")
    }

    private func pausedNote(_ paused: [IndustryJob]) -> String {
        if paused.count == 1, let job = paused.first {
            let when = job.pauseDate.map { " " + EVETime.dateTime($0) } ?? ""
            return String(localized: "\(context.facilityName(of: job)) went offline\(when). The job resumes by itself when the facility is back online.")
        }
        return String(localized: "These facilities went offline. The jobs resume by themselves when the facilities are back online.")
    }
}

// MARK: - Rows

/// A job that is ready, running or paused: what it makes, where, and how far along it is.
private struct IndustryJobRow: View {
    let context: IndustryContext
    let job: IndustryJob
    let now: Date
    let style: HUDRowStyle

    var body: some View {
        let phase = job.phase(at: now)
        HStack(alignment: .top, spacing: 12) {
            HUDItemIcon(typeID: IndustryIDs.type(context.iconType(of: job)), size: 36)
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(verbatim: context.title(of: job))
                        .font(.hudBody)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(verbatim: context.outputText(of: job))
                        .font(.hudReadout.weight(.semibold))
                        .lineLimit(1)
                }
                HStack(spacing: 6) {
                    Image(systemName: job.activity.symbol)
                        .font(.system(size: 11))
                    Text(verbatim: context.meta(of: job))
                        .textCase(.uppercase)
                        .lineLimit(1)
                }
                .font(.hudLabel)
                .foregroundStyle(Color.hudInkMuted)
                HStack(spacing: 10) {
                    HUDJobProgressBar(fraction: job.progress(at: now), color: phase.bar, isPaused: phase == .paused)
                    state(phase)
                }
                .padding(.top, 1)
            }
        }
        .multilineTextAlignment(.leading)
        .hudRow(style)
    }

    @ViewBuilder
    private func state(_ phase: IndustryJobPhase) -> some View {
        switch phase {
        case .ready:
            HUDStatusChip(text: Text("Ready"), color: .hudOk, mark: .dot)
        case .paused:
            HUDStatusChip(text: Text("\(EVETime.duration(job.timeLeft(at: now))) left"), color: .hudWarn,
                          mark: .symbol("pause.fill"))
        default:
            HUDStatusChip(text: Text(verbatim: EVETime.duration(job.timeLeft(at: now))), color: phase.ink)
                .monospacedDigit()
        }
    }
}

/// A job that is over: how it ended and when.
private struct IndustryCompletedRow: View {
    let context: IndustryContext
    let job: IndustryJob
    let now: Date

    var body: some View {
        let phase = job.phase(at: now)
        HStack(alignment: .top, spacing: 12) {
            HUDItemIcon(typeID: IndustryIDs.type(context.iconType(of: job)), size: 36)
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(verbatim: context.title(of: job))
                        .font(.hudBody)
                        .foregroundStyle(phase == .delivered ? Color.hudInk : Color.hudInkBodyMuted)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    HUDStatusChip(text: Text(verbatim: phase.title), color: phase.ink, mark: .dot)
                        .lineLimit(1)
                }
                HStack(spacing: 6) {
                    Image(systemName: job.activity.symbol)
                        .font(.system(size: 11))
                    Text(verbatim: context.completedMeta(of: job))
                        .textCase(.uppercase)
                        .lineLimit(1)
                }
                Text(verbatim: context.closedText(of: job, phase: phase))
                    .textCase(.uppercase)
                    .lineLimit(2)
            }
            .font(.hudLabel)
            .foregroundStyle(Color.hudInkMuted)
        }
        .multilineTextAlignment(.leading)
        .hudRow()
    }
}

private struct IndustryLegend: View {
    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)],
                  alignment: .leading, spacing: 12) {
            ForEach(IndustryActivity.legend, id: \.self) { activity in
                HStack(spacing: 10) {
                    Image(systemName: activity.symbol)
                        .font(.system(size: 14))
                        .foregroundStyle(Color.hudInkMuted)
                        .frame(width: 18)
                    Text(verbatim: activity.title)
                        .font(.hudLabel)
                        .tracking(1)
                        .textCase(.uppercase)
                        .foregroundStyle(Color.hudInkBodyMuted)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

enum IndustryIDs {
    static func type(_ id: Int64) -> TypeID { TypeID(rawValue: UInt32(clamping: id)) }
}
