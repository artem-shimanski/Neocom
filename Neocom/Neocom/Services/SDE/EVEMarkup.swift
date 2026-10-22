import Foundation
import SwiftUI

/// Converts EVE's markup from the data export into an attributed string.
///
/// Descriptions use HTML-like tags (`<b>`, `<i>`, `<u>`, `<br>`) and in-client links
/// (`<a href=showinfo:645>Dominix</a>`). Supported tags are converted and the rest dropped; links
/// keep their text but not their `showinfo:` destination, which only the EVE client handles.
///
/// SwiftUI is imported for `underlineStyle`, which `InlinePresentationIntent` lacks.
enum EVEMarkup {
    static func attributedString(from markup: String) -> AttributedString {
        var result = AttributedString()
        var traits = Traits()
        var text = ""

        // Single-pass scan; an HTML parser rejects unquoted attributes and tags like `<color=0xff...>`.
        func flush() {
            guard !text.isEmpty else { return }
            var run = AttributedString(decodeEntities(text))
            run.inlinePresentationIntent = traits.presentationIntent
            if traits.underline { run.underlineStyle = .single }
            result += run
            text = ""
        }

        var rest = Substring(markup)
        while let open = rest.firstIndex(of: "<") {
            text += rest[rest.startIndex..<open]
            guard let close = rest[open...].firstIndex(of: ">") else {
                // An unbalanced `<` is literal text.
                text += rest[open...]
                rest = rest[rest.endIndex...]
                break
            }
            let tag = rest[rest.index(after: open)..<close].lowercased()
            rest = rest[rest.index(after: close)...]

            switch tag {
            case "br", "br/", "br /":
                text += "\n"
            case "b", "i", "u":
                flush()
                traits.set(tag, on: true)
            case "/b", "/i", "/u":
                flush()
                traits.set(String(tag.dropFirst()), on: false)
            default:
                // Links, colours, fonts and urls keep their text; the tag is dropped.
                break
            }
        }
        text += rest
        flush()
        return result
    }


    private struct Traits {
        var bold = false
        var italic = false
        var underline = false

        mutating func set(_ tag: String, on: Bool) {
            switch tag {
            case "b": bold = on
            case "i": italic = on
            case "u": underline = on
            default: break
            }
        }

        /// Underline has no `InlinePresentationIntent` case and is applied as a separate attribute.
        var presentationIntent: InlinePresentationIntent? {
            var intent: InlinePresentationIntent = []
            if bold { intent.insert(.stronglyEmphasized) }
            if italic { intent.insert(.emphasized) }
            return intent.isEmpty ? nil : intent
        }
    }

    /// Decodes the five entities used in the export; any other ampersand is literal.
    private static func decodeEntities(_ text: String) -> String {
        guard text.contains("&") else { return text }
        return text
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&amp;", with: "&")
    }
}
