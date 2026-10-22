import MailKit
import SwiftUI

/// How the Mail screens word and draw the values `MailKit` hands them: glyphs, colours,
/// names, the recipients line. Shared by the mailboxes, the inbox, the message and compose.
enum MailText {
    // MARK: Glyphs

    /// The glyph of a built-in mailbox, a custom label having a colour dot instead.
    static func symbol(ofMailbox labelID: Int64) -> String {
        switch labelID {
        case MailLabelID.inbox: "tray"
        case MailLabelID.sent: "paperplane"
        case MailLabelID.corporation: "building.2"
        case MailLabelID.alliance: "flag"
        default: "tag"
        }
    }

    static let mailingListSymbol = "list.bullet"

    /// The glyph of a recipient kind: on the `TO` chips, and on compose's tokens.
    static func symbol(of kind: MailRecipientKind) -> String {
        switch kind {
        case .character: "person"
        case .corporation: "building.2"
        case .alliance: "flag"
        case .mailingList: mailingListSymbol
        }
    }

    /// What the glyph means, for VoiceOver.
    static func title(of kind: MailRecipientKind) -> Text {
        switch kind {
        case .character: Text("Character")
        case .corporation: Text("Corporation")
        case .alliance: Text("Alliance")
        case .mailingList: Text("Mailing list")
        }
    }

    // MARK: Colours

    /// A label's `#rrggbb`. White — the game's default, and what the built-in labels carry —
    /// and a label with no colour are the neutral mark: white on the dark HUD, the muted ink
    /// in light appearance, where a white dot vanishes.
    static func color(ofLabel hex: String?) -> Color {
        guard let color = hex.flatMap(MailColor.init(hex:)),
              !(color.red == 255 && color.green == 255 && color.blue == 255) else { return .hudMarkNeutral }
        return Self.color(color)
    }

    static func color(hex: String) -> Color? {
        MailColor(hex: hex).map(color(_:))
    }

    static func color(_ color: MailColor) -> Color {
        Color(.sRGB, red: Double(color.red) / 255, green: Double(color.green) / 255,
              blue: Double(color.blue) / 255, opacity: 1)
    }

    // MARK: Names

    /// Who a mail is from: the name ESI gave, or a placeholder while it is not known.
    static func name(of id: Int64, names: [Int64: ESIEntityName], sheet: MailSheet) -> String {
        names[id]?.name
            ?? sheet.name(of: MailRecipient(id: id, kind: .character))
            ?? String(localized: "Unknown")
    }

    /// The image of a mail's sender: a portrait or a logo from the image server. A sender whose
    /// name is not resolved yet is taken for a character, which most are — a wrong guess is a
    /// `404` and leaves the initials. `nil` for a kind that has no image (a faction, a system).
    /// 128 is twice the 36pt avatar's size at 2x, the image server's next size up.
    static func avatarURL(of id: Int64, names: [Int64: ESIEntityName]) -> URL? {
        switch names[id]?.category {
        case nil, .character?: EVEImage.portrait(characterID: id, size: 128)
        case .corporation?: EVEImage.logo(corporationID: id, size: 128)
        case .alliance?: EVEImage.logo(allianceID: id, size: 128)
        default: nil
        }
    }

    /// A recipient's name: a mailing list from the character's lists, anyone else from the
    /// names the sheet has.
    static func name(of recipient: MailRecipient, names: [Int64: ESIEntityName], sheet: MailSheet) -> String {
        if recipient.kind == .mailingList {
            return sheet.name(of: recipient) ?? String(localized: "Mailing List")
        }
        return names[recipient.id]?.name ?? sheet.name(of: recipient) ?? String(localized: "Unknown")
    }

    /// `TO YOU`, `TO YOU + 11`, `TO RENS TRADERS + 2`.
    static func recipientsLine(_ header: MailHeader, names: [Int64: ESIEntityName], sheet: MailSheet,
                               corporationID: Int64?, allianceID: Int64?) -> String {
        let line = MailRecipientsLine(header, characterID: sheet.characterID,
                                      corporationID: corporationID, allianceID: allianceID)
        switch line {
        case .nobody:
            return ""
        case let .you(others):
            return others > 0 ? String(localized: "To you + \(others)") : String(localized: "To you")
        case let .recipient(recipient, others):
            let name = name(of: recipient, names: names, sheet: sheet)
            return others > 0 ? String(localized: "To \(name) + \(others)") : String(localized: "To \(name)")
        }
    }

