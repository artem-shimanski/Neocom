import ESIKit
import Foundation
import MailKit
import Observation

/// The loaded headers of one `MailHeaderSource` as stored in `ESICache`, with sender and
/// recipient names.
nonisolated struct ESIMailHeaders: Codable, Sendable, Hashable {
    var list: MailHeaderList
    /// Senders and recipients by id. Mailing lists are not included: `/universe/names` cannot
    /// resolve them (see `MailSheet.mailingLists`).
    var names: [Int64: ESIEntityName]
}

/// A mail body with sender and recipient names.
nonisolated struct ESIMailMessage: Codable, Sendable, Hashable {
    var message: MailMessage
    var names: [Int64: ESIEntityName]
}

/// The character's contacts that can receive mail, with names.
nonisolated struct ESIMailContacts: Codable, Sendable, Hashable {
    var contacts: [MailContact]
    var names: [Int64: ESIEntityName]
}

/// A character's EVE mail: labels, mailing lists, mailbox headers, bodies, and sending.
///
/// The only owner of `/characters/{id}/mail` (GET, POST), `/characters/{id}/mail/{mail_id}`
/// (GET, PUT, DELETE), `/characters/{id}/mail/labels` (GET, POST),
/// `/characters/{id}/mail/labels/{label_id}` (DELETE), `/characters/{id}/mail/lists`,
/// `/characters/{id}/contacts` (GET), `/characters/{id}/search` and `/characters/{id}/cspa`.
///
/// Mutations are optimistic: snapshots change at once through `replace(_:)` (so a stale answer
/// in flight cannot undo them; ESI caches mail for 30 seconds) and are restored on failure
/// before the error is rethrown.
@Observable
@MainActor
final class MailSheet {
    private static let labelsTTL: TimeInterval = 60
    private static let listsTTL: TimeInterval = 300
    private static let headersTTL: TimeInterval = 60
    private static let contactsTTL: TimeInterval = 300
    /// A mail body never changes.
    private static let messageTTL: TimeInterval = 90 * 86_400
    /// Per-mail and per-mailbox files older than this are deleted on init.
    private static let perItemRetention: TimeInterval = 90 * 86_400
    private static let messagePrefix = "mail-message-"
    private static let headersPrefix = "mail-headers-"
    /// Maximum number of search queries whose results are kept.
    private static let searchMemory = 32

    let characterID: Int64
    /// `esi-mail.read_mail.v1`: labels, lists, headers and bodies.
    let hasReadScope: Bool
    /// `esi-mail.organize_mail.v1`: read state, labels, deleting mail and labels.
    let hasOrganizeScope: Bool
    /// `esi-mail.send_mail.v1`.
    let hasSendScope: Bool
    /// `esi-characters.read_contacts.v1`: contact suggestions and the CSPA charge.
    let hasContactsScope: Bool
    /// `esi-search.search_structures.v1`: `/characters/{id}/search`.
    let hasSearchScope: Bool

    /// Labels with unread counts, and the unread total.
    private(set) var labels: ESISnapshot<MailLabels>
    private(set) var mailingLists: ESISnapshot<[MailingList]>
    /// Contacts that can receive mail; fetched on the first suggestions request.
    private(set) var contacts: ESISnapshot<ESIMailContacts>
    /// Sources whose next page `loadOlder(in:)` is loading.
    private(set) var loadingOlder: Set<MailHeaderSource> = []

    @ObservationIgnored private let client: Client
    @ObservationIgnored private let memory: LookupMemory
    @ObservationIgnored private var headerSnapshots: [MailHeaderSource: ESISnapshot<ESIMailHeaders>] = [:]
    @ObservationIgnored private var messageSnapshots: [Int64: ESISnapshot<ESIMailMessage>] = [:]
    @ObservationIgnored private var searchResults: [String: [MailRecipient]] = [:]
    @ObservationIgnored private var isInvalidated = false

