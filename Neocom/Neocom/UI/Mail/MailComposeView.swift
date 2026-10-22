import DemoFixtures
import MailKit
import SwiftUI

/// Writing a mail: a new one (the pencil on the mailboxes and on a mailbox), or a reply, a
/// reply to all or a forward of an open message, which arrive as a prepared `draft`.
///
/// Presented as a sheet by `View.mailCompose(_:sheet:)`. Without the send scope it shows the
/// grant-access panel instead of the form.
struct MailComposeView: View {
    let sheet: MailSheet
    let draft: MailDraft

    @Environment(\.dismiss) private var dismiss

    init(sheet: MailSheet, draft: MailDraft) {
        self.sheet = sheet
        self.draft = draft
    }

    var body: some View {
        NavigationStack {
            if sheet.hasSendScope {
                MailComposeForm(sheet: sheet, initial: draft)
            } else {
                HUDList(isTransparent: true) {
                    Section {
                        HUDGrantAccessPanel(title: Text("No Send Access"),
                                            message: Text("Writing mail needs one more permission. Sign in to EVE again and allow Neocom to send mail."))
                            .hudBareRow()
                    }
                }
                .navigationTitle("New Mail")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                }
            }
        }
    }
}

/// Where sending stands. The draft stays as written in every phase but `.sent`.
private enum MailComposePhase: Equatable {
    case editing
    case sending
    /// EVE refused the mail for a CSPA fee; `nil` when it did not say how much.
    case needsApproval(cost: Int64?)
    /// Anything else. `approvedCost` is what the failed attempt approved, for Try Again.
    case failed(message: String?, approvedCost: Int64)
    /// Sent; the sheet closes on its own a moment later.
    case sent
}

private struct MailComposeForm: View {
    let sheet: MailSheet
    let initial: MailDraft

    @Environment(\.dismiss) private var dismiss
    @Environment(AccountStore.self) private var accounts

    @State private var draft: MailDraft
    @State private var query = ""
    @State private var suggestions: [MailSuggestion] = []
    @State private var isSearching = false
    /// Names of the recipients picked from suggestions; the rest are named by the sheet.
    @State private var names: [MailRecipient: String] = [:]
    @State private var phase: MailComposePhase = .editing
    @State private var isConfirmingDiscard = false
    @FocusState private var focus: Field?

    private enum Field: Hashable {
        case recipient, subject, body
    }

    private static let statusID = "status"
    private static let sentDismissDelay: Duration = .seconds(1.6)
    private static let searchDebounce: Duration = .milliseconds(300)

    private static let fieldStyle: HUDRowStyle = {
        var style = HUDRowStyle.sheet
        style.horizontalPadding = 12
        style.verticalPadding = 10
        return style
    }()

    private static let groupStyle: HUDRowStyle = {
        var style = HUDRowStyle.sheet
        style.minHeight = 0
        style.verticalPadding = 0
        return style
    }()

    private static let bodyStyle: HUDRowStyle = {
        var style = HUDRowStyle.sheet
        style.verticalPadding = 14
        return style
    }()

    init(sheet: MailSheet, initial: MailDraft) {
        self.sheet = sheet
        self.initial = initial
        _draft = State(initialValue: initial)
    }

    // MARK: Derived

    private var trimmedQuery: String { query.trimmingCharacters(in: .whitespaces) }
    private var isSuggesting: Bool { !trimmedQuery.isEmpty && !isBusy }
    private var isBusy: Bool { phase == .sending || phase == .sent }
    private var hasChanges: Bool { draft != initial }

    private var isApproving: Bool {
        if case .needsApproval = phase { return true }
        return false
    }

    /// The recipient who charges the fee, only when that is certain: a mail to one character.
    /// ESI's refusal does not name who charges, and neither does `/cspa`, which answers one
    /// figure for all of them — so with several recipients nobody is named.
    private var chargingRecipient: MailRecipient? {
        guard isApproving, draft.recipients.count == 1, let only = draft.recipients.first,
              only.kind == .character else { return nil }
        return only
    }

