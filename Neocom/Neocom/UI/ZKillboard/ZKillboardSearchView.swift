import KillmailKit
import LiteRowUI
import SDEKit
import SwiftUI

/// The zKillboard section: a criteria form. Nothing is sent to zKillboard until Search (the
/// results, `ZKillboardResultsView`) or, in Killmail ID mode, Open Killmail (the report).
///
/// The form keeps its state while the results are pushed and popped; coming back to the
/// section later it starts from the criteria of the last search (`ZKillboardSheet.criteria`).
struct ZKillboardSearchView: View {
    var body: some View {
        // The database names the subject, and the results' ships and systems.
        SDESectionView { database in
            ZKillboardSearchForm(database: database)
        }
        .hudScreen()
        .navigationTitle("zKillboard")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct ZKillboardSearchForm: View {
    let database: SDEDatabase

    @Environment(ZKillboardSheet.self) private var zkillboard
    @Environment(AccountStore.self) private var accounts

    @State private var criteria = KillboardCriteria()
    @State private var mode: ZKillboardSubjectMode = .subject(.shipType)
    @State private var killmailText = ""
    @State private var didRestore = false
    @State private var picking: KillboardSubjectKind?
    @State private var showsResults = false
    @State private var showsMonthPicker = false
    @State private var openedKillmail: KillmailRef?
    @State private var isLookingUp = false
    @State private var lookupFailure: ZKillboardSheet.Failure?

    /// The Period menu's own last row: not a period, it opens the month picker.
    private enum PeriodChoice: Hashable {
        case period(KillboardPeriod)
        case otherMonth
    }

    private var isByID: Bool { mode == .killmailID }
    private var hasSide: Bool { criteria.subject?.kind.hasSide ?? kind?.hasSide ?? true }
    private var kind: KillboardSubjectKind? {
        if case let .subject(kind) = mode { return kind }
        return nil
    }
    private var killmailID: Int64? { KillboardKillmailID.parse(killmailText) }

    var body: some View {
        HUDList {
            subjectSection
            filtersSection
            actionSection
        }
        .onAppear(perform: restore)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Reset", action: reset)
            }
        }
        .sheet(item: $picking) { kind in
            if kind == .shipType {
                ShipPickerView { typeID, name in
                    criteria.subject = KillboardSubject(kind: .shipType, id: Int64(typeID.rawValue), name: name)
                }
            } else {
                ZKillboardSubjectPicker(kind: kind) { criteria.subject = $0 }
            }
        }
        .sheet(isPresented: $showsMonthPicker) {
            ZKillboardMonthSheet(initial: criteria.period) { criteria.period = $0 }
        }
        .navigationDestination(isPresented: $showsResults) {
            ZKillboardResultsView()
                .liteDatabase(database.database)
        }
        .navigationDestination(item: $openedKillmail) { ref in
            KillmailReportView(sheet: zkillboard.reports(signedIn: accounts.currentKillmails), ref: ref)
                .liteDatabase(database.database)
        }
    }

    // MARK: Subject

    private var subjectSection: some View {
        HUDListSection {
            menuRow(Text("Type")) {
                Picker("Type", selection: Binding(get: { mode }, set: select)) {
                    ForEach(ZKillboardSubjectMode.allCases, id: \.self) { mode in
                        Text(verbatim: ZKillboardText.title(of: mode)).tag(mode)
                    }
                }
            }
            switch mode {
            case .killmailID:
                HStack(spacing: 12) {
                    label(Text("Killmail ID"))
                    TextField("Number or zKillboard link", text: $killmailText)
                        .multilineTextAlignment(.trailing)
                        .font(HUDFont.mono(15, weight: .regular, relativeTo: .body))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .submitLabel(.go)
                        .onSubmit(openKillmail)
                        .onChange(of: killmailText) { lookupFailure = nil }
                }
                .hudRow()
            case let .subject(kind):
                if let subject = criteria.subject {
                    Button { picking = kind } label: {
                        HStack(spacing: 12) {
                            ZKillboardSubjectPlate(subject: subject, size: 40)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(verbatim: subject.name)
                                    .font(HUDFont.display(16, weight: .semibold, relativeTo: .body))
                                    .lineLimit(1)
                                ZKillboardSubjectDetails(subject: subject)
                                    .font(HUDFont.mono(11, weight: .regular, relativeTo: .caption))
                                    .textCase(.uppercase)
                                    .foregroundStyle(Color.hudInkMuted)
                                    .lineLimit(1)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            Text("Change")
                                .foregroundStyle(Color.hudInkMuted)
                            HUDChevron()
                        }
                        .hudRow(HUDRowStyle(minHeight: 60))
                    }
                    .hudRowButton(HUDRowStyle(minHeight: 60))
                } else {
                    Button { picking = kind } label: {
                        HStack {
                            Text(verbatim: ZKillboardText.choose(kind))
                                .font(HUDFont.display(16, weight: .semibold, relativeTo: .body))
                                .foregroundStyle(Color.hudAccent)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            HUDChevron()
                        }
                        .hudRow()
                    }
                    .hudRowButton()
                }
            }
        } header: {
            HUDSectionHeader(Text(String(localized: "zkillboard.search.subject", defaultValue: "Subject", comment: "Section header: whom the search is about (pilot, corporation, ship…)")))
        }
    }