    init(characterID: Int64, client: Client, scopes: (String) -> Bool) {
        self.characterID = characterID
        self.client = client
        hasReadScope = scopes(SSOConfiguration.Scope.mailRead)
        hasOrganizeScope = scopes(SSOConfiguration.Scope.mailOrganize)
        hasSendScope = scopes(SSOConfiguration.Scope.mailSend)
        hasContactsScope = scopes(SSOConfiguration.Scope.contactsRead)
        hasSearchScope = scopes(SSOConfiguration.Scope.search)
        let memory = LookupMemory()
        self.memory = memory
        let cache = ESICache()
        let cutoff = Date.now.addingTimeInterval(-Self.perItemRetention)
        cache.removeFiles(of: .character(characterID), prefix: Self.messagePrefix, writtenBefore: cutoff)
        cache.removeFiles(of: .character(characterID), prefix: Self.headersPrefix, writtenBefore: cutoff)

        labels = ESISnapshot(kind: "mail-labels", characterID: characterID, ttl: Self.labelsTTL, cache: cache) {
            MailLabels(try await client.mailLabels(characterID: characterID))
        }
        mailingLists = ESISnapshot(kind: "mail-lists", characterID: characterID, ttl: Self.listsTTL, cache: cache) {
            try await client.mailingLists(characterID: characterID)
                .map { MailingList(id: $0.mailingListId, name: $0.name) }
                .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        }
        contacts = ESISnapshot(kind: "mail-contacts", characterID: characterID, ttl: Self.contactsTTL, cache: cache) {
            let payload = try await ESIParallel.allPages { page in
                let answer = try await client.contacts(characterID: characterID, page: page)
                return (answer.contacts, answer.pages)
            }
            var seen: Set<MailRecipient> = []
            let contacts = payload.compactMap(MailContact.init).filter { seen.insert($0.recipient).inserted }
            let names = await LookupMemory.names(contacts.map(\.recipient.id), memory: memory, client: client)
            return ESIMailContacts(contacts: contacts, names: names)
        }
        memory.seed(names: contacts.value?.names ?? [:])
    }

    /// The account lacks the read scope, or ESI answered `403`.
    var isMissingScope: Bool { !hasReadScope || labels.state.isForbidden }

    /// `nil` until the labels are loaded.
    var unreadSummary: MailUnreadSummary? { labels.value.map(MailUnreadSummary.init) }

    /// Refreshes the labels if missing or past their TTL.
    func ensureLabelsFresh() async {
        guard hasReadScope else { return }
        await labels.ensureFresh()
    }

    /// Refreshes the labels and mailing lists if missing or past their TTL.
    func ensureFresh() async {
        guard hasReadScope else { return }
        async let labels: Void = labels.ensureFresh()
        async let lists: Void = mailingLists.ensureFresh()
        _ = await (labels, lists)
    }

    /// Refreshes the labels and mailing lists; header snapshots are refreshed separately.
    func refresh() async {
        guard hasReadScope else { return }
        async let labels: Void = labels.refresh()
        async let lists: Void = mailingLists.refresh()
        _ = await (labels, lists)
    }

    // MARK: - Headers

    /// The headers of the mailbox's source. For a mailing list this is the unfiltered list;
    /// filter with `Mailbox.contains(_:)`.
    func headers(in mailbox: Mailbox) -> ESISnapshot<ESIMailHeaders> {
        headers(for: mailbox.source)
    }

    /// The headers of one source; the same snapshot for the same source on every call. A
    /// refresh refetches the first page and keeps older pages.
    func headers(for source: MailHeaderSource) -> ESISnapshot<ESIMailHeaders> {
        if let snapshot = headerSnapshots[source] { return snapshot }
        let client = client
        let characterID = characterID
        let memory = memory
        let hasReadScope = hasReadScope
        let snapshot = ESISnapshot<ESIMailHeaders>(kind: "\(Self.headersPrefix)\(source.key)", characterID: characterID,
                                                   ttl: Self.headersTTL, cache: ESICache()) { [weak self] in
            guard hasReadScope else { throw ESIError.http(status: 403, message: nil) }
            let page = try await client.mailHeaders(characterID: characterID, labels: source.labelFilter, lastMailID: nil)
                .compactMap(MailHeader.init)
            // Read after the answer arrives, so older pages appended meanwhile are kept.
            let previous = await self?.loadedHeaders(source)
            let list = (previous?.list ?? MailHeaderList()).refreshed(withFirstPage: page)
            let names = await LookupMemory.names(list.headers.flatMap(\.nameableIDs), memory: memory, client: client)
            return ESIMailHeaders(list: list, names: names)
        }
        memory.seed(names: snapshot.value?.names ?? [:])
        headerSnapshots[source] = snapshot
        return snapshot
    }

