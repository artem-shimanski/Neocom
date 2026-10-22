import Foundation

// Writing mail: `POST /characters/{id}/mail` takes 1 to 50 recipients, a subject of at most
// 1000 characters, a body of at most 10 000 and `approved_cost`, the CSPA fee the sender agrees
// to pay.
//
// CSPA: a character can charge pilots outside their contacts a fee for receiving mail. ESI
// documents no specific error for it; the game refuses such a mail with an error whose text
// names the charge (HTTP 520, `ContactCostNotApproved`), not documented to carry the amount.
// `MailCSPA.charge` recognises the refusal by its text and takes a number from it if present;
// otherwise the fee comes from `POST /characters/{id}/cspa`.

public enum MailLimits {
    public static let subjectLength = 1000
    public static let bodyLength = 10_000
    public static let recipients = MailRecipient.maxCount
}

public enum MailSubject {
    /// `Re: <subject>`, without stacking: `Re: Re: x` stays `Re: x`, and so do `RE:` and `Re[2]:`.
    public static func reply(to subject: String) -> String {
        prefixed("Re: ", subject, stripping: ["re"])
    }

    /// `Fw: <subject>`, without stacking; a forwarded reply keeps its `Re:` behind the `Fw:`.
    public static func forward(_ subject: String) -> String {
        prefixed("Fw: ", subject, stripping: ["fw", "fwd"])
    }

    private static func prefixed(_ prefix: String, _ subject: String, stripping: Set<String>) -> String {
        var rest = Substring(subject.trimmingCharacters(in: .whitespaces))
        while let colon = rest.prefix(8).firstIndex(of: ":") {
            var word = rest[..<colon].lowercased()
            // `Re[2]`, `RE(3)`.
            if let bracket = word.firstIndex(where: { $0 == "[" || $0 == "(" }) {
                word = String(word[..<bracket])
            }
            guard stripping.contains(word.trimmingCharacters(in: .whitespaces)) else { break }
            rest = rest[rest.index(after: colon)...].drop { $0 == " " }
        }
        return String((prefix + rest).prefix(MailLimits.subjectLength))
    }
}

/// The text a reply or a forward carries below what the pilot writes. Plain text: the quoted
/// mail goes along as its text, and its links as their words.
public enum MailQuote {
    /// The separator EVE's own client puts above a quoted mail.
    public static let separator = "--------------------------------"

    /// `On 2026.10.16 22:10 Hedda Coldwater wrote:`.
    public static func header(sender: String, date: Date) -> String {
        "On \(EVETime.dateTimeText(date)) \(sender) wrote:"
    }

    /// The quoted part: a blank line, the separator, the header, the original's plain text.
    public static func block(sender: String, date: Date, originalMarkup: String) -> String {
        "\n\n\(separator)\n\(header(sender: sender, date: date))\n\(MailMarkup.plainText(originalMarkup))"
    }
}

/// A mail being written, in plain text, and whether ESI will take it.
public struct MailDraft: Codable, Sendable, Hashable {
    public var recipients: [MailRecipient]
    public var subject: String
    /// What the pilot types, plain text.
    public var body: String
    /// The quoted mail under the body, plain text (`MailQuote.block`); empty for a new mail.
    /// Cut to fit when the whole would be too long — the pilot's own text never is.
    public var quote: String

    public init(recipients: [MailRecipient] = [], subject: String = "", body: String = "", quote: String = "") {
        self.recipients = recipients
        self.subject = subject
        self.body = body
        self.quote = quote
    }

    /// A reply to `message` from `sender` (the name to quote): to its sender, `Re:` subject,
    /// the original quoted.
    public static func reply(to message: MailMessage, senderName: String) -> MailDraft {
        MailDraft(recipients: [MailRecipient(id: message.header.from, kind: .character)],
                  subject: MailSubject.reply(to: message.header.subject),
                  quote: MailQuote.block(sender: senderName, date: message.header.date, originalMarkup: message.body))
    }

    /// A reply to everyone: the sender and every recipient but `characterID` themselves.
    public static func replyAll(to message: MailMessage, senderName: String, characterID: Int64) -> MailDraft {
        var draft = reply(to: message, senderName: senderName)
        for recipient in message.header.recipients
        where !(recipient.kind == .character && recipient.id == characterID) && !draft.recipients.contains(recipient) {
            draft.recipients.append(recipient)
        }
        // A reply to all of the character's own sent mail goes to its recipients, not back.
        let me = MailRecipient(id: characterID, kind: .character)
        if draft.recipients.count > 1 { draft.remove(me) }
        draft.recipients = Array(draft.recipients.prefix(MailLimits.recipients))
        return draft
    }

