import Foundation
import SDEDataDE
import SDEDataEN
import SDEDataES
import SDEDataFR
import SDEDataJA
import SDEDataKO
import SDEDataRU
import SDEDataZH

/// A language of the static data export.
///
/// The table is fixed to the eight exported languages, each bundled with the app as an `SDEData*`
/// target of the SDE package.
nonisolated struct SDELanguage: Identifiable, Hashable, Sendable {
    /// The `meta.language` code inside the file, and the `<lang>` of `text-<lang>.sqlite`.
    let code: String
    /// The language's name in itself.
    let nativeName: String
    /// The language's name in English.
    let englishName: String

    var id: String { code }

    static let english = SDELanguage(code: "en", nativeName: "English", englishName: "English")

    /// Every language: English first, then the others by code.
    static let all: [SDELanguage] = [
        english,
        SDELanguage(code: "de", nativeName: "Deutsch", englishName: "German"),
        SDELanguage(code: "es", nativeName: "Español", englishName: "Spanish"),
        SDELanguage(code: "fr", nativeName: "Français", englishName: "French"),
        SDELanguage(code: "ja", nativeName: "日本語", englishName: "Japanese"),
        SDELanguage(code: "ko", nativeName: "한국어", englishName: "Korean"),
        SDELanguage(code: "ru", nativeName: "Русский", englishName: "Russian"),
        SDELanguage(code: "zh", nativeName: "中文", englishName: "Chinese"),
    ]

    /// The language with this code, or `nil` for an unknown code.
    static func code(_ code: String) -> SDELanguage? {
        all.first { $0.code == code }
    }

    /// The bundled `text-<code>.sqlite` in the resource bundle of its `SDEData*` target.
    var fileURL: URL {
        switch code {
        case "de": SDEDataDE.url
        case "es": SDEDataES.url
        case "fr": SDEDataFR.url
        case "ja": SDEDataJA.url
        case "ko": SDEDataKO.url
        case "ru": SDEDataRU.url
        case "zh": SDEDataZH.url
        default: SDEDataEN.url
        }
    }
}
