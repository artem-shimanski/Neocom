import Foundation

// The header list of one mailbox: how pages of `GET /mail` add up, how the rows are grouped by
// day and how their date and recipients read. Every date is EVE time, which is UTC.

/// The loaded headers of one `MailHeaderSource`, newest first, with where the next page starts.
///
/// ESI answers 50 headers a page, newest first; the next page is asked with `last_mail_id` =
/// the oldest id loaded so far. A page of fewer than 50 is the last one.
public struct MailHeaderList: Codable, Sendable, Hashable {
    public static let pageSize = 50

    public private(set) var headers: [MailHeader]
    /// Whether ESI may have older mail than the oldest loaded: the last page asked was full.
    public private(set) var hasMore: Bool

    public init(headers: [MailHeader] = [], hasMore: Bool = false) {
        self.headers = Self.ordered(headers)
        self.hasMore = hasMore
    }

    /// The first page, on its own.
    public init(firstPage: [MailHeader]) {
        self.init(headers: firstPage, hasMore: firstPage.count >= Self.pageSize)
    }

    /// `last_mail_id` for the next page: the oldest id loaded. `nil` while there is nothing
    /// older to ask for.
    public var nextCursor: Int64? {
        guard hasMore else { return nil }
        return headers.map(\.id).min()
    }

    /// A fresh first page over what was loaded. Inside the range the page covers, the page is
    /// the truth — mail deleted or moved since disappears; older pages loaded before stay, and
    /// so does whether there is more beyond them. A page shorter than a full one is the whole
    /// list. A full page that does not reach what was loaded (more than a page of new mail
    /// since) starts over: kept, the older pages would leave a gap no cursor ever fills.
    public func refreshed(withFirstPage page: [MailHeader]) -> MailHeaderList {
        guard page.count >= Self.pageSize, let oldest = page.map(\.id).min(),
              headers.contains(where: { $0.id >= oldest }) else {
            return MailHeaderList(firstPage: page)
        }
        let older = headers.filter { $0.id < oldest }
        return MailHeaderList(headers: page + older, hasMore: older.isEmpty ? true : hasMore)
    }

    /// An older page appended: duplicates dropped (the list can shift between requests), the
    /// page's answer winning for a mail in both.
    public func appending(olderPage page: [MailHeader]) -> MailHeaderList {
        let ids = Set(page.map(\.id))
        return MailHeaderList(headers: headers.filter { !ids.contains($0.id) } + page,
                              hasMore: page.count >= Self.pageSize)
    }

    public func header(_ id: Int64) -> MailHeader? { headers.first { $0.id == id } }

    /// The list after one mail changed: replaced where it is; inserted when it now belongs
    /// here and falls inside the loaded range (newer than the oldest loaded, or everything is
    /// loaded); removed when it no longer belongs.
    public func updating(_ header: MailHeader, belongs: Bool) -> MailHeaderList {
        var copy = self
        copy.headers.removeAll { $0.id == header.id }
        if belongs {
            let inRange = !hasMore || (headers.map(\.id).min().map { header.id >= $0 } ?? false)
            if inRange || self.header(header.id) != nil {
                copy.headers = Self.ordered(copy.headers + [header])
            }
        }
        return copy
    }

    /// The list without one mail.
    public func removing(_ id: Int64) -> MailHeaderList {
        var copy = self
        copy.headers.removeAll { $0.id == id }
        return copy
    }

    /// Every header with `transform` applied — e.g. a deleted label stripped.
    public func mapping(_ transform: (MailHeader) -> MailHeader) -> MailHeaderList {
        var copy = self
        copy.headers = headers.map(transform)
        return copy
    }

    /// Newest first: by date, and by id between two of the same second. Duplicates by id keep
    /// the first occurrence.
    private static func ordered(_ headers: [MailHeader]) -> [MailHeader] {
        var seen: Set<Int64> = []
        return headers
            .filter { seen.insert($0.id).inserted }
            .sorted { $0.date != $1.date ? $0.date > $1.date : $0.id > $1.id }
    }
}

/// The day groups of a header list.
public enum MailDayGroup: Int, Sendable, Hashable, CaseIterable, Comparable {
    /// The same EVE day as now.
    case today
    /// The six EVE days before today.
    case thisWeek
    /// Anything older. A mail dated after now — a clock off by a minute — counts as today.
    case earlier

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }

    public static func of(_ date: Date, now: Date) -> MailDayGroup {
        let days = EVETime.daysBetween(date, and: now)
        switch days {
        case 0: return .today
        case 1...6: return .thisWeek
        default: return days < 0 ? .today : .earlier
        }
    }

    /// `headers` in groups, in group order and in the order given within each group; empty
    /// groups left out.
    public static func grouped(_ headers: [MailHeader], now: Date) -> [(group: MailDayGroup, headers: [MailHeader])] {
        let byGroup = Dictionary(grouping: headers) { of($0.date, now: now) }
        return allCases.compactMap { group in
            byGroup[group].map { (group, $0) }
        }
    }
}

