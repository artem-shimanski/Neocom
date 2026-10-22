import KillmailKit
import LiteRowUI
import MailKit
import SDEKit
import SwiftUI

/// A mail's body, from its EVE markup: the text with its bold, italic, underline and colours,
/// links Neocom can follow drawn in `accent`, and a fitting or a kill report the mail links to
/// lifted out of the text as a card of its own.
///
/// Every tap leaves through `openURL` with a `MailLinkURL`: the message screen routes the ones
/// that stay in Neocom, the system opens the rest.
struct MailBodyView: View {
    let markup: String

    var body: some View {
        let blocks = MailBodyBlock.blocks(of: MailMarkup.parse(markup))
        if blocks.isEmpty {
            Text("This mail has no text.")
                .font(.hudBody)
                .foregroundStyle(Color.hudInkMuted)
        } else {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(blocks.indices, id: \.self) { index in
                    switch blocks[index] {
                    case let .text(text):
                        Text(text)
                            .font(Self.bodyFont)
                            .lineSpacing(4)
                            .foregroundStyle(Color.hudInk)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    case let .fitting(fitting, title):
                        MailFittingCard(fitting: fitting, title: title)
                    case let .killReport(id, hash, title):
                        MailKillReportCard(killID: id, hash: hash, title: title)
                    }
                }
            }
        }
    }

    static let bodyFont = HUDFont.display(16, weight: .medium, relativeTo: .body)
}

/// A stretch of the body: text, or a card.
enum MailBodyBlock {
    case text(AttributedString)
    case fitting(MailFitting, title: String)
    case killReport(id: Int64, hash: String, title: String)

    static func blocks(of document: MailDocument) -> [MailBodyBlock] {
        var blocks: [MailBodyBlock] = []
        var text = AttributedString()
        /// The link of the card last added, while the runs after it still belong to it: a
        /// link's text drawn in two styles is two runs, and must stay one card.
        var openCard: MailLink?

        func flushText() {
            let trimmed = trimmingNewlines(text)
            if !trimmed.characters.isEmpty { blocks.append(.text(trimmed)) }
            text = AttributedString()
        }

        for run in document.runs {
            switch run.link {
            case let .fitting(fitting)?:
                if openCard == run.link, case let .fitting(_, title)? = blocks.last {
                    blocks[blocks.count - 1] = .fitting(fitting, title: title + run.text)
                } else {
                    flushText()
                    blocks.append(.fitting(fitting, title: run.text))
                }
                openCard = run.link
            case let .killReport(id, hash)?:
                if openCard == run.link, case let .killReport(_, _, title)? = blocks.last {
                    blocks[blocks.count - 1] = .killReport(id: id, hash: hash, title: title + run.text)
                } else {
                    flushText()
                    blocks.append(.killReport(id: id, hash: hash, title: run.text))
                }
                openCard = run.link
            default:
                openCard = nil
                text.append(attributed(run))
            }
        }
        flushText()
        return blocks.map { block in
            switch block {
            case .text: block
            case let .fitting(fitting, title): .fitting(fitting, title: title.trimmingCharacters(in: .whitespacesAndNewlines))
            case let .killReport(id, hash, title): .killReport(id: id, hash: hash, title: title.trimmingCharacters(in: .whitespacesAndNewlines))
            }
        }
    }

    private static func attributed(_ run: MailRun) -> AttributedString {
        var string = AttributedString(run.text)
        let url = run.link.flatMap { MailLinkURL.url(for: $0) }
        let isEmphasised = run.style.isBold || run.link != nil
        var font = HUDFont.display(16, weight: isEmphasised ? .semibold : .medium, relativeTo: .body)
        if run.style.isItalic { font = font.italic() }
        string.font = font
        if run.style.isUnderlined { string.underlineStyle = .single }
        if let url {
            string.link = url
            string.foregroundColor = .hudAccent
        } else if let color = run.style.color, !isGrey(color) {
            // White and greys are unreadable on the dark panel; only a real colour is kept.
            string.foregroundColor = MailText.color(color)
        }
        return string
    }

    /// `MailColor.isNeutral`, and the darker greys too.
    private static func isGrey(_ color: MailColor) -> Bool {
        color.isNeutral || Int(max(color.red, color.green, color.blue)) - Int(min(color.red, color.green, color.blue)) < 16
    }

