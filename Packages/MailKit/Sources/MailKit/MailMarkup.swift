import Foundation

// EVE mail bodies are the game client's rich text: an HTML-like markup with `<font size=
// color=>`, `<b>`, `<i>`, `<u>`, `<br>`, `<a href=...>` and HTML entities. Links point into the
// game — `showinfo:TYPEID//ITEMID` for anything with an info window, `fitting:...` for a ship
// fitting, `killReport:ID:HASH`, `joinChannel:...` — or out to the web.
//
// `MailMarkup.parse` turns a body into plain runs of text, each with its style and, where the
// text is a link Neocom can open, the link's target. Anything else — tags it does not know,
// links it cannot open — becomes plain text: nothing in a mail is ever dropped silently, and
// nothing is ever interpreted as more than text.

/// A colour from a `<font color=>`: EVE writes `#AARRGGBB`, sometimes `#RRGGBB`.
public struct MailColor: Codable, Sendable, Hashable {
    public var red: UInt8
    public var green: UInt8
    public var blue: UInt8
    public var alpha: UInt8

    public init(red: UInt8, green: UInt8, blue: UInt8, alpha: UInt8 = 255) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    /// `#AARRGGBB` or `#RRGGBB`, the `#` optional; `nil` for anything else.
    public init?(hex: String) {
        var digits = hex.trimmingCharacters(in: .whitespaces)
        if digits.hasPrefix("#") { digits.removeFirst() }
        guard digits.count == 6 || digits.count == 8,
              digits.allSatisfy(\.isHexDigit),
              let value = UInt32(digits, radix: 16) else { return nil }
        if digits.count == 8 {
            self.init(red: UInt8((value >> 16) & 0xFF), green: UInt8((value >> 8) & 0xFF),
                      blue: UInt8(value & 0xFF), alpha: UInt8(value >> 24))
        } else {
            self.init(red: UInt8(value >> 16), green: UInt8((value >> 8) & 0xFF), blue: UInt8(value & 0xFF))
        }
    }

    /// EVE's default body colour, `#bfffffff` — 75% white, and every mail written in the game
    /// carries it. A screen draws text in this colour as ordinary text.
    public static let eveDefault = MailColor(red: 255, green: 255, blue: 255, alpha: 0xBF)

    /// Close enough to white (or grey) that it says nothing: the game's default and its
    /// variations. A screen on a dark background may ignore such a colour.
    public var isNeutral: Bool {
        max(red, green, blue) - min(red, green, blue) < 16 && min(red, green, blue) > 160
    }
}

/// How a run of text is drawn.
public struct MailTextStyle: Codable, Sendable, Hashable {
    public var isBold = false
    public var isItalic = false
    public var isUnderlined = false
    public var color: MailColor?
    /// `<font size=>`, in the game's points; `nil` for the default.
    public var size: Int?

    public init(isBold: Bool = false, isItalic: Bool = false, isUnderlined: Bool = false,
                color: MailColor? = nil, size: Int? = nil) {
        self.isBold = isBold
        self.isItalic = isItalic
        self.isUnderlined = isUnderlined
        self.color = color
        self.size = size
    }

    public static let plain = MailTextStyle()
}

/// A ship fitting a mail links to: EVE's DNA string (`SHIP:MODULE;COUNT:...::`).
public struct MailFitting: Codable, Sendable, Hashable {
    public var dna: String
    public var shipTypeID: Int64

    public init(dna: String, shipTypeID: Int64) {
        self.dna = dna
        self.shipTypeID = shipTypeID
    }
}

/// Where a link in a mail leads, as far as Neocom can follow it.
public enum MailLink: Codable, Sendable, Hashable {
    /// A pilot's info.
    case character(Int64)
    case corporation(Int64)
    case alliance(Int64)
    case solarSystem(Int64)
    case constellation(Int64)
    case region(Int64)
    /// `showinfo:TYPEID` with no item: the type itself, in the database.
    case type(Int64)
    /// `showinfo:TYPEID//ITEMID` for anything not classified above — a station, a structure,
    /// a faction, a ship. `typeID` says what the item is; the SDE can tell a station type from
    /// a ship type, this parser does not.
    case info(typeID: Int64, itemID: Int64)
    /// `fitting:DNA`: opens in the Fitting Tool.
    case fitting(MailFitting)
    /// `killReport:ID:HASH`: `/killmails/{id}/{hash}`.
    case killReport(id: Int64, hash: String)
    /// `http(s)://…`.
    case url(URL)