    private func loadedHeaders(_ source: MailHeaderSource) -> ESIMailHeaders? {
        headerSnapshots[source]?.value
    }

    /// Appends the next 50 older headers of `source`; no-op when there are none or a page is
    /// loading. Does not change the snapshot's `fetchedAt`.
    func loadOlder(in source: MailHeaderSource) async throws {
        let snapshot = headers(for: source)
        guard hasReadScope, !loadingOlder.contains(source),
              let cursor = snapshot.value?.list.nextCursor else { return }
        loadingOlder.insert(source)
        defer { loadingOlder.remove(source) }
        let page = try await client.mailHeaders(characterID: characterID, labels: source.labelFilter, lastMailID: cursor)
            .compactMap(MailHeader.init)
        let names = await LookupMemory.names(page.flatMap(\.nameableIDs), memory: memory, client: client)
        guard let current = snapshot.value else { return }
        snapshot.amend(ESIMailHeaders(list: current.list.appending(olderPage: page),
                                      names: current.names.merging(names) { _, new in new }))
    }

    // MARK: - Messages

    /// A mail with its body; the same snapshot for the same mail on every call. Its `isRead`
    /// and labels are as fetched; `header(of:)` has the current ones.
    func message(_ mailID: Int64) -> ESISnapshot<ESIMailMessage> {
        if let snapshot = messageSnapshots[mailID] { return snapshot }
        let client = client
        let characterID = characterID
        let memory = memory
        let snapshot = ESISnapshot<ESIMailMessage>(kind: "\(Self.messagePrefix)\(mailID)", characterID: characterID,
                                                   ttl: Self.messageTTL, cache: ESICache()) {
            let payload = try await client.mail(characterID: characterID, mailID: mailID)
            let message = MailMessage(mailID: mailID, payload)
            let names = await LookupMemory.names(message.header.nameableIDs, memory: memory, client: client)
            return ESIMailMessage(message: message, names: names)
        }
        memory.seed(names: snapshot.value?.names ?? [:])
        messageSnapshots[mailID] = snapshot
        return snapshot
    }

    /// The current header of a mail, from a loaded header list or else from its body.
    func header(of mailID: Int64) -> MailHeader? {
        for snapshot in headerSnapshots.values {
            if let header = snapshot.value?.list.header(mailID) { return header }
        }
        return messageSnapshots[mailID]?.value?.message.header
    }

    /// The name of a sender or recipient: one of the character's mailing lists, or a name
    /// resolved so far.
    func name(of recipient: MailRecipient) -> String? {
        if recipient.kind == .mailingList {
            return mailingLists.value?.first { $0.id == recipient.id }?.name
        }
        return memory.names[recipient.id]?.name
    }

    // MARK: - Mutations

    func setRead(_ isRead: Bool, mailID: Int64) async throws {
        guard hasOrganizeScope else { return }
        let old = header(of: mailID)
        if let old, old.isRead == isRead { return }
        var new = old
        new?.isRead = isRead
        apply(mailID, from: old, to: new)
        do {
            try await client.updateMail(characterID: characterID, mailID: mailID, read: isRead, labels: nil)
        } catch {
            apply(mailID, from: new, to: old)
            throw error
        }
    }

    /// Replaces the full set of a mail's labels (at most 25); ESI's `PUT` replaces, not adds.
    func setLabels(_ labelIDs: [Int64], mailID: Int64) async throws {
        guard hasOrganizeScope else { return }
        var unique: [Int64] = []
        for id in labelIDs where !unique.contains(id) { unique.append(id) }
        // Truncated before the optimistic update, so the UI matches the request.
        unique = Array(unique.prefix(25))
        let old = header(of: mailID)
        var new = old
        new?.labels = unique
        apply(mailID, from: old, to: new)
        do {
            try await client.updateMail(characterID: characterID, mailID: mailID, read: nil, labels: unique)
        } catch {
            apply(mailID, from: new, to: old)
            throw error
        }
    }

