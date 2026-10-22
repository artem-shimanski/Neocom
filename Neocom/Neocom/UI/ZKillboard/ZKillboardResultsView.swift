import KillmailKit
import LiteRowUI
import SDEKit
import SwiftUI

/// What a zKillboard search found: the subject and the filters on top, the killmails by UTC
/// day, newest first, "Load Older" for the next page. A row opens the killmail's report.
///
/// Reads the `ZKillboardSheet` only; the search itself was started by the form's Search.
/// No time-relative text here, so no clock.
///
/// A row opens its report through `opened` rather than a navigation path value: the report is
/// pushed at once and shows its own loading, and while one is open a second tap pushes nothing.
struct ZKillboardResultsView: View {
    @Environment(ZKillboardSheet.self) private var zkillboard
    @Environment(AccountStore.self) private var accounts
    @Environment(\.dismiss) private var dismiss
    /// Handed on to the report: a destination does not inherit it.
    @Environment(\.liteDatabase) private var database
    @State private var opened: KillmailRef?

    var body: some View {
        let subject = zkillboard.criteria?.subject
        let entries = zkillboard.entries
        let systemIDs = entries.map(\.killmail.solarSystemID) + (subject?.kind == .solarSystem ? [subject!.id] : [])
        let typeIDs = entries.map(\.killmail.victim.shipTypeID) + (subject?.kind == .shipType ? [subject!.id] : [])
        KillmailStaticsReader(systemIDs: systemIDs, typeIDs: typeIDs) { statics in
            HUDList {
                if let criteria = zkillboard.criteria, let subject {
                    header(subject, criteria: criteria)
                }
                content(subject: subject, statics: statics)
            }
        }
        .navigationTitle(subject?.name ?? "zKillboard")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $opened) { ref in
            let report = KillmailReportView(sheet: zkillboard.reports(signedIn: accounts.currentKillmails), ref: ref)
            if let database {
                report.liteDatabase(database)
            } else {
                report
            }
        }
        // The sheet the reports go through is made here, not on the first tap.
        .onAppear { _ = zkillboard.reports(signedIn: accounts.currentKillmails) }
    }

    // MARK: Header

    private func header(_ subject: KillboardSubject, criteria: KillboardCriteria) -> some View {
        HUDListSection {
            if subject.kind == .shipType {
                NavigationLink(value: DatabaseRoute.type(TypeID(rawValue: UInt32(clamping: subject.id)))) {
                    subjectRow(subject, isLink: true)
                }
                .hudRowButton(Self.subjectStyle)
            } else {
                subjectRow(subject, isLink: false)
            }
            Button { dismiss() } label: {
                HUDReadoutRow(Text("Filters")) {
                    Text(verbatim: ZKillboardText.summary(of: criteria))
                }
            }
            .hudRowButton(.readout)
            Text("zKillboard · Newest First · 200 a Page")
                .font(.hudMicro)
                .tracking(1)
                .textCase(.uppercase)
                .foregroundStyle(Color.hudInkMuted)
                .frame(maxWidth: .infinity, alignment: .leading)
                .hudRow(HUDRowStyle(minHeight: 0, verticalPadding: 9))
        }
    }

    private static let subjectStyle = HUDRowStyle(minHeight: 0, verticalPadding: 14)

    private func subjectRow(_ subject: KillboardSubject, isLink: Bool) -> some View {
        HStack(spacing: 14) {
            ZKillboardSubjectPlate(subject: subject, size: 56)
            VStack(alignment: .leading, spacing: 5) {
                Text(verbatim: subject.name.uppercased())
                    .font(HUDFont.display(22, weight: .bold, relativeTo: .title2))
                    .lineLimit(2)
                ZKillboardSubjectDetails(subject: subject)
                    .font(.hudLabel)
                    .tracking(1)
                    .textCase(.uppercase)
                    .foregroundStyle(Color.hudInkMuted)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if isLink { HUDChevron() }
        }
        .hudRow(Self.subjectStyle)
    }

    // MARK: Content

    @ViewBuilder
    private func content(subject: KillboardSubject?, statics: KillmailStatics) -> some View {
        switch zkillboard.phase {
        case .idle:
            EmptyView()
        case .searching:
            Section {
                ProgressView()
                    .controlSize(.large)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 32)
                    .hudBareRow()
            }
        case .failed(.busy):
            Section {
                busyPanel
                    .hudBareRow()
            }
        case let .failed(failure):
            Section {
                HUDEmptyPanel(title: Text("Search Failed"), message: Text(verbatim: ZKillboardText.message(of: failure))) {
                    Button("Try Again", action: retry)
                        .hudProminentButton()
                }
                .hudBareRow()
            }
        case .loaded:
            if zkillboard.isEmpty {
                Section {
                    HUDEmptyPanel(title: Text("No Killmails"),
                                  message: Text("Nothing on zKillboard matches \(subject?.name ?? "") with these filters.")) {
                        Button("Change Filters") { dismiss() }
                            .font(HUDFont.display(15, weight: .semibold, relativeTo: .body))
                            .foregroundStyle(Color.hudAccent)
                    }
                    .hudBareRow()
                }
            } else if let subject {
                rows(subject: subject, statics: statics)
            }
        }
    }

    private var busyPanel: some View {
        HUDPanel(tone: .warn) {
            VStack(spacing: 10) {
                Text("zKillboard Is Busy")
                    .font(HUDFont.mono(13, weight: .regular, relativeTo: .subheadline))
                    .tracking(2)
                    .textCase(.uppercase)
                    .foregroundStyle(Color.hudWarn)
                Text(verbatim: ZKillboardText.message(of: .busy))
                    .font(.hudBody)
                    .foregroundStyle(Color.hudInkBodyMuted)
                    .frame(maxWidth: 280)
                Button("Try Again", action: retry)
                    .buttonStyle(.glass)
                    .padding(.top, 8)
            }
            .multilineTextAlignment(.center)
            .padding(.vertical, 28)
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder
    private func rows(subject: KillboardSubject, statics: KillmailStatics) -> some View {
        let naming = KillmailNaming(names: zkillboard.names, sheet: nil)
        let pilotID = accounts.currentAccountID
        let criteria = zkillboard.criteria
        let groupOf: (Int64) -> Int64? = { typeID in statics.types[typeID].map { Int64($0.groupID.rawValue) } }
        ForEach(zkillboard.days) { day in
            HUDListSection(day.entries, row: { entry in
                let killmail = entry.killmail
                Button { open(killmail.ref) } label: {
                    KillmailRow(killmail: killmail,
                                side: criteria?.side(of: killmail, groupOf: groupOf),
                                isVictimPilot: pilotID != nil && killmail.victim.characterID == pilotID,
                                victim: naming.victim(of: killmail),
                                shipName: statics.typeName(killmail.victim.shipTypeID),
                                place: statics.placeLine(killmail.solarSystemID,
                                                         details: [String(localized: "\(entry.involved) involved")]),
                                value: entry.totalValue,
                                valueCaption: Text(verbatim: "zKB ISK")) {
                        ZKillboardEntryTags(entry: entry)
                    }
                }
                .hudRowButton(KillmailRow<EmptyView>.rowStyle)
                .killmailContextMenu(killID: killmail.ref.id)
            }, header: {
                HUDSectionHeader(Text(verbatim: EVETime.date(day.day))) {
                    Text(verbatim: "\(day.entries.count)")
                }
            })
        }

        if zkillboard.pendingBodies > 0, !zkillboard.isLoadingOlder {
            Section {
                HUDLoadMoreRow(title: Text("Loading Killmails"), detail: Text("\(zkillboard.pendingBodies) more"), isLoading: true) {}
            }
        }

        if zkillboard.hasOlder || zkillboard.olderFailure != nil {
            Section {
                if zkillboard.hasOlder {
                    HUDLoadMoreRow(detail: zkillboard.results.nextPage.map { Text("Page \($0)") },
                                   isLoading: zkillboard.isLoadingOlder) {
                        Task { await zkillboard.loadOlder() }
                    }
                }
            } footer: {
                if let failure = zkillboard.olderFailure {
                    HUDFootnote(Text(verbatim: ZKillboardText.message(of: failure)), color: .hudWarn)
                        .hudListFooter()
                }
            }
        }

        Section {
            HUDFootnote(Text("Values and points are zKillboard's own, not Neocom's estimate. \(ZKillboardText.sides(of: subject)) zKillboard holds back killmails for their first five minutes and serves up to 100 pages."))
                .hudBareRow()
        }
    }

    /// Once: a tap while a report is open, or on its way, does nothing.
    private func open(_ ref: KillmailRef) {
        guard opened == nil else { return }
        opened = ref
    }

    private func retry() {
        guard let criteria = zkillboard.criteria else { return }
        Task { await zkillboard.search(criteria) }
    }
}

/// The last line of a result row: zKillboard's `SOLO` / `NPC` / `AWOX` and its points.
private struct ZKillboardEntryTags: View {
    let entry: KillboardEntry

    var body: some View {
        if entry.isSolo || entry.isNPC || entry.isAwox || entry.points != nil {
            HStack(spacing: 6) {
                if entry.isSolo { HUDOutlineTag(text: Text("Solo"), color: .hudInkMuted) }
                if entry.isNPC { HUDOutlineTag(text: Text(verbatim: "NPC"), color: .hudInkMuted) }
                if entry.isAwox { HUDOutlineTag(text: Text(verbatim: "AWOX"), color: .hudInkMuted) }
                Spacer(minLength: 0)
                if let points = entry.points {
                    Text(verbatim: ZKillboardText.points(points))
                        .font(.hudMicro)
                        .tracking(1)
                        .textCase(.uppercase)
                        .foregroundStyle(Color.hudInkMuted)
                        .lineLimit(1)
                }
            }
        }
    }
}