    /// Type ids that are characters (EVE's per-race character types, and the later one).
    public static let characterTypeIDs: Set<Int64> = Set(1373...1386).union([34574])
    public static let corporationTypeID: Int64 = 2
    public static let allianceTypeID: Int64 = 16159
    public static let regionTypeID: Int64 = 3
    public static let constellationTypeID: Int64 = 4
    public static let solarSystemTypeID: Int64 = 5

    /// The target of an `href`; `nil` for one Neocom cannot open (`joinChannel:`, `showRouteTo:`,
    /// `contract:`, a malformed `showinfo:`…), which then reads as plain text.
    public init?(href: String) {
        let href = href.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = href.lowercased()
        if lower.hasPrefix("showinfo:") {
            let parts = href.dropFirst("showinfo:".count).components(separatedBy: "//")
            guard let typeID = Int64(parts[0].trimmingCharacters(in: .whitespaces)), typeID > 0 else { return nil }
            let itemID = parts.count > 1 ? Int64(parts[1].trimmingCharacters(in: .whitespaces)) : nil
            guard let itemID, itemID > 0 else {
                if parts.count > 1, !parts[1].isEmpty { return nil }
                self = .type(typeID)
                return
            }
            if Self.characterTypeIDs.contains(typeID) {
                self = .character(itemID)
            } else {
                switch typeID {
                case Self.corporationTypeID: self = .corporation(itemID)
                case Self.allianceTypeID: self = .alliance(itemID)
                case Self.solarSystemTypeID: self = .solarSystem(itemID)
                case Self.constellationTypeID: self = .constellation(itemID)
                case Self.regionTypeID: self = .region(itemID)
                default: self = .info(typeID: typeID, itemID: itemID)
                }
            }
        } else if lower.hasPrefix("fitting:") {
            let dna = String(href.dropFirst("fitting:".count))
            guard let ship = dna.split(separator: ":", omittingEmptySubsequences: false).first,
                  let shipTypeID = Int64(ship), shipTypeID > 0 else { return nil }
            self = .fitting(MailFitting(dna: dna, shipTypeID: shipTypeID))
        } else if lower.hasPrefix("killreport:") {
            let parts = href.dropFirst("killReport:".count).split(separator: ":")
            guard parts.count >= 2, let id = Int64(parts[0]), id > 0,
                  parts[1].allSatisfy(\.isHexDigit), !parts[1].isEmpty else { return nil }
            self = .killReport(id: id, hash: String(parts[1]))
        } else if lower.hasPrefix("http://") || lower.hasPrefix("https://") {
            guard let url = URL(string: href), url.host != nil else { return nil }
            self = .url(url)
        } else {
            return nil
        }
    }
}

/// A stretch of text drawn one way.
public struct MailRun: Codable, Sendable, Hashable {
    public var text: String
    public var style: MailTextStyle
    /// Where the text leads; `nil` for plain text, which a link Neocom cannot open is too.
    public var link: MailLink?

    public init(text: String, style: MailTextStyle = .plain, link: MailLink? = nil) {
        self.text = text
        self.style = style
        self.link = link
    }
}

/// A parsed mail body.
public struct MailDocument: Codable, Sendable, Hashable {
    /// The body in order; adjacent runs drawn alike are one run. Line breaks are `\n` inside
    /// the text.
    public var runs: [MailRun]

    public init(runs: [MailRun]) {
        self.runs = runs
    }

    /// The body as plain text: what a reply quotes. A link reads as its text.
    public var plainText: String { runs.map(\.text).joined() }

    /// Every link Neocom can open, in order, once each.
    public var links: [MailLink] {
        var seen: Set<MailLink> = []
        return runs.compactMap(\.link).filter { seen.insert($0).inserted }
    }

    public var isEmpty: Bool { runs.allSatisfy { $0.text.isEmpty } }
}

public enum MailMarkup {
    /// Parses EVE mail markup. Never fails: whatever is not understood is text.
    public static func parse(_ markup: String) -> MailDocument {
        var parser = Parser()
        parser.run(markup)
        return MailDocument(runs: parser.finish())
    }

    /// `parse(markup).plainText`.
    public static func plainText(_ markup: String) -> String {
        parse(markup).plainText
    }

