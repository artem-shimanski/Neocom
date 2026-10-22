import DogmaKit
import DogmaKitIO
import KillmailKit
import LiteRowUI
import MailKit
import SDEKit
import SwiftUI

/// One mail: subject, sender, recipients, when it was sent and its labels, then the body with
/// its links. Opening an unread mail marks it read. Delete, mark unread, reply, reply to all
/// and forward are in the bottom toolbar.
struct MailMessageView: View {
    let sheet: MailSheet
    let mailID: Int64
    let database: SDEDatabase

    var body: some View {
        let snapshot = sheet.message(mailID)
        Group {
            if let value = snapshot.value {
                MailMessageBody(sheet: sheet, mailID: mailID, message: value, database: database)
            } else if case let .failed(error) = snapshot.state {
                if error.isESIForbidden {
                    MailGrantAccessList()
                } else {
                    MailUnavailableList(error: error) { await snapshot.refresh() }
                }
            } else {
                ProgressView()
                    .controlSize(.large)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .hudScreen()
        .navigationBarTitleDisplayMode(.inline)
        .task { await snapshot.ensureFresh() }
    }
}

private struct MailMessageBody: View {
    let sheet: MailSheet
    let mailID: Int64
    let message: ESIMailMessage
    let database: SDEDatabase

    @Environment(\.dismiss) private var dismiss
    @Environment(FittingStore.self) private var fittingStore
    @Environment(AccountStore.self) private var accounts

    @State private var compose: MailComposeRequest?
    @State private var pushedType: DatabaseRoute?
    /// The kill report a card or a link opened.
    @State private var pushedKillmail: KillmailRef?
    /// The fit a fitting card opened, pushed into the editor — as from an assembled ship in
    /// Assets: a draft until the player changes or saves it.
    @State private var pushedFit: FittingRoute?
    @State private var pendingFitID: UUID?
    @State private var hasImportLosses = false
    @State private var actionError: (any Error)?
    @State private var isWorking = false

    /// The mail's read state and labels as they are now; the opened body has them as fetched.
    private var header: MailHeader { sheet.header(of: mailID) ?? message.message.header }

    private var fromName: String {
        MailText.name(of: header.from, names: message.names, sheet: sheet)
    }

    var body: some View {
        let header = header
        HUDList {
            HUDListSection {
                Text(verbatim: header.subject.isEmpty ? String(localized: "(No Subject)") : header.subject)
                    .font(.hudCardTitle)
                    .tracking(0.2)
                    .padding(.top, 16)
                    .padding(.bottom, 14)
                    .hudRow(HUDRowStyle(minHeight: 0, verticalPadding: 0))
                fromRow
                if !header.recipients.isEmpty {
                    recipientsRow(header.recipients)
                }
                HUDReadoutRow("Sent", value: MailKit.EVETime.dateTimeText(header.date))
                labelsRow(header)
            }

            HUDListSection {
                MailBodyView(markup: message.message.body)
                    .hudRow(HUDRowStyle(minHeight: 0, verticalPadding: 16))
            } header: {
                HUDSectionHeader("Message")
            } footer: {
                HUDFootnote("Links open inside Neocom where it can: items in the database, fittings in the Fitting Tool, kill reports in Killmails. Web links open in the browser; a link Neocom can’t open stays as text.")
            }
        }
        .environment(\.openURL, OpenURLAction(handler: open))
        .toolbar { toolbar }
        .task {
            // Opening an unread mail reads it; a refusal leaves it unread and says nothing —
            // the mail is on screen either way.
            if !self.header.isRead { try? await sheet.setRead(true, mailID: mailID) }
        }
        .navigationDestination(item: $pushedType) { route in
            route.destination
                .liteDatabase(database.database)
        }
        .navigationDestination(item: $pushedFit) { route in
            route.destination
                .liteDatabase(database.database)
        }
        .navigationDestination(item: $pushedKillmail) { ref in
            if let sheet = accounts.currentKillmails {
                KillmailReportView(sheet: sheet, ref: ref)
                    .liteDatabase(database.database)
            }
        }
        .mailCompose($compose, sheet: sheet)
        .alert("Not Everything Was Copied", isPresented: $hasImportLosses) {
            Button("Open Fit") {
                if let pendingFitID { pushedFit = .editor(pendingFitID) }
                pendingFitID = nil
            }
            Button("OK", role: .cancel) {
                if let pendingFitID { fittingStore.discardDraft(pendingFitID) }
                pendingFitID = nil
            }
        } message: {
            Text("Some items of this fitting are not in the database, are cargo or did not fit, and were left out.")
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

    // MARK: Header

    private var fromRow: some View {
        HStack(spacing: 12) {
            HUDInitialsAvatar(name: fromName, url: MailText.avatarURL(of: header.from, names: message.names))
            VStack(alignment: .leading, spacing: 2) {
                Text("From")
                    .font(.hudMicro)
                    .tracking(1.5)
                    .textCase(.uppercase)
                    .foregroundStyle(Color.hudInkMuted)
                Text(verbatim: fromName)
                    .font(HUDFont.display(16, weight: .semibold, relativeTo: .body))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .hudRow(HUDRowStyle(minHeight: 0, verticalPadding: 10))
        .accessibilityElement(children: .combine)
    }

    private func recipientsRow(_ recipients: [MailRecipient]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("To · \(recipients.count)")
                .font(.hudMicro)
                .tracking(1.5)
                .textCase(.uppercase)
                .foregroundStyle(Color.hudInkMuted)
            HUDWrapLayout(spacing: 6) {
                ForEach(recipients, id: \.self) { recipient in
                    HUDTokenChip(title: Text(verbatim: MailText.name(of: recipient, names: message.names, sheet: sheet)),
                                 systemImage: MailText.symbol(of: recipient.kind),
                                 kindLabel: MailText.title(of: recipient.kind))
                }
            }
        }
        .hudRow(HUDRowStyle(minHeight: 0, verticalPadding: 12))
    }

    private func labelsRow(_ header: MailHeader) -> some View {
        let all = sheet.labels.value
        let shown = header.labels.compactMap { all?.label($0) }
            .sorted { lhs, rhs in
                let left = MailLabelID.wellKnown.firstIndex(of: lhs.id) ?? .max
                let right = MailLabelID.wellKnown.firstIndex(of: rhs.id) ?? .max
                return left != right ? left < right : lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
        return HStack(spacing: 8) {
            HUDWrapLayout(spacing: 12, lineSpacing: 8) {
                ForEach(shown) { label in
                    HUDDotLabel(title: Text(verbatim: label.name), color: MailText.color(ofLabel: label.color), dotSize: 8)
                }
            }
            .font(.hudLabel)
            .tracking(1)
            .foregroundStyle(Color.hudInkBodyMuted)
            .frame(maxWidth: .infinity, alignment: .leading)
            if sheet.hasOrganizeScope, let all {
                labelsMenu(header, labels: all)
            }
        }
        .padding(.leading, HUDMetrics.gutter)
        .padding(.trailing, 10)
        .hudRow(HUDRowStyle(horizontalPadding: 0, minHeight: 56, verticalPadding: 10))
    }

    /// Well-known labels first, then the player's with their colours; each a toggle. Sent is
    /// the game's own and is not offered.
    private func labelsMenu(_ header: MailHeader, labels: MailLabels) -> some View {
        Menu {
            Section {
                ForEach(labels.mailboxes.filter { $0.id != MailLabelID.sent }) { label in
                    Toggle(MailText.mailboxName(id: label.id, name: label.name) ?? label.name, isOn: labelBinding(label.id, header: header))
                }
            }
            Section {
                ForEach(labels.custom) { label in
                    Toggle(isOn: labelBinding(label.id, header: header)) {
                        Label {
                            Text(verbatim: label.name)
                        } icon: {
                            Image(systemName: "circle.fill")
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(MailText.color(ofLabel: label.color))
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "tag")
                Text("Labels")
            }
            .font(.subheadline.weight(.medium))
        }
        .menuStyle(.button)
        .buttonStyle(.glass)
        .controlSize(.regular)
        .fixedSize()
    }

    private func labelBinding(_ id: Int64, header: MailHeader) -> Binding<Bool> {
        Binding {
            header.labels.contains(id)
        } set: { isOn in
            let current = self.header.labels
            let new = isOn ? current + [id] : current.filter { $0 != id }
            perform { try await sheet.setLabels(new, mailID: mailID) }
        }
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        if sheet.hasOrganizeScope {
            ToolbarItemGroup(placement: .bottomBar) {
                Button {
                    perform(thenDismiss: true) { try await sheet.delete(mailID: mailID) }
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                .disabled(isWorking)
                Button {
                    perform(thenDismiss: true) { try await sheet.setRead(false, mailID: mailID) }
                } label: {
                    Label("Mark as Unread", systemImage: "envelope.badge")
                }
                .disabled(isWorking)
            }
        }
        ToolbarSpacer(.flexible, placement: .bottomBar)
        ToolbarItemGroup(placement: .bottomBar) {
            Button {
                compose = MailComposeRequest(draft: MailDraft.reply(to: currentMessage, senderName: fromName).withLocalizedQuoteHeader(of: currentMessage, senderName: fromName))
            } label: {
                Label("Reply", systemImage: "arrowshape.turn.up.left")
            }
            Button {
                compose = MailComposeRequest(draft: MailDraft.replyAll(to: currentMessage, senderName: fromName,
                                                                         characterID: sheet.characterID)
                    .withLocalizedQuoteHeader(of: currentMessage, senderName: fromName))
            } label: {
                Label("Reply All", systemImage: "arrowshape.turn.up.left.2")
            }
            Button {
                compose = MailComposeRequest(draft: MailDraft.forward(currentMessage, senderName: fromName).withLocalizedQuoteHeader(of: currentMessage, senderName: fromName))
            } label: {
                Label("Forward", systemImage: "arrowshape.turn.up.right")
            }
        }
    }

    /// The opened mail with its current labels and read state.
    private var currentMessage: MailMessage {
        MailMessage(header: header, body: message.message.body)
    }

    private func perform(thenDismiss: Bool = false, _ action: @escaping () async throws -> Void) {
        isWorking = true
        Task {
            defer { isWorking = false }
            do {
                try await action()
                if thenDismiss { dismiss() }
            } catch {
                actionError = error
            }
        }
    }

    // MARK: Links

    private func open(_ url: URL) -> OpenURLAction.Result {
        switch MailLinkURL.target(of: url) {
        case let .type(id)?:
            pushedType = .type(TypeID(rawValue: UInt32(clamping: id)))
            return .handled
        case let .fitting(dna, name)?:
            openFitting(dna: dna, name: name)
            return .handled
        case let .killmail(id, hash)?:
            guard accounts.currentKillmails != nil else {
                // No character to open it under: zKillboard has every killmail too.
                return KillmailText.zKillboard(killID: id).map { .systemAction($0) } ?? .discarded
            }
            pushedKillmail = KillmailRef(id: id, hash: hash)
            return .handled
        case nil:
            return .systemAction
        }
    }

    /// The fitting as a draft in the Fitting Tool, the way an assembled ship from Assets opens:
    /// stored once the player changes or saves it, gone if the editor closes untouched.
    private func openFitting(dna: String, name: String?) {
        let catalog: TypeCatalog
        do {
            catalog = try TypeCatalog()
        } catch {
            actionError = CopyFittingError.catalogUnavailable
            return
        }
        // DNA names nothing: the resolver is never asked.
        let importer = FitImporter(resolver: DictionaryTypeResolver(types: [:]), catalog: catalog)
        let result = importer.load(dna, as: .dna)
        guard let document = result.documents.first, let shipTypeID = document.pilots.first?.ship?.type else {
            actionError = MailFittingError.unreadable
            return
        }
        let id = fittingStore.createDraft(shipTypeID: shipTypeID,
                                          name: name ?? String(localized: "Fitting from Mail"),
                                          document: document)
        if result.warnings.isEmpty {
            pushedFit = .editor(id)
        } else {
            pendingFitID = id
            hasImportLosses = true
        }
    }
}

nonisolated enum MailFittingError: LocalizedError {
    case unreadable

    var errorDescription: String? {
        switch self {
        case .unreadable: String(localized: "This fitting link names a ship that is not in the database.")
        }
    }
}
