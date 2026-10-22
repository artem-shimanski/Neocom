import LiteRowUI
import MailKit
import SDEKit
import SwiftUI

/// The Mail section: the unread total, the built-in mailboxes, the player's labels and the
/// mailing lists, from the `MailSheet`. Each leads to its header list (`MailInboxView`), and
/// a mail to its message (`MailMessageView`).
struct MailView: View {
    var body: some View {
        // The database is for the message: its links open items in the database, and its
        // fitting cards name their hull.
        SDESectionView { database in
            MailBody(database: database)
        }
        .hudScreen()
        .navigationTitle("Mail")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct MailBody: View {
    let database: SDEDatabase

    @Environment(AccountStore.self) private var accounts

    var body: some View {
        if let sheet = accounts.currentMail {
            MailboxesScreen(sheet: sheet, database: database)
                // Another character is another sheet, not this one refilled.
                .id(ObjectIdentifier(sheet))
        }
    }
}

/// The screens of the section.
enum MailRoute: Hashable {
    case mailbox(Mailbox)
    case message(Int64)

    @ViewBuilder
    func destination(sheet: MailSheet, database: SDEDatabase) -> some View {
        switch self {
        case let .mailbox(mailbox):
            MailInboxView(sheet: sheet, mailbox: mailbox)
        case let .message(id):
            MailMessageView(sheet: sheet, mailID: id, database: database)
        }
    }
}

/// The empty state of every Mail screen without the read scope.
struct MailGrantAccessList: View {
    var body: some View {
        HUDList {
            Section {
                HUDGrantAccessPanel(title: Text("No Mail Access"),
                                    message: Text("Your mail needs more permissions. Sign in to EVE again and allow Neocom to read, send and organize your mail."))
                    .hudBareRow()
            }
        }
    }
}

/// A fetch that failed with nothing on screen yet: why, and a retry.
struct MailUnavailableList: View {
    let error: any Error
    let retry: () async -> Void

    var body: some View {
        HUDList {
            Section {
                HUDEmptyPanel(title: Text("Mail Unavailable"), message: Text(error.localizedDescription)) {
                    Button("Retry") {
                        Task { await retry() }
                    }
                    .hudProminentButton()
                }
                .hudBareRow()
            }
        }
    }
}

/// The pencil of the mailboxes and of a mailbox: a new, empty mail.
struct MailComposeButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label("New Mail", systemImage: "square.and.pencil")
        }
    }
}

private struct MailboxesScreen: View {
    let sheet: MailSheet
    let database: SDEDatabase

    @State private var compose: MailComposeRequest?

    var body: some View {
        Group {
            if sheet.isMissingScope {
                MailGrantAccessList()
            } else if let labels = sheet.labels.value {
                TimelineView(.everyMinute) { context in
                    MailboxesList(sheet: sheet, labels: labels, now: context.date)
                }
            } else if case let .failed(error) = sheet.labels.state {
                MailUnavailableList(error: error) { await sheet.refresh() }
            } else {
                ProgressView()
                    .controlSize(.large)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task { await sheet.ensureFresh() }
        .refreshableCommand { await sheet.refresh() }
        .navigationDestination(for: MailRoute.self) { route in
            route.destination(sheet: sheet, database: database)
                .liteDatabase(database.database)
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

private struct MailboxesList: View {
    let sheet: MailSheet
    let labels: MailLabels
    let now: Date

    @State private var isCreatingLabel = false
    @State private var actionError: (any Error)?

    var body: some View {
        let custom = labels.custom
        let lists = sheet.mailingLists.value ?? []
        HUDList {
            Section {
                HUDPanel {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Total Unread")
                                .font(.hudMicro)
                                .tracking(1.5)
                                .textCase(.uppercase)
                                .foregroundStyle(Color.hudInkMuted)
                            Text("Across all labels")
                                .font(.hudBody)
                                .foregroundStyle(Color.hudInkBodyMuted)
                        }
                        Spacer(minLength: 8)
                        Text(labels.totalUnread, format: .number)
                            .font(.hudFigureXL)
                            .foregroundStyle(labels.totalUnread > 0 ? Color.hudAccent : Color.hudInkMuted)
                    }
                    .padding(.horizontal, HUDMetrics.gutter)
                    .padding(.vertical, 14)
                }
                .hudBareRow()
            } footer: {
                HUDFreshnessChip(sheet.labels, now: now)
                    .hudListFooter()
            }

            HUDListSection("Mailboxes") {
                ForEach(labels.mailboxes) { label in
                    NavigationLink(value: MailRoute.mailbox(.label(label.id))) {
                        MailboxRow(name: MailText.mailboxName(id: label.id, name: label.name) ?? label.name,
                                   unread: label.unreadCount) {
                            Image(systemName: MailText.symbol(ofMailbox: label.id))
                                .font(.system(size: 17))
                                .foregroundStyle(Color.hudAccent)
                        }
                    }
                    .hudRowButton()
                }
            }

            HUDListSection {
                ForEach(custom) { label in
                    labelRow(label)
                }
                if sheet.hasOrganizeScope {
                    HUDAddRow(title: "New Label…") { isCreatingLabel = true }
                }
            } header: {
                HUDSectionHeader(Text("Labels · \(custom.count)"))
            } footer: {
                HUDFootnote("Swipe a label to delete it; its mail keeps its other labels. A label holds up to 40 characters and one of EVE’s 18 colours.")
            }

            if !lists.isEmpty {
                HUDListSection {
                    ForEach(lists) { list in
                        NavigationLink(value: MailRoute.mailbox(.mailingList(list.id))) {
                            MailboxRow(name: list.name, unread: 0) {
                                Image(systemName: MailText.mailingListSymbol)
                                    .font(.system(size: 17))
                                    .foregroundStyle(Color.hudAccent)
                            }
                        }
                        .hudRowButton()
                    }
                } header: {
                    HUDSectionHeader(Text("Mailing Lists · \(lists.count)"))
                } footer: {
                    HUDFootnote("EVE does not count unread mail per mailing list. Join or leave lists in the EVE client.")
                }
            }
        }
        .sheet(isPresented: $isCreatingLabel) {
            MailNewLabelSheet(sheet: sheet)
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

    @ViewBuilder
    private func labelRow(_ label: MailLabel) -> some View {
        let link = NavigationLink(value: MailRoute.mailbox(.label(label.id))) {
            MailboxRow(name: label.name, unread: label.unreadCount) {
                HUDColorDot(color: MailText.color(ofLabel: label.color), size: 10)
            }
        }
        .hudRowButton()
        if sheet.hasOrganizeScope {
            HUDSwipeRow(title: "Delete", onRemove: { delete(label) }) { link }
        } else {
            link
        }
    }

    private func delete(_ label: MailLabel) {
        Task {
            do {
                try await sheet.deleteLabel(label.id)
            } catch {
                actionError = error
            }
        }
    }
}

/// One mailbox, label or mailing list: its mark, its name, what is unread in it.
private struct MailboxRow<Mark: View>: View {
    let name: String
    let unread: Int
    @ViewBuilder var mark: Mark

    var body: some View {
        HStack(spacing: 12) {
            mark
                .frame(width: 24)
                .accessibilityHidden(true)
            Text(verbatim: name)
                .font(HUDFont.display(15, weight: .semibold, relativeTo: .body))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            if unread > 0 {
                Text(unread, format: .number)
                    .font(HUDFont.mono(13, weight: .semibold, relativeTo: .subheadline))
                    .foregroundStyle(Color.hudAccent)
                    .accessibilityLabel(Text("\(unread) unread"))
            }
            HUDChevron()
        }
        .hudRow()
    }
}