    /// Plain text as EVE markup, for sending: `&`, `<` and `>` escaped so the game shows them
    /// as typed, line breaks as `<br>`.
    public static func encode(plainText text: String) -> String {
        var result = ""
        result.reserveCapacity(text.count)
        for character in text {
            switch character {
            case "&": result += "&amp;"
            case "<": result += "&lt;"
            case ">": result += "&gt;"
            case "\r\n", "\n", "\r", "\u{2028}":
                result += "<br>"
            default: result.append(character)
            }
        }
        return result
    }

    /// The text with HTML entities replaced: `&amp;`, `&lt;`, `&gt;`, `&quot;`, `&apos;`,
    /// `&nbsp;`, `&#NN;` and `&#xHH;`. An entity it does not know stays as written.
    public static func decodeEntities(_ text: String) -> String {
        guard text.contains("&") else { return text }
        var result = ""
        var index = text.startIndex
        while index < text.endIndex {
            let character = text[index]
            guard character == "&",
                  let semicolon = text[index...].prefix(12).firstIndex(of: ";") else {
                result.append(character)
                index = text.index(after: index)
                continue
            }
            let name = text[text.index(after: index)..<semicolon]
            if let decoded = entity(String(name)) {
                result += decoded
                index = text.index(after: semicolon)
            } else {
                result.append(character)
                index = text.index(after: index)
            }
        }
        return result
    }

    private static func entity(_ name: String) -> String? {
        switch name.lowercased() {
        case "amp": return "&"
        case "lt": return "<"
        case "gt": return ">"
        case "quot": return "\""
        case "apos": return "'"
        case "nbsp": return "\u{00A0}"
        default:
            guard name.hasPrefix("#") else { return nil }
            let digits = name.dropFirst()
            let value: UInt32? = digits.first == "x" || digits.first == "X"
                ? UInt32(digits.dropFirst(), radix: 16)
                : UInt32(digits)
            // `&#0;` and other control characters stay as written.
            guard let scalar = value.flatMap(Unicode.Scalar.init),
                  scalar.properties.generalCategory != .control || scalar == "\n" || scalar == "\t" else { return nil }
            return String(Character(scalar))
        }
    }

    // MARK: - Parser

    private struct Frame {
        var tag: String
        var style: MailTextStyle
        var link: MailLink?
    }

    private struct Parser {
        private var runs: [MailRun] = []
        private var stack: [Frame] = []

        private var style: MailTextStyle { stack.last?.style ?? .plain }
        private var link: MailLink? { stack.last?.link }

        mutating func run(_ markup: String) {
            var index = markup.startIndex
            var text = ""
            while index < markup.endIndex {
                let character = markup[index]
                if character == "<", let close = tagEnd(in: markup, from: index) {
                    let inner = markup[markup.index(after: index)..<close]
                    if let tag = Tag(inner) {
                        flush(&text)
                        apply(tag)
                        index = markup.index(after: close)
                        continue
                    }
                }
                text.append(character)
                index = markup.index(after: index)
            }
            flush(&text)
        }

        /// The `>` closing a tag opened at `start`: before the next `<`; a quoted attribute
        /// value may hold `>`. Only a quote right after `=` opens one — an apostrophe in text
        /// after a stray `<` (`I <3 it, don't`) must not swallow the tags behind it.
        private func tagEnd(in markup: String, from start: String.Index) -> String.Index? {
            var quote: Character?
            var previous: Character?
            var index = markup.index(after: start)
            while index < markup.endIndex {
                let character = markup[index]
                if let open = quote {
                    if character == open { quote = nil }
                } else if (character == "\"" || character == "'") && previous == "=" {
                    quote = character
                } else if character == ">" {
                    return index
                } else if character == "<" {
                    return nil
                }
                if quote == nil, !character.isWhitespace { previous = character }
                index = markup.index(after: index)
            }
            return nil
        }

        private mutating func flush(_ text: inout String) {
            guard !text.isEmpty else { return }
            let decoded = MailMarkup.decodeEntities(text.replacingOccurrences(of: "\r\n", with: "\n"))
            append(decoded)
            text = ""
        }

        private mutating func append(_ text: String) {
            guard !text.isEmpty else { return }
            let style = style
            let link = link
            if let last = runs.last, last.style == style, last.link == link {
                runs[runs.count - 1].text += text
            } else {
                runs.append(MailRun(text: text, style: style, link: link))
            }
        }

        private var endsWithNewline: Bool {
            runs.last.map { $0.text.hasSuffix("\n") } ?? true
        }