    func delete(mailID: Int64) async throws {
        guard hasOrganizeScope else { return }
        let old = header(of: mailID)
        apply(mailID, from: old, to: nil)
        do {
            try await client.deleteMail(characterID: characterID, mailID: mailID)
            messageSnapshots[mailID]?.invalidate()
            messageSnapshots[mailID] = nil
        } catch {
            apply(mailID, from: nil, to: old)
            throw error
        }
    }

    /// Creates a label (name up to 40 characters, color from `MailLabelColor.all`) and adds it
    /// to `labels`.
    @discardableResult
    func createLabel(name: String, color: String = MailLabelColor.default) async throws -> MailLabel {
        let name = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(MailLabel.maxNameLength))
        let color = MailLabelColor.isAllowed(color) ? color.lowercased() : MailLabelColor.default
        let id = try await client.createMailLabel(characterID: characterID, name: name, color: color)
        let label = MailLabel(id: id, name: name, color: color, unreadCount: 0)
        if var value = labels.value {
            value.labels.removeAll { $0.id == id }
            value.labels.append(label)
            labels.replace(value)
        }
        return label
    }

    /// Deletes a player label; built-in labels cannot be deleted.
    func deleteLabel(_ labelID: Int64) async throws {
        guard hasOrganizeScope, !MailLabelID.isWellKnown(labelID) else { return }
        let previousLabels = labels.value
        let previousHeaders = headerSnapshots.compactMapValues(\.value)
        if var value = previousLabels {
            value.labels.removeAll { $0.id == labelID }
            labels.replace(value)
        }
        for (source, snapshot) in headerSnapshots {
            guard source != .label(labelID), var value = snapshot.value else { continue }
            value.list = value.list.mapping { header in
                var header = header
                header.labels.removeAll { $0 == labelID }
                return header
            }
            snapshot.replace(value)
        }
        let labelHeaders = headerSnapshots[.label(labelID)]
        headerSnapshots[.label(labelID)] = nil
        do {
            try await client.deleteMailLabel(characterID: characterID, labelID: labelID)
            labelHeaders?.invalidate()
        } catch {
            if let previousLabels { labels.replace(previousLabels) }
            headerSnapshots[.label(labelID)] = labelHeaders
            for (source, value) in previousHeaders where source != .label(labelID) {
                headerSnapshots[source]?.replace(value)
            }
            throw error
        }
    }

    /// Sends a draft. On `.needsApproval(cost)`, call again with `approvedCost: cost` once the
    /// pilot accepts the CSPA fee. The mail appears in Sent on that mailbox's next refresh.
    func send(_ draft: MailDraft, approvedCost: Int64 = 0) async -> MailSendOutcome {
        guard hasSendScope else { return .failed(message: nil) }
        guard draft.canSend else { return .failed(message: nil) }
        do {
            let id = try await client.sendMail(characterID: characterID,
                                               recipients: draft.recipients.map(\.postPayload),
                                               subject: draft.subject,
                                               body: draft.encodedBody,
                                               approvedCost: max(0, approvedCost))
            return .sent(mailID: id)
        } catch let ESIError.http(status, message) {
            switch MailCSPA.charge(status: status, message: message) {
            case .none:
                return .failed(message: message)
            case let .required(cost):
                // Prefer `/cspa`; a number parsed from the error text is a fallback and is
                // ignored if it matches a recipient id.
                let named = cost.flatMap { cost in draft.recipients.contains { $0.id == cost } ? nil : cost }
                return .needsApproval(cost: await cspaCharge(for: draft.recipients) ?? named)
            }
        } catch {
            return .failed(message: error.localizedDescription)
        }
    }

    /// The CSPA fee for the character recipients from `/characters/{id}/cspa`, or `nil`.
    private func cspaCharge(for recipients: [MailRecipient]) async -> Int64? {
        let characters = Array(Set(recipients.filter { $0.kind == .character }.map(\.id))).sorted().prefix(100)
        guard hasContactsScope, !characters.isEmpty,
              let charge = try? await client.cspaCharge(characterID: characterID, targets: Array(characters)),
              charge > 0 else { return nil }
        return MailCSPA.approvedCost(charge)
    }

    // MARK: - Suggestions

    /// Recipient suggestions for `query`: contacts, mailing lists, then ESI search for
    /// characters, corporations and alliances (from three characters). Failed parts are
    /// omitted. With `searching` false, only contacts and lists are matched.
    func suggestions(for query: String, excluding: Set<MailRecipient> = [], searching: Bool = true) async -> [MailSuggestion] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return [] }
        async let contactsDone: Void = hasContactsScope ? contacts.ensureFresh() : ()
        async let listsDone: Void = hasReadScope ? mailingLists.ensureFresh() : ()
        let found = searching ? await search(trimmed) : []
        _ = await (contactsDone, listsDone)
        let foundNames = await LookupMemory.names(found.map(\.id), memory: memory, client: client)
        var names: [Int64: String] = [:]
        for (id, entity) in (contacts.value?.names ?? [:]).merging(foundNames, uniquingKeysWith: { _, new in new }) {
            names[id] = entity.name
        }
        return MailSuggestions.make(query: trimmed,
                                    contacts: contacts.value?.contacts ?? [],
                                    mailingLists: mailingLists.value ?? [],
                                    searchResults: found,
                                    names: names,
                                    excluding: excluding)
    }

    /// ESI search for one kind (character, corporation or alliance), with names, in ESI's
    /// order. Used by pickers outside mail, such as `ZKillboardSheet`. Empty for mailing lists,
    /// without the scope, for fewer than three characters, or on failure.
    func searchEntities(_ query: String, kind: MailRecipientKind) async -> [(recipient: MailRecipient, name: String)] {
        let query = query.trimmingCharacters(in: .whitespaces)
        guard kind != .mailingList, hasSearchScope, query.count >= MailSuggestions.minimumSearchLength else { return [] }
        let key = "\(kind.rawValue):\(query.lowercased())"
        let found: [MailRecipient]
        if let cached = searchResults[key] {
            found = cached
        } else {
            let category: Operations.GetCharactersCharacterIdSearch.Input.Query.CategoriesPayloadPayload = switch kind {
            case .corporation: .corporation
            case .alliance: .alliance
            default: .character
            }
            guard let answer = try? await client.searchMailRecipients(characterID: characterID, text: query,
                                                                     categories: [category]) else { return [] }
            let ids = switch kind {
            case .corporation: answer.corporation ?? []
            case .alliance: answer.alliance ?? []
            default: answer.character ?? []
            }
            found = ids.prefix(Self.pickerSearchLimit).map { MailRecipient(id: $0, kind: kind) }
            if searchResults.count >= Self.searchMemory { searchResults.removeAll() }
            searchResults[key] = found
        }
        let names = await LookupMemory.names(found.map(\.id), memory: memory, client: client)
        return found.compactMap { recipient in names[recipient.id].map { (recipient, $0.name) } }
    }

    /// ESI returns up to 500 ids per category.
    private static let pickerSearchLimit = 100

    private func search(_ query: String) async -> [MailRecipient] {
        guard hasSearchScope, query.count >= MailSuggestions.minimumSearchLength else { return [] }
        let key = query.lowercased()
        if let cached = searchResults[key] { return cached }
        guard let answer = try? await client.searchMailRecipients(characterID: characterID, text: query) else { return [] }
        // ESI returns up to 500 per category; only the first few are useful.
        let found = (answer.character ?? []).prefix(20).map { MailRecipient(id: $0, kind: .character) }
            + (answer.corporation ?? []).prefix(10).map { MailRecipient(id: $0, kind: .corporation) }
            + (answer.alliance ?? []).prefix(10).map { MailRecipient(id: $0, kind: .alliance) }
        if searchResults.count >= Self.searchMemory { searchResults.removeAll() }
        searchResults[key] = found
        return found
    }

    // MARK: - Local changes

    /// Applies one mail's change to every snapshot holding it: header lists (`new == nil`
    /// removes it), the body and the unread counts. Reverted by swapping `old` and `new`.
    private func apply(_ mailID: Int64, from old: MailHeader?, to new: MailHeader?) {
        guard !isInvalidated else { return }
        for (source, snapshot) in headerSnapshots {
            guard var value = snapshot.value else { continue }
            let list: MailHeaderList = if let new {
                value.list.updating(new, belongs: source.lists(new))
            } else {
                value.list.removing(mailID)
            }
            guard list != value.list else { continue }
            value.list = list
            snapshot.replace(value)
        }
        if let new, let snapshot = messageSnapshots[mailID], var value = snapshot.value {
            value.message.header.isRead = new.isRead
            value.message.header.labels = new.labels
            snapshot.replace(value)
        }
        if let value = labels.value, old != nil || new != nil {
            let adjusted = value.adjusting(from: old, to: new)
            if adjusted != value { labels.replace(adjusted) }
        }
    }

    /// Stops all disk writes; called by `AccountStore` when it drops the sheet.
    func invalidate() {
        isInvalidated = true
        labels.invalidate()
        mailingLists.invalidate()
        contacts.invalidate()
        headerSnapshots.values.forEach { $0.invalidate() }
        messageSnapshots.values.forEach { $0.invalidate() }
    }
}