    /// A forward: no recipients yet, `Fw:` subject, the original quoted.
    public static func forward(_ message: MailMessage, senderName: String) -> MailDraft {
        MailDraft(subject: MailSubject.forward(message.header.subject),
                  quote: MailQuote.block(sender: senderName, date: message.header.date, originalMarkup: message.body))
    }

    /// Adds a recipient unless already there or the list is full. Answers whether it was added.
    @discardableResult
    public mutating func add(_ recipient: MailRecipient) -> Bool {
        guard !recipients.contains(recipient), recipients.count < MailLimits.recipients else { return false }
        recipients.append(recipient)
        return true
    }

    public mutating func remove(_ recipient: MailRecipient) {
        recipients.removeAll { $0 == recipient }
    }

    /// The body as ESI gets it: EVE markup, the quote cut so the whole fits 10 000 characters.
    public var encodedBody: String {
        let own = MailMarkup.encode(plainText: body)
        guard !quote.isEmpty else { return String(own.prefix(MailLimits.bodyLength)) }
        var quoted = MailMarkup.encode(plainText: quote)
        let room = MailLimits.bodyLength - own.count
        if quoted.count > room {
            quoted = String(quoted.prefix(max(0, room)))
            // Never leave half an entity or half a `<br>` at the cut.
            if let amp = quoted.lastIndex(of: "&"), !quoted[amp...].contains(";") { quoted = String(quoted[..<amp]) }
            if let lt = quoted.lastIndex(of: "<"), !quoted[lt...].contains(">") { quoted = String(quoted[..<lt]) }
        }
        return own + quoted
    }

    /// Characters of the body as ESI counts them (the encoded markup, quote included), for the
    /// `412 / 10 000` counter.
    public var bodyLength: Int { MailMarkup.encode(plainText: body).count + (quote.isEmpty ? 0 : MailMarkup.encode(plainText: quote).count) }

    public enum Issue: Sendable, Hashable {
        case noRecipients
        case tooManyRecipients
        case subjectTooLong
        /// The pilot's own text alone is over the limit; a long quote is cut instead.
        case bodyTooLong
    }

    /// What stops the draft from being sent; empty when it can go.
    public var issues: [Issue] {
        var issues: [Issue] = []
        if recipients.isEmpty { issues.append(.noRecipients) }
        if recipients.count > MailLimits.recipients { issues.append(.tooManyRecipients) }
        if subject.count > MailLimits.subjectLength { issues.append(.subjectTooLong) }
        if MailMarkup.encode(plainText: body).count > MailLimits.bodyLength { issues.append(.bodyTooLong) }
        return issues
    }

    public var canSend: Bool { issues.isEmpty }
}

/// How sending a mail ended.
public enum MailSendOutcome: Sendable, Hashable {
    /// Sent; ESI's id of the new mail.
    case sent(mailID: Int64)
    /// EVE refused it for a CSPA fee of `cost` ISK. Send again with `approvedCost: cost` once
    /// the pilot agrees. `cost` is `nil` when the refusal named a charge but the amount could
    /// not be learned.
    case needsApproval(cost: Int64?)
    /// Anything else — ESI's message when it gave one. The draft is kept for another try.
    case failed(message: String?)
}

public enum MailCSPA {
    /// What a refused `POST /mail` says about CSPA.
    public enum Charge: Sendable, Hashable {
        /// Not a CSPA refusal.
        case none
        /// A CSPA refusal; the fee if the message carried one.
        case required(cost: Int64?)
    }