    // MARK: Filters

    private var filtersSection: some View {
        HUDListSection {
            Picker("Side", selection: $criteria.side) {
                ForEach(KillmailFilter.allCases) { side in
                    Text(verbatim: ZKillboardText.title(of: side)).tag(side)
                }
            }
            .pickerStyle(.segmented)
            .disabled(!hasSide)
            .opacity(hasSide ? 1 : 0.4)
            .hudLeadingBlock()

            menuRow(Text("Space")) {
                Picker("Space", selection: $criteria.space) {
                    Text(verbatim: ZKillboardText.title(of: KillboardSpace?.none)).tag(KillboardSpace?.none)
                    ForEach(KillboardSpace.allCases) { space in
                        Text(verbatim: ZKillboardText.title(of: space)).tag(KillboardSpace?.some(space))
                    }
                }
            }
            menuRow(Text("Engagement")) {
                Picker("Engagement", selection: $criteria.engagement) {
                    Text(verbatim: ZKillboardText.title(of: KillboardEngagement?.none)).tag(KillboardEngagement?.none)
                    ForEach(KillboardEngagement.allCases) { engagement in
                        Text(verbatim: ZKillboardText.title(of: engagement)).tag(KillboardEngagement?.some(engagement))
                    }
                }
            }
            menuRow(Text(verbatim: "NPC")) { inclusionPicker("NPC", selection: $criteria.npc) }
            menuRow(Text(verbatim: "AWOX")) { inclusionPicker("AWOX", selection: $criteria.awox) }
            menuRow(Text("Period")) { periodPicker }
            menuRow(Text("Min. Value")) {
                Picker("Min. Value", selection: $criteria.minimumValue) {
                    Text(verbatim: ZKillboardText.title(ofMinimumValue: nil)).tag(Int64?.none)
                    ForEach(KillboardCriteria.minimumValueOptions, id: \.self) { value in
                        Text(verbatim: ZKillboardText.title(ofMinimumValue: value)).tag(Int64?.some(value))
                    }
                }
            }
            Toggle(isOn: $criteria.finalBlowOnly) {
                label(Text("Final Blow Only"))
            }
            .tint(Color.hudAccentFill)
            .disabled(!hasSide)
            .hudRow()
        } header: {
            HUDSectionHeader(Text("Filters"))
        }
        .disabled(isByID)
        .opacity(isByID ? 0.4 : 1)
    }

    private func inclusionPicker(_ title: LocalizedStringKey, selection: Binding<KillboardInclusion>) -> some View {
        Picker(title, selection: selection) {
            ForEach(KillboardInclusion.allCases) { inclusion in
                Text(verbatim: ZKillboardText.title(of: inclusion)).tag(inclusion)
            }
        }
    }

    private var periodPicker: some View {
        var months = KillboardPeriod.recentMonths(3)
        if case .month = criteria.period, !months.contains(criteria.period) {
            months.append(criteria.period)
        }
        let selection = Binding<PeriodChoice>(
            get: { .period(criteria.period) },
            set: { choice in
                switch choice {
                case let .period(period): criteria.period = period
                case .otherMonth: showsMonthPicker = true
                }
            })
        return Picker("Period", selection: selection) {
            Section {
                ForEach([KillboardPeriod.any, .pastHour, .pastDay, .pastWeek], id: \.self) { period in
                    Text(verbatim: ZKillboardText.title(of: period)).tag(PeriodChoice.period(period))
                }
            }
            Section {
                ForEach(months, id: \.self) { period in
                    Text(verbatim: ZKillboardText.title(of: period)).tag(PeriodChoice.period(period))
                }
            }
            Section {
                Text("Other Month…").tag(PeriodChoice.otherMonth)
            }
        }
    }

    // MARK: Search