        private mutating func apply(_ tag: Tag) {
            if tag.isClosing {
                switch tag.name {
                case "p", "div":
                    if !endsWithNewline { append("\n") }
                default:
                    break
                }
                if let index = stack.lastIndex(where: { $0.tag == tag.name }) {
                    stack.removeSubrange(index...)
                }
                return
            }
            var style = style
            var link = link
            switch tag.name {
            case "br":
                append("\n")
                return
            case "p", "div":
                if !endsWithNewline { append("\n") }
                return
            case "b", "strong":
                style.isBold = true
            case "i", "em":
                style.isItalic = true
            case "u":
                style.isUnderlined = true
            case "font":
                if let color = tag.attributes["color"].flatMap(MailColor.init(hex:)) { style.color = color }
                if let size = tag.attributes["size"].flatMap({ Int($0.trimmingCharacters(in: .whitespaces)) }) {
                    style.size = size
                }
            case "a", "url":
                link = tag.attributes["href"].flatMap(MailLink.init(href:))
            default:
                // `<loc>`, `<color>`, anything else: no effect, and never shown.
                return
            }
            if tag.isSelfClosing { return }
            stack.append(Frame(tag: tag.name, style: style, link: link))
        }

        mutating func finish() -> [MailRun] {
            // Leading and trailing blank lines are the game's padding, not the author's.
            while let first = runs.first {
                let trimmed = String(first.text.drop { $0 == "\n" })
                if trimmed.isEmpty {
                    runs.removeFirst()
                } else {
                    runs[0].text = trimmed
                    break
                }
            }
            while let last = runs.last {
                var text = last.text
                while let tail = text.last, tail.isWhitespace { text.removeLast() }
                if text.isEmpty {
                    runs.removeLast()
                } else {
                    runs[runs.count - 1].text = text
                    break
                }
            }
            return runs
        }
    }

    /// One `<...>`: its lowercased name, attributes, and whether it closes or closes itself.
    private struct Tag {
        var name: String
        var isClosing: Bool
        var isSelfClosing: Bool
        var attributes: [String: String]

        /// `nil` when `inner` is not a tag at all (`< 5`, `<3`), which then stays text.
        init?(_ inner: Substring) {
            var body = inner.trimmingCharacters(in: .whitespacesAndNewlines)
            isClosing = body.hasPrefix("/")
            if isClosing { body.removeFirst() }
            isSelfClosing = body.hasSuffix("/")
            if isSelfClosing { body.removeLast() }
            guard let first = body.first, first.isLetter else { return nil }
            let nameEnd = body.firstIndex { !($0.isLetter || $0.isNumber) } ?? body.endIndex
            name = body[..<nameEnd].lowercased()
            var rest = body[nameEnd...]
            attributes = [:]
            // EVE's chat-style `<url=showinfo:...>`.
            if name == "url", rest.first == "=" {
                attributes["href"] = Self.unquote(String(rest.dropFirst()))
                return
            }
            while true {
                rest = rest.drop { $0.isWhitespace }
                guard let start = rest.first, start.isLetter else { break }
                let keyEnd = rest.firstIndex { !($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") } ?? rest.endIndex
                let key = rest[..<keyEnd].lowercased()
                rest = rest[keyEnd...].drop { $0.isWhitespace }
                guard rest.first == "=" else {
                    attributes[key] = ""
                    continue
                }
                rest = rest.dropFirst().drop { $0.isWhitespace }
                if let quote = rest.first, quote == "\"" || quote == "'" {
                    let afterQuote = rest.dropFirst()
                    let valueEnd = afterQuote.firstIndex(of: quote) ?? afterQuote.endIndex
                    attributes[key] = MailMarkup.decodeEntities(String(afterQuote[..<valueEnd]))
                    rest = valueEnd < afterQuote.endIndex ? afterQuote[afterQuote.index(after: valueEnd)...] : afterQuote[valueEnd...]
                } else {
                    let valueEnd = rest.firstIndex { $0.isWhitespace } ?? rest.endIndex
                    attributes[key] = MailMarkup.decodeEntities(String(rest[..<valueEnd]))
                    rest = rest[valueEnd...]
                }
            }
        }

        private static func unquote(_ value: String) -> String {
            var value = value.trimmingCharacters(in: .whitespaces)
            if let first = value.first, first == "\"" || first == "'", value.count >= 2, value.last == first {
                value = String(value.dropFirst().dropLast())
            }
            return MailMarkup.decodeEntities(value)
        }
    }
}
