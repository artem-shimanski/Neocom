import BusinessKit
import SDEKit
import SwiftUI

/// One industry job: the blueprint, how far along it is against the clock, what it makes,
/// when, and where.
struct IndustryJobView: View {
    let sheet: IndustrySheet
    let assets: AssetsSheet?
    let jobID: Int64

    var body: some View {
        Group {
            if let value = sheet.value, let job = value.jobs.first(where: { $0.id == jobID }) {
                IndustryContextReader(data: value, jobs: [job], characterID: sheet.characterID,
                                      assetNames: assets?.value?.names ?? [:]) { context in
                    IndustryJobDetail(context: context, job: job)
                }
            } else {
                HUDList {
                    Section {
                        HUDEmptyPanel(title: Text("Job Not Found"),
                                      message: Text("This job is no longer in the list EVE sent. It may have been delivered long ago."))
                            .hudBareRow()
                    }
                }
            }
        }
        .hudScreen()
        .navigationBarTitleDisplayMode(.inline)
        .task { await sheet.ensureFresh() }
        .refreshableCommand { await sheet.refresh() }
    }
}

private struct IndustryJobDetail: View {
    let context: IndustryContext
    let job: IndustryJob

    var body: some View {
        let activity = job.activity
        HUDList {
            Section {
                TimelineView(.periodic(from: .now, by: 1)) { clock in
                    IndustryJobHero(context: context, job: job, now: clock.date)
                }
                .hudBareRow()
            }

            output(activity)
            timeline
            facility
            facts

            Section {
                HUDFootnote("Deliver, pause or cancel the job in the EVE client.")
                    .hudBareRow()
            }
        }
        .navigationTitle(navigationTitle)
        .navigationSubtitle(Text("Industry job"))
    }

    private var navigationTitle: String {
        context.typeName(job.blueprintTypeID)
            .replacingOccurrences(of: " Blueprint", with: "")
            .replacingOccurrences(of: " Reaction Formula", with: "")
    }

    // MARK: Output

