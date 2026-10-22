import MailKit
import SwiftUI

/// One mailbox — a built-in one, a label or a mailing list: its loaded headers by day, All or
/// only the unread, with swipe to mark read or delete, and the next 50 on request.
struct MailInboxView: View {
    let sheet: MailSheet
    let mailbox: Mailbox

    @State private var compose: MailComposeRequest?

    var body: some View {
        let snapshot = sheet.headers(in: mailbox)
        Group {
            if sheet.isMissingScope || snapshot.state.isForbidden {
                MailGrantAccessList()
            } else if let data = snapshot.value {
                TimelineView(.everyMinute) { context in
                    MailInboxList(sheet: sheet, mailbox: mailbox, snapshot: snapshot, data: data, now: context.date)
                }
            } else if case let .failed(error) = snapshot.state {
                MailUnavailableList(error: error) { await snapshot.refresh() }
            } else {
                ProgressView()
                    .controlSize(.large)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .hudScreen()
        .navigationTitle(MailText.title(of: mailbox, sheet: sheet))
        .navigationBarTitleDisplayMode(.inline)
        .task { await snapshot.ensureFresh() }
        .refreshableCommand {
            // The counts on the mailboxes screen move with the list.
            async let headers: Void = snapshot.refresh()
            async let labels: Void = sheet.ensureFresh()
            _ = await (headers, labels)
        }
        .toolbar {
            if !sheet.isMissingScope {
                ToolbarItem(placement: .topBarTrailing) {
                    MailComposeButton { compose = MailComposeRequest(draft: MailDraft()) }
                }
            }
        }
        .mailCompose($compose, sheet: sheet)
    }
}

private enum MailInboxSide: Hashable {
    case all
    case unread
}

/// One day group of the list, for `ForEach`.
private struct MailInboxGroup: Identifiable {
    var group: MailDayGroup
    var headers: [MailHeader]

    var id: MailDayGroup { group }
}

private struct MailInboxList: View {
    let sheet: MailSheet
    let mailbox: Mailbox
    let snapshot: ESISnapshot<ESIMailHeaders>
    let data: ESIMailHeaders
    let now: Date

    @Environment(AccountStore.self) private var accounts
    @State private var side: MailInboxSide = .all
    @State private var actionError: (any Error)?

    var body: some View {
        let headers = data.list.headers.filter(mailbox.contains)
        let unread = headers.filter { !$0.isRead }
        let shown = side == .unread ? unread : headers
        let groups = MailDayGroup.grouped(shown, now: now).map { MailInboxGroup(group: $0.group, headers: $0.headers) }
        // The character's corporation and alliance, as the character sheet last fetched them:
        // `TO RENS TRADERS` rather than `TO YOU` for mail sent to the corporation.
        let profile = accounts.currentSheet?.profile
        let context = MailRowContext(sheet: sheet, names: data.names, labels: sheet.labels.value,
                                     corporationID: profile?.corporationID, allianceID: profile?.allianceID,
                                     now: now)
        HUDList {
            Section {
                Picker("Show", selection: $side) {
                    Text("All").tag(MailInboxSide.all)
                    Text(verbatim: "\(String(localized: "Unread")) · \(unread.count)").tag(MailInboxSide.unread)
                }
                .pickerStyle(.segmented)
                .hudBareRow()
            } footer: {
                HUDFreshnessChip(snapshot, now: now, staleAfter: 600)
                    .hudListFooter()
            }

            if groups.isEmpty {
                Section {
                    empty(hasMail: !headers.isEmpty)
                        .hudBareRow()
                }
            }

            ForEach(groups) { group in
                HUDListSection(group.headers, row: { header in
                    row(header, context: context)
                }, header: {
                    HUDSectionHeader(Text(verbatim: "\(MailText.title(of: group.group)) · \(group.headers.count)"))
                })
            }

            // Shown under an empty mailing list too: its mail may all be older than the
            // unfiltered feed loaded so far.
            if data.list.hasMore, side == .all {
                Section {
                    loadOlderRow
                } footer: {
                    footnote.hudListFooter()
                }
            } else if !groups.isEmpty {
                Section {
                    footnote.hudBareRow()
                }
            }
        }
        .alert(
            "Something Went Wrong",
            isPresented: Binding(get: { actionError != nil }, set: { if !$0 { actionError = nil } }),
            presenting: actionError
        ) { _ in
            Button("OK", role: .cancel) {}
        } message: { error in
            Text(error.localizedDescription)
        }
    }

    private var footnote: HUDFootnote {
        HUDFootnote(sheet.hasOrganizeScope
                    ? "EVE sends mail 50 at a time, newest first. Swipe a mail to mark it read or delete it."
                    : "EVE sends mail 50 at a time, newest first.")
    }

    @ViewBuilder
    private func empty(hasMail: Bool) -> some View {
        if side == .unread, hasMail {
            HUDEmptyPanel(title: Text("All Read"),
                          message: Text("Every loaded mail in \(MailText.title(of: mailbox, sheet: sheet)) is read."))
        } else {
            HUDEmptyPanel(title: Text("No Mail"), message: emptyMessage)
        }
    }

    private var emptyMessage: Text {
        switch mailbox {
        case .label(MailLabelID.inbox):
            Text("Mail sent to you appears here. Write one with the pencil button.")
        case .label(MailLabelID.sent):
            Text("Mail you send appears here. Write one with the pencil button.")
        case .label:
            Text("Mail with this label appears here.")
        case .mailingList:
            Text("Mail sent to this list appears here.")
        }
    }

    private var loadOlderRow: some View {
        let isLoading = sheet.loadingOlder.contains(mailbox.source)
        return Button(action: loadOlder) {
            HStack(spacing: 10) {
                if isLoading {
                    ProgressView()
                } else {
                    Image(systemName: "arrow.down")
                        .font(.system(size: 16, weight: .semibold))
                        .accessibilityHidden(true)
                }
                Text("Load Older Mail")
                    .font(HUDFont.display(15, weight: .semibold, relativeTo: .body))
            }
            .foregroundStyle(Color.hudAccent)
            .frame(maxWidth: .infinity)
            .hudRow()
        }
        .hudRowButton()
        .disabled(isLoading)
    }

    private func loadOlder() {
        Task {
            do {
                try await sheet.loadOlder(in: mailbox.source)
            } catch {
                actionError = error
            }
        }
    }

    @ViewBuilder
    private func row(_ header: MailHeader, context: MailRowContext) -> some View {
        NavigationLink(value: MailRoute.message(header.id)) {
            MailHeaderRow(header: header, context: context)
        }
        .hudRowButton(MailHeaderRow.rowStyle)
        .hudRowActions {
            if sheet.hasOrganizeScope {
                Button(role: .destructive) {
                    perform { try await sheet.delete(mailID: header.id) }
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                Button {
                    perform { try await sheet.setRead(!header.isRead, mailID: header.id) }
                } label: {
                    header.isRead
                        ? Label("Unread", systemImage: "envelope.badge")
                        : Label("Read", systemImage: "envelope.open")
                }
                .tint(Color.hudAccentFill)
            }
        }
    }

    private func perform(_ action: @escaping () async throws -> Void) {
        Task {
            do {
                try await action()
            } catch {
                actionError = error
            }
        }
    }
}

/// What every row of one list reads besides its own header.
struct MailRowContext {
    let sheet: MailSheet
    let names: [Int64: ESIEntityName]
    let labels: MailLabels?
    let corporationID: Int64?
    let allianceID: Int64?
    let now: Date
}

/// One mail of the list: unread dot, the sender's initials, sender and date, subject, who it
/// went to and the player's labels on it.
struct MailHeaderRow: View {
    static let rowStyle = HUDRowStyle(horizontalPadding: 0, minHeight: 0, verticalPadding: 12)

    let header: MailHeader
    let context: MailRowContext

    var body: some View {
        let isUnread = !header.isRead
        let from = MailText.name(of: header.from, names: context.names, sheet: context.sheet)
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(isUnread ? Color.hudAccent : .clear)
                .frame(width: 8, height: 8)
                .frame(width: 8, height: 36)
                .accessibilityHidden(true)
            HUDInitialsAvatar(name: from, url: MailText.avatarURL(of: header.from, names: context.names))
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(verbatim: from)
                        .font(HUDFont.display(15, weight: isUnread ? .semibold : .medium, relativeTo: .body))
                        .foregroundStyle(isUnread ? Color.hudInk : Color.hudInkBodyMuted)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(verbatim: MailText.date(header.date, now: context.now))
                        .font(HUDFont.mono(11, weight: .regular, relativeTo: .caption))
                        .textCase(.uppercase)
                        .foregroundStyle(isUnread ? Color.hudAccent : Color.hudInkMuted)
                        .lineLimit(1)
                        .fixedSize()
                }
                Text(verbatim: header.subject.isEmpty ? String(localized: "(No Subject)") : header.subject)
                    .font(HUDFont.display(14, weight: isUnread ? .semibold : .medium, relativeTo: .subheadline))
                    .foregroundStyle(isUnread ? Color.hudInk : Color.hudInkMuted)
                    .lineLimit(1)
                HStack(spacing: 10) {
                    Text(verbatim: MailText.recipientsLine(header, names: context.names, sheet: context.sheet,
                                                           corporationID: context.corporationID,
                                                           allianceID: context.allianceID))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    ForEach(customLabels) { label in
                        HUDDotLabel(title: Text(verbatim: label.name), color: MailText.color(ofLabel: label.color))
                            .fixedSize()
                    }
                }
                .font(HUDFont.mono(10, weight: .regular, relativeTo: .caption2))
                .tracking(1)
                .textCase(.uppercase)
                .foregroundStyle(Color.hudInkMuted)
            }
        }
        .padding(.leading, 8)
        .padding(.trailing, 14)
        .hudRow(Self.rowStyle)
        .accessibilityElement(children: .combine)
        .accessibilityValue(isUnread ? Text("Unread") : Text(verbatim: ""))
    }

    /// The player's own labels on the mail; the built-in ones go without saying in a list of
    /// one mailbox.
    private var customLabels: [MailLabel] {
        guard let labels = context.labels else { return [] }
        return header.labels.compactMap { id in
            MailLabelID.isWellKnown(id) ? nil : labels.label(id)
        }
    }
}
