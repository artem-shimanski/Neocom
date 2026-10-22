import Foundation

// A character's EVE mail: `/characters/{id}/mail` (headers, 50 a page, newest first),
// `/characters/{id}/mail/{mail_id}` (one mail with its body), `/characters/{id}/mail/labels`
// (labels with unread counts) and `/characters/{id}/mail/lists` (mailing lists the character
// is on). Plain data, independent of the generated ESI records; cached on disk as is.

/// Who a mail can be addressed to: ESI's `recipient_type`.
public enum MailRecipientKind: String, Codable, Sendable, Hashable, CaseIterable {
    case character
    case corporation
    case alliance
    case mailingList = "mailing_list"
}

/// One addressee of a mail.
public struct MailRecipient: Codable, Sendable, Hashable {
    public var id: Int64
    public var kind: MailRecipientKind

    public init(id: Int64, kind: MailRecipientKind) {
        self.id = id
        self.kind = kind
    }

    /// At most this many recipients on one mail (ESI's `maxItems`).
    public static let maxCount = 50
}

/// One mail as the header list carries it: no body.
public struct MailHeader: Codable, Sendable, Hashable, Identifiable {
    public var id: Int64
    /// The sender: a character's id. For mail sent by the game (a corporation or an alliance
    /// announcing something), the id of whatever sent it.
    public var from: Int64
    public var subject: String
    public var date: Date
    public var isRead: Bool
    /// Label ids, well-known ones (`MailLabelID`) and the player's own.
    public var labels: [Int64]
    public var recipients: [MailRecipient]

    public init(id: Int64, from: Int64, subject: String, date: Date, isRead: Bool,
                labels: [Int64], recipients: [MailRecipient]) {
        self.id = id
        self.from = from
        self.subject = subject
        self.date = date
        self.isRead = isRead
        self.labels = labels
        self.recipients = recipients
    }

    /// Ids worth naming through `/universe/names`: the sender, and every recipient that is not
    /// a mailing list (lists are named only by `/mail/lists`, and only the character's own).
    public var nameableIDs: [Int64] {
        [from] + recipients.filter { $0.kind != .mailingList }.map(\.id)
    }
}

/// One mail opened: the header fields and the body, as EVE markup (`MailMarkup` parses it).
///
/// The body never changes once sent; `isRead` and `labels` are what they were when the mail
/// was fetched — the header list is where their current value lives.
public struct MailMessage: Codable, Sendable, Hashable, Identifiable {
    public var header: MailHeader
    public var body: String

    public var id: Int64 { header.id }

    public init(header: MailHeader, body: String) {
        self.header = header
        self.body = body
    }
}

/// EVE's built-in labels. Every character has them; their names come from the game.
public enum MailLabelID {
    public static let inbox: Int64 = 1
    public static let sent: Int64 = 2
    public static let corporation: Int64 = 4
    public static let alliance: Int64 = 8

    /// The four, in the order the mailboxes screen lists them.
    public static let wellKnown: [Int64] = [inbox, sent, corporation, alliance]

    public static func isWellKnown(_ id: Int64) -> Bool { wellKnown.contains(id) }

    /// The game's names for the four, for when ESI answers a label without one.
    public static func defaultName(of id: Int64) -> String? {
        switch id {
        case inbox: "Inbox"
        case sent: "Sent"
        case corporation: "[Corp]"
        case alliance: "[Alliance]"
        default: nil
        }
    }
}

/// The 18 colours EVE allows for a label (the enum of `POST /mail/labels`'s `color`), in the
/// order of the game's palette rows. `#ffffff` is the default.
public enum MailLabelColor {
    public static let all: [String] = [
        "#ffffff", "#ffff01", "#ff6600", "#fe0000", "#9a0000", "#660066",
        "#0000fe", "#0099ff", "#01ffff", "#00ff33", "#349800", "#006634",
        "#666666", "#999999", "#e6e6e6", "#ffffcd", "#99ffff", "#ccff9a",
    ]
    public static let `default` = "#ffffff"

    /// Whether ESI accepts `hex` for a new label (case-insensitive).
    public static func isAllowed(_ hex: String) -> Bool { all.contains(hex.lowercased()) }
}

/// One label, well-known or the player's own.
public struct MailLabel: Codable, Sendable, Hashable, Identifiable {
    public var id: Int64
    public var name: String
    /// `#rrggbb`, one of `MailLabelColor.all`; `nil` where ESI gave none.
    public var color: String?
    public var unreadCount: Int