    private static func trimmingNewlines(_ text: AttributedString) -> AttributedString {
        var text = text
        while let first = text.characters.first, first.isNewline {
            text.removeSubrange(text.startIndex..<text.characters.index(after: text.startIndex))
        }
        while let last = text.characters.last, last.isNewline || last == " " {
            text.removeSubrange(text.characters.index(before: text.endIndex)..<text.endIndex)
        }
        return text
    }
}

/// `FITTING · VEXOR` / the link's text / `OPEN IN FITTING TOOL`.
private struct MailFittingCard: View {
    let fitting: MailFitting
    let title: String

    @Environment(\.openURL) private var openURL
    @LiteQuery private var ship: TypeSummary?

    init(fitting: MailFitting, title: String) {
        self.fitting = fitting
        self.title = title
        _ship = LiteQuery(SDEBrowser.summary(of: TypeID(rawValue: UInt32(clamping: fitting.shipTypeID))))
    }

    var body: some View {
        let shipName = ship?.name
        Button {
            if let url = MailLinkURL.url(for: .fitting(fitting), title: title.isEmpty ? shipName : title) {
                openURL(url)
            }
        } label: {
            HUDLinkCard(systemImage: "wrench.and.screwdriver",
                        caption: shipName.map { Text(verbatim: "\(String(localized: "Fitting")) · \($0)") } ?? Text("Fitting"),
                        title: Text(verbatim: title.isEmpty ? (shipName ?? String(localized: "Fitting")) : title),
                        detail: Text("Open in Fitting Tool"))
        }
        .buttonStyle(.plain)
    }
}

/// `KILL REPORT` / `VEXOR · <PILOT>` / `LOSS · KAMELA · 2026.10.16 20:40 · ≈36.76M ISK`,
/// from the killmail itself (`KillmailsSheet.killmail(id:hash:)`); the link's text while it
/// loads or when it cannot be. A tap opens the killmail's report in Neocom.
private struct MailKillReportCard: View {
    let killID: Int64
    let hash: String
    let title: String

    @Environment(AccountStore.self) private var accounts
    @Environment(\.openURL) private var openURL

    var body: some View {
        Button {
            if let url = MailLinkURL.url(for: .killReport(id: killID, hash: hash)) { openURL(url) }
        } label: {
            if let sheet = accounts.currentKillmails {
                MailKillReportCardContent(snapshot: sheet.killmail(id: killID, hash: hash), sheet: sheet,
                                          fallbackTitle: fallbackTitle)
            } else {
                MailKillReportCardLabel(title: fallbackTitle, detail: nil)
            }
        }
        .buttonStyle(.plain)
    }

    private var fallbackTitle: String { title.isEmpty ? "#\(killID)" : title }
}

private struct MailKillReportCardContent: View {
    let snapshot: ESISnapshot<ESIKillmail>
    let sheet: KillmailsSheet
    let fallbackTitle: String

    @Environment(MarketSheet.self) private var market

    var body: some View {
        Group {
            if let report = snapshot.value {
                let killmail = report.killmail
                KillmailStaticsReader(systemIDs: [killmail.solarSystemID], typeIDs: [killmail.victim.shipTypeID]) { statics in
                    let naming = KillmailNaming(names: report.names, sheet: sheet)
                    let value = killmail.value { market.ccpAverage(of: $0) }.total
                    let side = KillmailText.side(of: killmail, pilotID: sheet.characterID)
                    let detail = [side.map { KillmailText.title(of: $0) },
                                  statics.system(killmail.solarSystemID)?.name,
                                  EVETime.dateTime(killmail.time),
                                  value > 0 ? "≈\(KillmailText.isk(value)) ISK" : nil]
                        .compactMap { $0 }.joined(separator: " · ")
                    MailKillReportCardLabel(
                        title: [statics.typeName(killmail.victim.shipTypeID), naming.victim(of: killmail)]
                            .compactMap { $0 }.joined(separator: " · "),
                        detail: detail)
                }
            } else {
                MailKillReportCardLabel(title: fallbackTitle, detail: nil)
            }
        }
        .task { await snapshot.ensureFresh() }
        .task { await market.ensurePricesFresh() }
    }
}

private struct MailKillReportCardLabel: View {
    let title: String
    let detail: String?

    var body: some View {
        HUDLinkCard(systemImage: "scope",
                    caption: Text("Kill Report"),
                    title: Text(verbatim: title),
                    detail: detail.map { Text(verbatim: $0) },
                    detailColor: .hudInkMuted)
    }
}