    /// The name of a mailbox: Inbox and Sent in the app's language (ESI answers them in English),
    /// the rest as ESI or the game names them.
    static func mailboxName(id: Int64, name: String?) -> String? {
        switch id {
        case MailLabelID.inbox: String(localized: "Inbox")
        case MailLabelID.sent: String(localized: "mail.mailbox.sent", defaultValue: "Sent", comment: "The mailbox of sent mail.")
        default: name ?? MailLabelID.defaultName(of: id)
        }
    }

    /// The title of a mailbox's screen.
    static func title(of mailbox: Mailbox, sheet: MailSheet) -> String {
        switch mailbox {
        case let .label(id):
            mailboxName(id: id, name: sheet.labels.value?.label(id)?.name) ?? String(localized: "Mail")
        case let .mailingList(id):
            sheet.name(of: MailRecipient(id: id, kind: .mailingList)) ?? String(localized: "Mailing List")
        }
    }

    /// `TODAY`, `THIS WEEK`, `EARLIER`.
    static func title(of group: MailDayGroup) -> String {
        switch group {
        case .today: String(localized: "Today")
        case .thisWeek: String(localized: "This Week")
        case .earlier: String(localized: "Earlier")
        }
    }

    /// `11:42`, `YESTERDAY`, `10.14`, `2025.12.31`.
    static func date(_ date: Date, now: Date) -> String {
        let text = MailDateText(date, now: now)
        if case .yesterday = text { return String(localized: "Yesterday") }
        return text.description
    }
}

/// The custom URLs a mail body's links are drawn with: the body is a `Text` of attributed
/// runs, and a tap on one reaches the screen through `openURL`, which reads these back.
enum MailLinkURL {
    static let scheme = "neocom-mail"

    /// The URL a run's link is drawn with; `nil` for a link Neocom has no screen for (a pilot,
    /// a corporation, a solar system), which then reads as emphasised text.
    /// `title` is the link's text: the name a fitting opens under.
    static func url(for link: MailLink, title: String? = nil) -> URL? {
        switch link {
        case let .type(typeID), let .info(typeID, _):
            return URL(string: "\(scheme)://type/\(typeID)")
        case let .fitting(fitting):
            var components = URLComponents()
            components.scheme = scheme
            components.host = "fitting"
            components.queryItems = [URLQueryItem(name: "dna", value: fitting.dna)]
                + (title.map { [URLQueryItem(name: "name", value: $0)] } ?? [])
            return components.url
        case let .killReport(id, hash):
            guard let hash = hash.addingPercentEncoding(withAllowedCharacters: .alphanumerics) else { return nil }
            return URL(string: "\(scheme)://killmail/\(id)/\(hash)")
        case let .url(url):
            return url
        case .character, .corporation, .alliance, .solarSystem, .constellation, .region:
            return nil
        }
    }

    enum Target {
        case type(Int64)
        case fitting(dna: String, name: String?)
        /// A kill report: the killmail's own report screen.
        case killmail(id: Int64, hash: String)
    }

    /// What one of the URLs above leads to inside Neocom; `nil` for one that leaves the app.
    static func target(of url: URL) -> Target? {
        guard url.scheme == scheme else { return nil }
        switch url.host {
        case "type":
            return Int64(url.lastPathComponent).map(Target.type)
        case "fitting":
            let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            let name = items.first { $0.name == "name" }?.value
            return items.first { $0.name == "dna" }?.value.map { Target.fitting(dna: $0, name: name) }
        case "killmail":
            // `/<id>/<hash>`.
            let parts = url.pathComponents.filter { $0 != "/" }
            guard parts.count == 2, let id = Int64(parts[0]) else { return nil }
            return .killmail(id: id, hash: parts[1])
        default:
            return nil
        }
    }
}

extension MailDraft {
    /// The package writes the quote's `On … wrote:` line in English; this swaps it for the app's language.
    func withLocalizedQuoteHeader(of message: MailMessage, senderName: String) -> MailDraft {
        let english = MailQuote.header(sender: senderName, date: message.header.date)
        let date = MailKit.EVETime.dateTimeText(message.header.date)
        let localized = String(localized: "On \(date) \(senderName) wrote:", comment: "Header line above a quoted mail in a reply or forward; the date is EVE time.")
        var draft = self
        draft.quote = quote.replacingOccurrences(of: english, with: localized)
        return draft
    }
}