    private var title: LocalizedStringKey {
        if initial.quote.isEmpty { return "New Mail" }
        return initial.recipients.isEmpty ? "Forward" : "Reply"
    }

    /// The selected character's sheet, which owns the wallet route — when it is this mail's
    /// character.
    private var characterSheet: CharacterSheet? {
        accounts.currentAccountID == sheet.characterID ? accounts.currentSheet : nil
    }

    private func name(of recipient: MailRecipient) -> String {
        names[recipient] ?? MailText.name(of: recipient, names: [:], sheet: sheet)
    }

    // MARK: Body

    var body: some View {
        ScrollViewReader { proxy in
            HUDList(isTransparent: true) {
                status
                recipientsSection
                if !isSuggesting {
                    subjectSection
                    messageSection
                }
            }
            .onChange(of: phase) { _, new in
                guard new != .editing, new != .sending else { return }
                withAnimation { proxy.scrollTo(Self.statusID, anchor: .top) }
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbar }
        .interactiveDismissDisabled(hasChanges || phase == .sending)
        .onAppear { focus = draft.recipients.isEmpty ? .recipient : .body }
        .onChange(of: draft.subject) { _, new in
            if new.count > MailLimits.subjectLength { draft.subject = String(new.prefix(MailLimits.subjectLength)) }
        }
        .onChange(of: draft.recipients) {
            // A fee was asked — or approved, for Try Again — for the recipients as they were;
            // another set is another question.
            switch phase {
            case .needsApproval: phase = .editing
            case let .failed(message, approvedCost) where approvedCost > 0:
                phase = .failed(message: message, approvedCost: 0)
            default: break
            }
        }
        .task(id: query) { await suggest(query) }
        .task(id: phase) {
            switch phase {
            case .sent:
                try? await Task.sleep(for: Self.sentDismissDelay)
                if !Task.isCancelled { dismiss() }
            case .needsApproval:
                // The panel shows the balance; the character sheet owns the wallet route.
                await characterSheet?.ensureProfileFresh()
            default:
                break
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Cancel") {
                if hasChanges, phase != .sent {
                    isConfirmingDiscard = true
                } else {
                    dismiss()
                }
            }
            .disabled(phase == .sending)
            .confirmationDialog("Discard this mail?", isPresented: $isConfirmingDiscard, titleVisibility: .visible) {
                Button("Discard Mail", role: .destructive) { dismiss() }
                Button("Keep Editing", role: .cancel) {}
            } message: {
                Text("What you have written is not kept anywhere.")
            }
        }
        ToolbarItem(placement: .confirmationAction) {
            switch phase {
            case .sending:
                ProgressView()
                    .accessibilityLabel(Text("Sending"))
            case .sent:
                Image(systemName: "checkmark")
                    .foregroundStyle(Color.hudOk)
                    .accessibilityLabel(Text("Sent"))
            default:
                Button {
                    send()
                } label: {
                    Label("Send", systemImage: "arrow.up")
                }
                .disabled(!draft.canSend || isApproving)
            }
        }
    }

    // MARK: Status

    @ViewBuilder
    private var status: some View {
        switch phase {
        case .editing, .sending:
            EmptyView()
        case let .needsApproval(cost):
            Section {
                cspaPanel(cost: cost)
                    .id(Self.statusID)
                    .hudBareRow()
            }
        case let .failed(message, approvedCost):
            Section {
                failedPanel(message: message, approvedCost: approvedCost)
                    .id(Self.statusID)
                    .hudBareRow()
            }
        case .sent:
            Section {
                HUDPanel {
                    VStack(alignment: .leading, spacing: 6) {
                        caption(Text("Sent"), systemImage: "checkmark", color: .hudOk)
                        Text("It shows up in Sent with EVE’s next mail refresh. This sheet closes on its own.")
                            .font(.hudBody)
                            .foregroundStyle(Color.hudInkBodyMuted)
                    }
                    .padding(.horizontal, HUDMetrics.gutter)
                    .padding(.vertical, 14)
                }
                .id(Self.statusID)
                .hudBareRow()
            }
        }
    }

    private func caption(_ text: Text, systemImage: String, color: Color) -> some View {
        Label {
            text
        } icon: {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .bold))
        }
        .labelStyle(MailCaptionLabelStyle())
        .font(.hudLabel)
        .tracking(2)
        .textCase(.uppercase)
        .foregroundStyle(color)
        .accessibilityAddTraits(.isHeader)
    }

    private func cspaPanel(cost: Int64?) -> some View {
        let charging = chargingRecipient
        let chargingName = charging.map(name(of:))
        let balance = characterSheet?.profile?.balance
        let canAfford = cost.map { cost in balance.map { $0 >= Double(cost) } ?? true } ?? false

        return HUDPanel(tone: .warn) {
            VStack(alignment: .leading, spacing: 8) {
                caption(Text("CSPA charge · Not sent yet"), systemImage: "exclamationmark.triangle", color: .hudWarn)
                Group {
                    if let chargingName {
                        Text("\(chargingName) charges a fee to receive mail from pilots outside their contacts.")
                    } else {
                        Text("Someone this mail is addressed to charges a fee to receive mail from pilots outside their contacts. EVE does not say who.")
                    }
                }
                .font(.hudBody)
                .foregroundStyle(Color.hudInkBodyMuted)
                .fixedSize(horizontal: false, vertical: true)

                readout(Text("Fee")) {
                    if let cost {
                        Text(verbatim: "\(cost.formatted()) ISK")
                            .font(HUDFont.mono(15, weight: .semibold, relativeTo: .body))
                            .foregroundStyle(Color.hudWarn)
                    } else {
                        Text("Unknown")
                            .textCase(.uppercase)
                            .foregroundStyle(Color.hudWarn)
                    }
                }
                if let balance {
                    readout(Text("Wallet")) {
                        Text(verbatim: ISK.string(balance))
                            .fontWeight(.semibold)
                            .foregroundStyle(canAfford || cost == nil ? Color.hudInk : Color.hudDanger)
                    }
                }

                VStack(spacing: 8) {
                    if let cost {
                        Button {
                            send(approvedCost: cost)
                        } label: {
                            Text("Approve \(cost.formatted()) ISK and Send")
                                .frame(maxWidth: .infinity)
                        }
                        .hudProminentButton()
                        .disabled(!canAfford)
                    }
                    if let charging, let chargingName {
                        Button("Remove \(chargingName)") {
                            draft.remove(charging)
                        }
                        .buttonStyle(.borderless)
                        .frame(maxWidth: .infinity, minHeight: 44)
                    } else if cost == nil {
                        Button("Back to Draft") { phase = .editing }
                            .buttonStyle(.borderless)
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                }
                .padding(.top, 6)
            }
            .padding(.horizontal, HUDMetrics.gutter)
            .padding(.vertical, 14)

            if cost == nil {
                HUDWarnNote(Text("Neocom can approve only a fee EVE names, and it named none. Send this mail from the game, which shows the fee, or take out the recipients who charge it."))
            } else if !canAfford {
                HUDWarnNote(Text("The wallet does not hold the fee. EVE takes it only when the mail goes out, so nothing has been charged."))
            } else {
                HUDWarnNote(Text("EVE takes the fee from your wallet only when the mail goes out. Nothing is charged without this approval."))
            }
        }
    }

    /// `message` trimmed, ending in a full stop unless it already ends a sentence.
    private static func sentence(_ message: String) -> String {
        let message = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let last = message.last, !".!?…。".contains(last) else { return message }
        return message + "."
    }

    private func readout<Value: View>(_ label: Text, @ViewBuilder value: () -> Value) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            label
                .font(.hudMicro)
                .tracking(1.5)
                .textCase(.uppercase)
                .foregroundStyle(Color.hudInkMuted)
            HUDLeader()
                .frame(minWidth: 12)
            value()
        }
        .font(.hudCaption)
        .accessibilityElement(children: .combine)
    }

    private func failedPanel(message: String?, approvedCost: Int64) -> some View {
        HUDPanel(tone: .danger) {
            VStack(alignment: .leading, spacing: 8) {
                caption(Text("Not sent"), systemImage: "exclamationmark.circle", color: .hudDanger)
                Group {
                    if let message = message.map(Self.sentence), !message.isEmpty {
                        if DemoIDs.contains(sheet.characterID) {
                            // The demo's own rejection, not EVE's.
                            Text("\(message) Your mail is kept as written.")
                        } else {
                            Text("EVE refused the mail: \(message) Your mail is kept as written — send it again when you are ready.")
                        }
                    } else {
                        Text("EVE did not take the mail. Your mail is kept as written — send it again when you are ready.")
                    }
                }
                .font(.hudBody)
                .foregroundStyle(Color.hudInkBodyMuted)
                .fixedSize(horizontal: false, vertical: true)
                Button("Try Again") { send(approvedCost: approvedCost) }
                    .buttonStyle(.borderless)
                    .fontWeight(.semibold)
                    .frame(minHeight: 44)
                    .disabled(!draft.canSend)
            }
            .padding(.horizontal, HUDMetrics.gutter)
            .padding(.vertical, 14)
        }
    }

    // MARK: Recipients

    private var recipientsSection: some View {
        HUDListSection {
            HUDWrapLayout(spacing: 6, fillsLastLine: true) {
                ForEach(draft.recipients, id: \.self) { recipient in
                    token(recipient)
                }
                TextField("Name", text: $query)
                    .font(.hudSheetBody)
                    .focused($focus, equals: .recipient)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .onSubmit {
                        if let first = suggestions.first { add(first) }
                    }
                    .frame(minWidth: 110, minHeight: 30)
                    .disabled(draft.recipients.count >= MailLimits.recipients)
                    .accessibilityLabel(Text("Add recipient"))
            }
            .hudRow(Self.fieldStyle)

            if isSuggesting {
                suggestionRows
            }
        } header: {
            HUDSectionHeader(Text("To")) {
                Text("\(draft.recipients.count) of \(MailLimits.recipients)")
            }
        } footer: {
            if isSuggesting {
                if !sheet.hasSearchScope {
                    HUDFootnote("Only your contacts and mailing lists are offered: searching all of EVE needs the search permission.")
                } else if trimmedQuery.count < MailSuggestions.minimumSearchLength {
                    HUDFootnote("Type three letters or more to search all of EVE.")
                }
            }
        }
        .opacity(isBusy ? 0.55 : 1)
        .disabled(isBusy)
    }

    private func token(_ recipient: MailRecipient) -> some View {
        let charges = recipient == chargingRecipient
        return HUDTokenChip(title: Text(verbatim: name(of: recipient)),
                            systemImage: MailText.symbol(of: recipient.kind),
                            kindLabel: MailText.title(of: recipient.kind),
                            tone: charges ? .warn : .normal,
                            marker: charges ? Text(verbatim: "CSPA") : nil,
                            onRemove: { draft.remove(recipient) })
    }

    @ViewBuilder
    private var suggestionRows: some View {
        let contacts = suggestions.filter { if case .contact = $0.source { true } else { false } }
        let lists = suggestions.filter { $0.source == .mailingList }
        let found = suggestions.filter { $0.source == .search }
        if !contacts.isEmpty {
            groupTitle(Text("Contacts"))
            ForEach(contacts) { suggestionRow($0) }
        }
        if !lists.isEmpty {
            groupTitle(Text("Mailing Lists"))
            ForEach(lists) { suggestionRow($0) }
        }
        if !found.isEmpty || isSearching {
            groupTitle(Text(verbatim: "EVE"), isBusy: isSearching)
            ForEach(found) { suggestionRow($0) }
        }
        if suggestions.isEmpty, !isSearching {
            Text("No matches")
                .font(.hudLabel)
                .tracking(1.5)
                .textCase(.uppercase)
                .foregroundStyle(Color.hudInkMuted)
                .padding(.vertical, 14)
                .hudRow(Self.groupStyle)
        }
    }

    private func groupTitle(_ title: Text, isBusy: Bool = false) -> some View {
        HStack(spacing: 8) {
            title
                .font(.hudMicro)
                .tracking(1.5)
                .textCase(.uppercase)
                .foregroundStyle(Color.hudInkMuted)
                .accessibilityAddTraits(.isHeader)
            if isBusy {
                ProgressView()
                    .controlSize(.mini)
                    .accessibilityLabel(Text("Searching"))
            }
        }
        .padding(.top, 12)
        .padding(.bottom, 6)
        .hudRow(Self.groupStyle)
    }

    private func suggestionRow(_ suggestion: MailSuggestion) -> some View {
        Button {
            add(suggestion)
        } label: {
            HStack(spacing: 12) {
                HUDSymbolPlate(systemImage: MailText.symbol(of: suggestion.recipient.kind), size: 32)
                HUDRowTitle(title: Text(verbatim: suggestion.name), subtitle: subtitle(of: suggestion),
                            font: HUDFont.display(15, weight: .semibold, relativeTo: .body))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .hudRow(.sheet)
        }
        .hudRowButton(.sheet)
    }

    private func subtitle(of suggestion: MailSuggestion) -> Text {
        let kind = MailText.title(of: suggestion.recipient.kind)
        if case let .contact(standing) = suggestion.source {
            let value = standing.formatted(.number.precision(.fractionLength(1)).sign(strategy: .always(includingZero: false)))
            return Text("\(kind) · Standing \(value)")
        }
        return kind
    }

    private func add(_ suggestion: MailSuggestion) {
        names[suggestion.recipient] = suggestion.name
        draft.add(suggestion.recipient)
        query = ""
        suggestions = []
        focus = .recipient
    }

    /// Contacts and lists at once; ESI's search, from three characters on, after a pause in
    /// typing. A new query cancels the old one's task (`task(id:)`), so a stale answer never
    /// lands. Search results of the previous query that still match stay on screen meanwhile,
    /// so the `EVE` group does not blink out on every keystroke.
    private func suggest(_ query: String) async {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            suggestions = []
            isSearching = false
            return
        }
        let excluding = Set(draft.recipients)
        let willSearch = sheet.hasSearchScope && trimmed.count >= MailSuggestions.minimumSearchLength
        let local = await sheet.suggestions(for: trimmed, excluding: excluding, searching: false)
        guard !Task.isCancelled else { return }
        let kept = willSearch
            ? suggestions.filter {
                $0.source == .search && !excluding.contains($0.recipient)
                    && !local.contains($0)
                    && $0.name.range(of: trimmed, options: [.caseInsensitive, .diacriticInsensitive]) != nil
            }
            : []
        suggestions = local + kept
        isSearching = willSearch
        guard willSearch else { return }
        do {
            try await Task.sleep(for: Self.searchDebounce)
        } catch {
            return
        }
        let all = await sheet.suggestions(for: trimmed, excluding: excluding)
        guard !Task.isCancelled else { return }
        suggestions = all
        isSearching = false
    }

    // MARK: Subject and message

    private var subjectSection: some View {
        HUDListSection {
            TextField("Subject", text: $draft.subject)
                .font(.hudSheetBody)
                .focused($focus, equals: .subject)
                .submitLabel(.next)
                .onSubmit { focus = .body }
                .hudRow(.sheet)
        } header: {
            HUDSectionHeader(Text("Subject")) {
                if draft.subject.count > MailLimits.subjectLength - 100 {
                    Text(verbatim: "\(draft.subject.count) / \(MailLimits.subjectLength.formatted())")
                }
            }
        }
        .opacity(isBusy ? 0.55 : 1)
        .disabled(isBusy)
    }

    private var messageSection: some View {
        let issues = draft.issues
        let length = draft.bodyLength
        let isTooLong = issues.contains(.bodyTooLong)
        let quoteIsCut = !isTooLong && length > MailLimits.bodyLength
        return HUDListSection {
            TextField("Message", text: $draft.body, axis: .vertical)
                .font(.hudSheetBody)
                .lineLimit((initial.quote.isEmpty ? 7 : 4)...)
                .focused($focus, equals: .body)
                .hudRow(Self.bodyStyle)
            if let quote = Self.quoteParts(draft.quote) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(verbatim: quote.header)
                        .font(.hudMicro)
                        .tracking(1.5)
                        .textCase(.uppercase)
                        .foregroundStyle(Color.hudInkMuted)
                    if !quote.text.isEmpty {
                        Text(verbatim: quote.text)
                            .font(.subheadline)
                            .foregroundStyle(Color.hudInkMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.top, 4)
                .padding(.bottom, 6)
                .hudRow(.sheet)
                .accessibilityElement(children: .combine)
            }
        } header: {
            HUDSectionHeader(Text("Message")) {
                Text(verbatim: "\(length.formatted()) / \(MailLimits.bodyLength.formatted())")
                    .foregroundStyle(isTooLong ? Color.hudDanger : quoteIsCut ? Color.hudWarn : Color.hudInkMuted)
            }
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                if isTooLong {
                    HUDFootnote(Text("EVE takes at most \(MailLimits.bodyLength.formatted()) characters; links and line breaks count as more than one."),
                                color: .hudDanger)
                } else if quoteIsCut {
                    HUDFootnote(Text("The quoted mail is cut to fit EVE’s \(MailLimits.bodyLength.formatted()) characters."),
                                color: .hudWarnNoteInk)
                }
                if initial.quote.isEmpty {
                    HUDFootnote("Sent as plain text. Pilots, corporations, alliances and your mailing lists can receive mail.")
                } else {
                    HUDFootnote("Sent as plain text. The quoted mail goes along as text; its links do not.")
                }
            }
        }
        .opacity(isBusy ? 0.55 : 1)
        .disabled(isBusy)
    }

    /// `MailQuote.block` taken apart for the screen: its header line (`On … wrote`, the colon
    /// dropped) and the quoted text, without the leading blank lines and the separator.
    static func quoteParts(_ quote: String) -> (header: String, text: String)? {
        var lines = quote.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        while let first = lines.first,
              first.trimmingCharacters(in: .whitespaces).isEmpty || first == MailQuote.separator {
            lines.removeFirst()
        }
        guard !lines.isEmpty else { return nil }
        var header = lines.removeFirst()
        if header.hasSuffix(":") { header.removeLast() }
        return (header, lines.joined(separator: "\n").trimmingCharacters(in: .newlines))
    }

    // MARK: Sending

    private func send(approvedCost: Int64 = 0) {
        guard draft.canSend, !isBusy else { return }
        focus = nil
        query = ""
        phase = .sending
        let draft = draft
        Task {
            switch await sheet.send(draft, approvedCost: approvedCost) {
            case .sent:
                phase = .sent
            case let .needsApproval(cost):
                phase = .needsApproval(cost: cost)
            case let .failed(message):
                phase = .failed(message: message, approvedCost: approvedCost)
            }
        }
    }
}

/// A caption's glyph and words, 8pt apart on one line.
private struct MailCaptionLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 8) {
            configuration.icon
            configuration.title
        }
    }
}

/// A draft being presented in `MailComposeView`.
struct MailComposeRequest: Identifiable {
    let id = UUID()
    var draft: MailDraft
}

extension View {
    /// Presents `MailComposeView` for `request` while it is set.
    func mailCompose(_ request: Binding<MailComposeRequest?>, sheet: MailSheet) -> some View {
        self.sheet(item: request) { request in
            MailComposeView(sheet: sheet, draft: request.draft)
        }
    }
}