    private var actionSection: some View {
        Section {
            Group {
                if isByID {
                    Button(action: openKillmail) {
                        HStack(spacing: 8) {
                            if isLookingUp {
                                ProgressView()
                            } else {
                                Image(systemName: "magnifyingglass")
                            }
                            Text("Open Killmail")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .disabled(killmailID == nil || isLookingUp)
                } else {
                    Button(action: search) {
                        Label("Search", systemImage: "magnifyingglass")
                            .frame(maxWidth: .infinity)
                    }
                    .disabled(!criteria.canSearch)
                }
            }
            .hudProminentButton()
            .hudBareRow()
        } footer: {
            VStack(alignment: .leading, spacing: 8) {
                if isByID, let lookupFailure {
                    HUDFootnote(Text(verbatim: lookupFailureMessage(lookupFailure)), color: .hudWarn)
                } else if isByID, !killmailText.trimmingCharacters(in: .whitespaces).isEmpty, killmailID == nil {
                    HUDFootnote(Text("Enter a killmail number, or paste a zkillboard.com/kill/… link."), color: .hudWarn)
                }
                HUDFootnote(isByID
                    ? "A killmail ID opens that one killmail; filters do not apply to it. A zKillboard link pasted here works too."
                    : "Kills and losses count from the side of the subject. A past period reaches back one week at most; a month can be any month. Results are newest first, 200 a page.")
            }
            .hudListFooter()
        }
    }

    private func lookupFailureMessage(_ failure: ZKillboardSheet.Failure) -> String {
        if case .notFound = failure, let killmailID {
            return String(localized: "zKillboard has no killmail \(String(killmailID)).")
        }
        return ZKillboardText.message(of: failure)
    }

    // MARK: Rows

    private func label(_ text: Text) -> some View {
        text
            .font(HUDFont.mono(13, weight: .regular, relativeTo: .subheadline))
            .tracking(1)
            .textCase(.uppercase)
            .foregroundStyle(Color.hudInkMuted)
            .lineLimit(1)
    }

    /// A caption on the left, a system menu picker on the right.
    private func menuRow(_ title: Text, @ViewBuilder picker: () -> some View) -> some View {
        HStack(spacing: 8) {
            label(title)
            Spacer(minLength: 8)
            picker()
                .pickerStyle(.menu)
                .labelsHidden()
        }
        .hudRow(HUDRowStyle(minHeight: 48, verticalPadding: 4))
    }

    // MARK: Actions

    /// Once per visit: the last search's criteria, if there was one.
    private func restore() {
        guard !didRestore else { return }
        didRestore = true
        if let last = zkillboard.criteria, let subject = last.subject {
            criteria = last
            mode = .subject(subject.kind)
        }
    }

    private func select(_ newMode: ZKillboardSubjectMode) {
        guard newMode != mode else { return }
        mode = newMode
        lookupFailure = nil
        if case let .subject(kind) = newMode, criteria.subject?.kind != kind {
            criteria.subject = nil
        }
    }

    private func search() {
        guard criteria.canSearch else { return }
        let criteria = criteria
        Task { await zkillboard.search(criteria) }
        showsResults = true
    }

    private func openKillmail() {
        guard let id = killmailID, !isLookingUp else { return }
        isLookingUp = true
        lookupFailure = nil
        Task {
            defer { isLookingUp = false }
            do throws(ZKillboardSheet.Failure) {
                let ref = try await zkillboard.killmail(id: id)
                // Only for what is still asked: the player may have changed the id, or left
                // Killmail ID mode, while zKillboard answered.
                guard isByID, killmailID == id else { return }
                openedKillmail = ref
            } catch {
                guard isByID, killmailID == id else { return }
                lookupFailure = error
            }
        }
    }

    /// Back to an empty form, in the mode it is in.
    private func reset() {
        criteria = KillboardCriteria()
        killmailText = ""
        lookupFailure = nil
        zkillboard.reset()
    }
}

/// "Other Month…": any month zKillboard has, December 2007 to this one, EVE time.
private struct ZKillboardMonthSheet: View {
    /// zKillboard's records begin here.
    static let firstYear = 2007
    static let firstMonth = 12

    let onPick: (KillboardPeriod) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var year: Int
    @State private var month: Int
    private let currentYear: Int
    private let currentMonth: Int

    init(initial: KillboardPeriod, onPick: @escaping (KillboardPeriod) -> Void) {
        self.onPick = onPick
        let now = ZKillboardText.calendar.dateComponents([.year, .month], from: .now)
        currentYear = now.year ?? 2026
        currentMonth = now.month ?? 1
        if case let .month(year, month) = initial {
            _year = State(initialValue: year)
            _month = State(initialValue: month)
        } else {
            _year = State(initialValue: currentYear)
            _month = State(initialValue: currentMonth)
        }
    }

    private var months: ClosedRange<Int> {
        let first = year == Self.firstYear ? Self.firstMonth : 1
        let last = year == currentYear ? currentMonth : 12
        return first...max(first, last)
    }

    var body: some View {
        NavigationStack {
            HStack(spacing: 0) {
                Picker("Month", selection: $month) {
                    ForEach(months, id: \.self) { month in
                        Text(verbatim: ZKillboardText.calendar.standaloneMonthSymbols[month - 1]).tag(month)
                    }
                }
                Picker("Year", selection: $year) {
                    ForEach(Self.firstYear...currentYear, id: \.self) { year in
                        Text(verbatim: String(year)).tag(year)
                    }
                }
            }
            .pickerStyle(.wheel)
            .padding(.horizontal, HUDMetrics.gutter)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onChange(of: year) { month = min(max(month, months.lowerBound), months.upperBound) }
            .navigationTitle("Other Month")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", systemImage: "checkmark") {
                        onPick(.month(year: year, month: month))
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }
}