/// How a row prints its date: the time today, `YESTERDAY`, the month and day this year, the
/// whole date before that.
public enum MailDateText: Sendable, Hashable, CustomStringConvertible {
    /// `11:42`.
    case time(hour: Int, minute: Int)
    /// `YESTERDAY`.
    case yesterday
    /// `10.14`.
    case monthDay(month: Int, day: Int)
    /// `2025.12.31`.
    case date(year: Int, month: Int, day: Int)

    public init(_ date: Date, now: Date) {
        let parts = EVETime.calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let days = EVETime.daysBetween(date, and: now)
        let thisYear = EVETime.calendar.component(.year, from: now)
        if days <= 0 {
            self = .time(hour: parts.hour ?? 0, minute: parts.minute ?? 0)
        } else if days == 1 {
            self = .yesterday
        } else if parts.year == thisYear {
            self = .monthDay(month: parts.month ?? 1, day: parts.day ?? 1)
        } else {
            self = .date(year: parts.year ?? 0, month: parts.month ?? 1, day: parts.day ?? 1)
        }
    }

    public var description: String {
        switch self {
        case let .time(hour, minute): String(format: "%02d:%02d", hour, minute)
        case .yesterday: "YESTERDAY"
        case let .monthDay(month, day): String(format: "%02d.%02d", month, day)
        case let .date(year, month, day): String(format: "%04d.%02d.%02d", year, month, day)
        }
    }
}

/// Who a row says the mail went to.
public enum MailRecipientsLine: Sendable, Hashable {
    /// `TO YOU`, `TO YOU + 11`: the character is a direct recipient, with this many others.
    case you(others: Int)
    /// `TO RENS TRADERS + 2`: the character got it through `first` — their corporation,
    /// alliance or a mailing list — or sent it; `first` is the recipient to name.
    case recipient(MailRecipient, others: Int)
    /// No recipients at all.
    case nobody

    /// The line for a mail `characterID` has. Without the character among the recipients,
    /// the one to name is the first of: the corporation, the alliance (the ids, when known),
    /// a mailing list, whatever comes first.
    public init(_ header: MailHeader, characterID: Int64,
                corporationID: Int64? = nil, allianceID: Int64? = nil) {
        let recipients = header.recipients
        guard !recipients.isEmpty else {
            self = .nobody
            return
        }
        if recipients.contains(MailRecipient(id: characterID, kind: .character)) {
            self = .you(others: recipients.count - 1)
            return
        }
        let preferred = recipients.first { $0.kind == .corporation && $0.id == corporationID }
            ?? recipients.first { $0.kind == .alliance && $0.id == allianceID }
            ?? recipients.first { $0.kind == .mailingList }
            ?? recipients[0]
        self = .recipient(preferred, others: recipients.count - 1)
    }
}

/// What the home tile says: `5 UNREAD`, and `Inbox 3 · [Corp] 2` — the built-in mailboxes with
/// something unread, in their order (Sent never has).
public struct MailUnreadSummary: Sendable, Hashable {
    public var totalUnread: Int
    /// The built-in mailboxes with unread mail, in their order.
    public var mailboxes: [MailLabel]

    public init(_ labels: MailLabels) {
        totalUnread = labels.totalUnread
        mailboxes = labels.mailboxes.filter { $0.unreadCount > 0 }
    }

    /// `Inbox 3 · [Corp] 2`; `nil` when no mailbox has unread mail.
    public var mailboxesLine: String? {
        mailboxes.isEmpty ? nil : mailboxes.map { "\($0.name) \($0.unreadCount)" }.joined(separator: " · ")
    }
}

/// EVE time: UTC, Gregorian.
public enum EVETime {
    public static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.locale = Locale(identifier: "en_US_POSIX")
        return calendar
    }()

    /// Whole EVE days from `date`'s day to `now`'s day: 0 the same day, 1 yesterday, negative
    /// for a date after now's day.
    public static func daysBetween(_ date: Date, and now: Date) -> Int {
        let from = calendar.startOfDay(for: date)
        let to = calendar.startOfDay(for: now)
        return calendar.dateComponents([.day], from: from, to: to).day ?? 0
    }

    /// `2026.10.16 22:10`, the way EVE writes a moment.
    public static func dateTimeText(_ date: Date) -> String {
        let p = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        return String(format: "%04d.%02d.%02d %02d:%02d", p.year ?? 0, p.month ?? 0, p.day ?? 0, p.hour ?? 0, p.minute ?? 0)
    }
}