    private func output(_ activity: IndustryActivity) -> some View {
        let productID = context.productType(of: job)
        return HUDListSection {
            NavigationLink(value: DatabaseRoute.type(IndustryIDs.type(productID))) {
                HStack(spacing: 12) {
                    HUDItemIcon(typeID: IndustryIDs.type(productID), size: 36)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: context.typeName(productID))
                            .font(.hudBody)
                        Text(verbatim: productSubtitle(productID))
                            .font(.hudLabel)
                            .textCase(.uppercase)
                            .foregroundStyle(Color.hudInkMuted)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Text(verbatim: productQuantity)
                        .font(.hudReadout.weight(.semibold))
                    HUDChevron()
                }
                .multilineTextAlignment(.leading)
                .hudRow()
            }
            .hudRowButton()

            HUDReadoutRow("Runs", value: job.runs.formatted())
            if let licensed = job.licensedRuns {
                HUDReadoutRow("Licensed runs", value: licensed.formatted())
            }
            if let probability = job.probability {
                HUDReadoutRow("Chance", value: String(localized: "\(IndustryFormat.percent(probability)) a run"))
            }
            if activity == .invention || activity == .manufacturing || activity == .reaction {
                HUDReadoutRow("Successful runs") {
                    successfulRuns
                }
            }
        } header: {
            HUDSectionHeader(Text(outputTitle(activity)))
        }
    }

    private func outputTitle(_ activity: IndustryActivity) -> String {
        switch activity {
        case .invention: String(localized: "Invents")
        case .copying: String(localized: "Copies")
        case .researchTime, .researchMaterial: String(localized: "Researches")
        default: String(localized: "Produces")
        }
    }

    private func productSubtitle(_ productID: Int64) -> String {
        let group = context.types[productID]?.groupName ?? ""
        switch job.activity {
        case .copying, .invention:
            if let licensed = job.licensedRuns {
                return [group, String(localized: "\(licensed) runs each")].filter { !$0.isEmpty }.joined(separator: " · ")
            }
            return group
        case .researchTime:
            return String(localized: "Time efficiency +\(job.runs) levels")
        case .researchMaterial:
            return String(localized: "Material efficiency +\(job.runs) levels")
        default:
            return group
        }
    }

    private var productQuantity: String {
        switch job.activity {
        case .manufacturing, .reaction:
            return "×\((context.units(of: job) ?? job.runs).formatted())"
        case .invention, .reverseEngineering:
            if let ok = job.successfulRuns { return "×\(ok)" }
            return String(localized: "Up to \(job.runs)")
        case .copying:
            return job.activity.count(job.runs).uppercased()
        case .researchTime, .researchMaterial:
            return String(localized: "\(job.runs) LV")
        case .unknown:
            return ""
        }
    }

    @ViewBuilder
    private var successfulRuns: some View {
        let phase = job.phase(at: .now)
        if let ok = job.successfulRuns {
            Text(verbatim: String(localized: "\(ok) of \(job.runs)"))
                .foregroundStyle(ok < job.runs ? Color.hudWarn : Color.hudInk)
        } else if phase == .delivered, job.activity == .manufacturing || job.activity == .reaction {
            Text(verbatim: String(localized: "\(job.runs) of \(job.runs)"))
        } else if phase == .cancelled || phase == .reverted {
            Text(verbatim: "—")
        } else {
            Text("After delivery")
        }
    }

    // MARK: Timeline, facility, facts

    private var timeline: some View {
        let phase = job.phase(at: .now)
        return HUDListSection {
            HUDReadoutRow("Started", value: EVETime.dateTime(job.startDate))
            if let pause = job.pauseDate {
                HUDReadoutRow("Paused") {
                    Text(verbatim: EVETime.dateTime(pause)).foregroundStyle(Color.hudWarn)
                }
            }
            HUDReadoutRow(job.endDate <= .now ? Text("Ended") : Text("Ends"), value: EVETime.dateTime(job.endDate))
            HUDReadoutRow("Duration",
                          value: "\(EVETime.duration(TimeInterval(job.duration))) · " + String(localized: "\(job.duration.formatted()) s", comment: "Seconds, abbreviated"))
            if phase.isCompleted {
                HUDReadoutRow(Text(verbatim: phase.title),
                              value: EVETime.dateTime(job.completedDate ?? job.endDate))
            }
        } header: {
            HUDSectionHeader(Text("Timeline"))
        }
    }

    private var facility: some View {
        HUDListSection {
            HUDPlaceBlock(name: context.facilityName(of: job), line: facilityLine)
                .hudRow()
            HUDReadoutRow("Blueprint from", value: context.place(job.blueprintLocationID, in: job))
            HUDReadoutRow("Output to", value: context.place(job.outputLocationID, in: job))
        } header: {
            HUDSectionHeader(Text("Facility"))
        }
    }

    /// `RENS 0.9 · HEIMATAR · NPC STATION`.
    private var facilityLine: Text {
        let system = context.system(of: job)
        return HUDPlaceBlock.line(systemName: system?.name, security: system?.securityStatus,
                                  details: [system?.regionName, context.facilityKind(of: job)])
            ?? Text(verbatim: String(localized: "Location unknown").uppercased())
    }

    private var facts: some View {
        HUDListSection {
            if let cost = job.cost {
                HUDReadoutRow("Cost", value: ISK.price(cost))
            }
            HUDReadoutRow("Installed by", value: context.pilotName(job.installerID))
            if let by = job.completedCharacterID {
                HUDReadoutRow(job.phase(at: .now) == .cancelled ? Text("Cancelled by") : Text("Delivered by"),
                              value: context.pilotName(by))
            }
            HUDReadoutRow("Job ID", value: String(job.id))
            HUDReadoutRow("Blueprint item ID", value: String(job.blueprintID))
            HUDReadoutRow("Facility · Station ID", value: "\(job.facilityID) · \(job.stationID)")
        } header: {
            HUDSectionHeader(Text("Job"))
        }
    }
}

/// The panel at the head of a job: activity and state, the blueprint, and the countdown or the
/// moment it closed, redrawn by the second.
private struct IndustryJobHero: View {
    let context: IndustryContext
    let job: IndustryJob
    let now: Date