// MARK: - ESI → MailKit

nonisolated extension MailLabels {
    init(_ payload: Components.Schemas.CharactersCharacterIdMailLabelsGet) {
        let labels = (payload.labels ?? []).compactMap { label -> MailLabel? in
            guard let id = label.labelId else { return nil }
            return MailLabel(id: id,
                             name: label.name ?? MailLabelID.defaultName(of: id) ?? "",
                             color: label.color?.rawValue,
                             unreadCount: Int(clamping: label.unreadCount ?? 0))
        }
        self.init(labels: labels, totalUnread: Int(clamping: payload.totalUnreadCount ?? 0))
    }
}

nonisolated extension MailHeader {
    init?(_ payload: Components.Schemas.CharactersCharacterIdMailGetPayload) {
        guard let id = payload.mailId else { return nil }
        self.init(id: id,
                  from: payload.from ?? 0,
                  subject: payload.subject ?? "",
                  date: payload.timestamp ?? .distantPast,
                  isRead: payload.isRead ?? false,
                  labels: payload.labels ?? [],
                  recipients: (payload.recipients ?? []).map {
                      MailRecipient(id: $0.recipientId, kind: MailRecipientKind(rawValue: $0.recipientType.rawValue) ?? .character)
                  })
    }
}

nonisolated extension MailMessage {
    init(mailID: Int64, _ payload: Components.Schemas.CharactersCharacterIdMailMailIdGet) {
        let header = MailHeader(id: mailID,
                                from: payload.from ?? 0,
                                subject: payload.subject ?? "",
                                date: payload.timestamp ?? .distantPast,
                                isRead: payload.read ?? false,
                                labels: payload.labels ?? [],
                                recipients: (payload.recipients ?? []).map {
                                    MailRecipient(id: $0.recipientId,
                                                  kind: MailRecipientKind(rawValue: $0.recipientType.rawValue) ?? .character)
                                })
        self.init(header: header, body: payload.body ?? "")
    }
}

nonisolated extension MailContact {
    /// `nil` for a faction, which cannot receive mail.
    init?(_ payload: Components.Schemas.CharactersCharacterIdContactsGetPayload) {
        let kind: MailRecipientKind
        switch payload.contactType {
        case .character: kind = .character
        case .corporation: kind = .corporation
        case .alliance: kind = .alliance
        case .faction: return nil
        }
        self.init(recipient: MailRecipient(id: payload.contactId, kind: kind), standing: payload.standing)
    }
}

nonisolated extension MailRecipient {
    var postPayload: Operations.PostCharactersCharacterIdMail.Input.Body.JsonPayload.RecipientsPayloadPayload {
        .init(recipientId: id, recipientType: .init(rawValue: kind.rawValue) ?? .character)
    }
}