    public init(id: Int64, name: String, color: String?, unreadCount: Int) {
        self.id = id
        self.name = name
        self.color = color
        self.unreadCount = unreadCount
    }

    public var isWellKnown: Bool { MailLabelID.isWellKnown(id) }

    /// At most this many characters in a label's name (ESI's `maxLength`).
    public static let maxNameLength = 40
}

/// `/mail/labels`: every label and the unread total. A mail can carry several labels, so the
/// total is not the sum of the per-label counts.
public struct MailLabels: Codable, Sendable, Hashable {
    public var labels: [MailLabel]
    public var totalUnread: Int

    public init(labels: [MailLabel], totalUnread: Int) {
        self.labels = labels
        self.totalUnread = totalUnread
    }

    /// Inbox, Sent, [Corp], [Alliance], in that order; one ESI did not list is still there,
    /// named by the game's default and with nothing unread.
    public var mailboxes: [MailLabel] {
        MailLabelID.wellKnown.map { id in
            labels.first { $0.id == id }
                ?? MailLabel(id: id, name: MailLabelID.defaultName(of: id) ?? "", color: nil, unreadCount: 0)
        }
    }

    /// The player's own labels, by name.
    public var custom: [MailLabel] {
        labels.filter { !$0.isWellKnown }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    public func label(_ id: Int64) -> MailLabel? { labels.first { $0.id == id } }

    /// The counts after one mail changed from `old` to `new` (`nil` for a mail that appears or
    /// disappears): an unread mail counts once in the total and once in each of its labels.
    /// Counts never drop below zero — ESI's own may already have caught up.
    public func adjusting(from old: MailHeader?, to new: MailHeader?) -> MailLabels {
        var result = self
        func add(_ header: MailHeader?, _ delta: Int) {
            guard let header, !header.isRead else { return }
            result.totalUnread = max(0, result.totalUnread + delta)
            for id in Set(header.labels) {
                if let index = result.labels.firstIndex(where: { $0.id == id }) {
                    result.labels[index].unreadCount = max(0, result.labels[index].unreadCount + delta)
                }
            }
        }
        add(old, -1)
        add(new, +1)
        return result
    }
}

/// A mailing list the character is on (`/mail/lists`). EVE does not count unread mail per list.
public struct MailingList: Codable, Sendable, Hashable, Identifiable {
    public var id: Int64
    public var name: String

    public init(id: Int64, name: String) {
        self.id = id
        self.name = name
    }
}

/// What a header list shows: one label's mail, or the mail sent to one mailing list.
public enum Mailbox: Codable, Sendable, Hashable {
    case label(Int64)
    case mailingList(Int64)

    public static let inbox = Mailbox.label(MailLabelID.inbox)
    public static let sent = Mailbox.label(MailLabelID.sent)

    /// The header list the mailbox is read from. `GET /mail` filters by label only, so every
    /// mailing list reads the unfiltered list and keeps the mail addressed to it.
    public var source: MailHeaderSource {
        switch self {
        case let .label(id): .label(id)
        case .mailingList: .all
        }
    }

    /// Whether `header` belongs in this mailbox.
    public func contains(_ header: MailHeader) -> Bool {
        switch self {
        case let .label(id): header.labels.contains(id)
        case let .mailingList(id): header.recipients.contains { $0.kind == .mailingList && $0.id == id }
        }
    }
}

/// One `GET /mail` stream: filtered by a label, or not filtered at all.
public enum MailHeaderSource: Codable, Sendable, Hashable {
    case label(Int64)
    case all

    /// The `labels` query of the request; `nil` for the unfiltered list.
    public var labelFilter: [Int64]? {
        switch self {
        case let .label(id): [id]
        case .all: nil
        }
    }

    /// A stable name for the source's cache file.
    public var key: String {
        switch self {
        case let .label(id): "label-\(id)"
        case .all: "all"
        }
    }

    /// Whether a mail with these labels is listed by this source.
    public func lists(_ header: MailHeader) -> Bool {
        switch self {
        case let .label(id): header.labels.contains(id)
        case .all: true
        }
    }
}

/// One of the character's contacts (`/characters/{id}/contacts`), as far as mail cares: who,
/// and how much the character likes them. Factions cannot receive mail and are left out.
public struct MailContact: Codable, Sendable, Hashable {
    public var recipient: MailRecipient
    public var standing: Double

    public init(recipient: MailRecipient, standing: Double) {
        self.recipient = recipient
        self.standing = standing
    }
}