    var body: some View {
        let phase = job.phase(at: now)
        let progress = job.progress(at: now)
        HUDPanel(tone: phase.tone) {
            HUDPanelHeader(title: Text("\(Image(systemName: job.activity.symbol)) \(job.activity.longTitle)")) {
                HUDStatusChip(text: Text(verbatim: phase.title), color: phase.ink,
                              mark: phase == .paused ? .symbol("pause.fill") : .dot)
            }

            HStack(spacing: 14) {
                HUDItemIcon(typeID: IndustryIDs.type(job.blueprintTypeID), size: 64)
                VStack(alignment: .leading, spacing: 6) {
                    Text(verbatim: context.typeName(job.blueprintTypeID))
                        .font(HUDFont.display(21, weight: .bold, relativeTo: .title3))
                        .tracking(0.5)
                        .textCase(.uppercase)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(verbatim: blueprintSubtitle)
                        .font(.hudCaption)
                        .textCase(.uppercase)
                        .foregroundStyle(Color.hudInkMuted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(HUDMetrics.gutter)

            VStack(spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(verbatim: big.label)
                        .font(.hudMicro)
                        .tracking(1.5)
                        .textCase(.uppercase)
                        .foregroundStyle(Color.hudInkMuted)
                    Spacer(minLength: 8)
                    Text(verbatim: big.value)
                        .font(HUDFont.mono(22, weight: .semibold, relativeTo: .title2))
                        .monospacedDigit()
                        .foregroundStyle(big.color)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                HUDJobProgressBar(fraction: progress, color: phase.bar, isPaused: phase == .paused, height: 8)
                HStack {
                    Text(verbatim: EVETime.monthDayTime(job.startDate))
                    Spacer()
                    Text(verbatim: progress.formatted(.percent.precision(.fractionLength(0))))
                    Spacer()
                    Text(verbatim: EVETime.monthDayTime(job.endDate))
                }
                .font(.hudLabel)
                .foregroundStyle(Color.hudInkMuted)
            }
            .padding(.horizontal, HUDMetrics.gutter)
            .padding(.bottom, HUDMetrics.gutter)

            note(phase)
        }
        .foregroundStyle(Color.hudInk)
    }

    private var blueprintSubtitle: String {
        if job.activity == .reaction { return String(localized: "Reaction formula") }
        return String(localized: "Blueprint · \(job.activity.count(job.runs))")
    }

    private var big: (label: String, value: String, color: Color) {
        let phase = job.phase(at: now)
        switch phase {
        case .active:
            return (String(localized: "Time left"), EVETime.duration(job.timeLeft(at: now)), .hudAccent)
        case .ready:
            return (String(localized: "Finished"), String(localized: "\(EVETime.duration(job.timeSinceEnd(at: now))) ago"), .hudOk)
        case .paused:
            return (String(localized: "Left when resumed"), EVETime.duration(job.timeLeft(at: now)), .hudWarn)
        case .delivered, .cancelled, .reverted, .unknown:
            return (phase.title, EVETime.monthDayTime(job.completedDate ?? job.endDate),
                    phase == .reverted ? .hudDanger : phase == .cancelled ? .hudInkBodyMuted : .hudInk)
        }
    }

    @ViewBuilder
    private func note(_ phase: IndustryJobPhase) -> some View {
        switch phase {
        case .ready:
            HUDWarnNote(verbatim: String(localized: "Ready to deliver. Deliver at \(context.facilityName(of: job)) in the EVE client; output goes to \(context.place(job.outputLocationID, in: job).lowercased())."))
                .colors(ink: .hudInkMuted, background: .clear)
        case .paused:
            let when = job.pauseDate.map { " " + EVETime.dateTime($0) } ?? ""
            HUDWarnNote(verbatim: String(localized: "\(context.facilityName(of: job)) went offline\(when). The job resumes by itself when the facility is back online."))
        case .reverted:
            HUDWarnNote(verbatim: String(localized: "The server rolled this job back: it produces nothing. Check the facility’s hangar in the EVE client."))
                .colors(ink: .hudDanger, background: .clear)
        default:
            EmptyView()
        }
    }
}