    /// Reads a refusal: status and ESI's error text. A refusal counts as CSPA when the text
    /// names it (`CSPA`, `ContactCostNotApproved`, "contact cost", "approved cost"); the fee is
    /// the largest whole number in the text (separators `,` `.` and spaces allowed between
    /// digit groups of three), if any.
    public static func charge(status: Int, message: String?) -> Charge {
        guard let message, !message.isEmpty else { return .none }
        let lower = message.lowercased()
        let compact = lower.replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "_", with: "")
        let named = compact.contains("cspa")
            || compact.contains("contactcost")
            || compact.contains("approvedcost")
            || compact.contains("costnotapproved")
        guard named else { return .none }
        return .required(cost: largestAmount(in: message, ignoring: status))
    }

    /// The largest amount in `text`: `25000`, `25,000`, `25 000`, `25.000`, `25000.00` (the
    /// fraction dropped). A number equal to `status` is the HTTP status echoed in the text
    /// (`Error 520`), not a fee, and is skipped.
    static func largestAmount(in text: String, ignoring status: Int? = nil) -> Int64? {
        let pattern = /\d{1,3}(?:[ ,.\u{00A0}]\d{3})+(?!\d)|\d+/
        var best: Int64?
        for match in text.matches(of: pattern) {
            let digits = match.output.filter { $0.isASCII && $0.isNumber }
            guard let value = Int64(digits), value != Int64(status ?? -1) else { continue }
            best = max(best ?? 0, value)
        }
        return best
    }

    /// The fee to approve for `/characters/{id}/cspa`'s answer, in whole ISK, rounded up.
    public static func approvedCost(_ cost: Double) -> Int64 {
        guard cost.isFinite, cost > 0 else { return 0 }
        return Int64(cost.rounded(.up))
    }
}

/// Someone a mail can be addressed to, offered while the pilot types a name.
public struct MailSuggestion: Sendable, Hashable, Identifiable {
    public enum Source: Sendable, Hashable {
        /// One of the pilot's contacts, with their standing.
        case contact(standing: Double)
        /// One of the pilot's mailing lists.
        case mailingList
        /// Found by `/characters/{id}/search`.
        case search
    }

    public var recipient: MailRecipient
    public var name: String
    public var source: Source

    public init(recipient: MailRecipient, name: String, source: Source) {
        self.recipient = recipient
        self.name = name
        self.source = source
    }

    public var id: MailRecipient { recipient }
}

public enum MailSuggestions {
    /// ESI's search wants at least this many characters.
    public static let minimumSearchLength = 3

    /// What matches `query` (case- and diacritic-insensitive, anywhere in the name): contacts
    /// first — names starting with the query before the rest, then by standing, highest first —
    /// then the pilot's mailing lists, then search results by name. Nothing already in
    /// `excluding` and nothing twice; unnamed ids are left out.
    public static func make(query: String,
                            contacts: [MailContact],
                            mailingLists: [MailingList],
                            searchResults: [MailRecipient],
                            names: [Int64: String],
                            excluding: Set<MailRecipient> = [],
                            limit: Int = 20) -> [MailSuggestion] {
        let query = query.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return [] }
        func matches(_ name: String) -> Bool {
            name.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }
        func startsWith(_ name: String) -> Bool {
            name.range(of: query, options: [.caseInsensitive, .diacriticInsensitive, .anchored]) != nil
        }
        var seen = excluding
        var result: [MailSuggestion] = []

        let fromContacts = contacts.compactMap { contact -> (MailContact, String)? in
            guard let name = names[contact.recipient.id], matches(name) else { return nil }
            return (contact, name)
        }
        .sorted { lhs, rhs in
            let (l, r) = (startsWith(lhs.1), startsWith(rhs.1))
            if l != r { return l }
            if lhs.0.standing != rhs.0.standing { return lhs.0.standing > rhs.0.standing }
            return lhs.1.localizedStandardCompare(rhs.1) == .orderedAscending
        }
        for (contact, name) in fromContacts where seen.insert(contact.recipient).inserted {
            result.append(MailSuggestion(recipient: contact.recipient, name: name, source: .contact(standing: contact.standing)))
        }

        for list in mailingLists.sorted(by: { $0.name.localizedStandardCompare($1.name) == .orderedAscending })
        where matches(list.name) {
            let recipient = MailRecipient(id: list.id, kind: .mailingList)
            if seen.insert(recipient).inserted {
                result.append(MailSuggestion(recipient: recipient, name: list.name, source: .mailingList))
            }
        }

        let found = searchResults.compactMap { recipient -> (MailRecipient, String)? in
            names[recipient.id].map { (recipient, $0) }
        }
        .sorted { lhs, rhs in
            let (l, r) = (startsWith(lhs.1), startsWith(rhs.1))
            if l != r { return l }
            return lhs.1.localizedStandardCompare(rhs.1) == .orderedAscending
        }
        for (recipient, name) in found where seen.insert(recipient).inserted {
            result.append(MailSuggestion(recipient: recipient, name: name, source: .search))
        }
        return Array(result.prefix(limit))
    }
}
