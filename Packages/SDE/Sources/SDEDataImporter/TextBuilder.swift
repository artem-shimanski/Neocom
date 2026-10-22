//
//  TextBuilder.swift
//  SDE
//
//  Created by Artem Shimanski on 05.09.2026.
//

import Foundation
import LiteRow
import LiteRowBuild
import SDEModels

/// Dump language. Declaration order is the storage order in `Localized`.
enum Language: String, CaseIterable, Sendable {
    case de, en, es, fr, ja, ko, ru, zh

    /// Collation locale: in SQLite `BINARY` and `NOCASE` do not know `ё` and `ä`.
    var locale: Locale { Locale(identifier: rawValue) }

    /// Search index tokenizer.
    ///
    /// `unicode61` splits on delimiters, which Chinese and Japanese lack; `trigram` matches a
    /// substring anywhere.
    var tokenizer: TextTokenizer {
        switch self {
        case .zh, .ja: .trigram
        case .de, .en, .es, .fr, .ko, .ru: .unicode61
        }
    }
}

/// Eight translations of one string.
///
/// A missing translation is output as English: the language file must be complete so reads need no
/// fallback.
struct Localized: Hashable, Sendable {
    var values: [String]

    init(de: String?, en: String, es: String?, fr: String?, ja: String?, ko: String?, ru: String?, zh: String?) {
        values = [de ?? en, en, es ?? en, fr ?? en, ja ?? en, ko ?? en, ru ?? en, zh ?? en]
    }

    /// String without translation: an internal name, a resource path.
    init(same text: String) {
        values = Array(repeating: text, count: Language.allCases.count)
    }

    subscript(language: Language) -> String {
        values[language.index]
    }
}

/// Type with the eight language fields of the raw schema; implementations are in
/// `RawLocalization.swift`.
protocol Localizable {
    var localized: Localized { get }
}

extension Language {
    var index: Int {
        switch self {
        case .de: 0
        case .en: 1
        case .es: 2
        case .fr: 3
        case .ja: 4
        case .ko: 5
        case .ru: 6
        case .zh: 7
        }
    }
}

/// Hands out `NameID`/`DescriptionID` and fills the language files.
///
/// One ID is one string across all language files; IDs are assigned while the main database is
/// built, so a file is valid only for its own build (`meta.buildNumber`). Names accumulate in
/// memory for `ordinal`, descriptions are written in batches.
final class TextBuilder {
    /// Number of descriptions to accumulate before writing; a flush is one transaction.
    private static let flushThreshold = 4096

    private let languages: [Language]
    private let builders: [Language: DatabaseBuilder]

    private var names: [(id: NameID, text: Localized)] = []
    private var nameIDs: [Localized: NameID] = [:]

    private var descriptions: [(id: DescriptionID, text: Localized)] = []
    private var descriptionIDs: [Localized: DescriptionID] = [:]
    private var nextDescriptionID: UInt32 = 0

    init(languages: [Language], builders: [Language: DatabaseBuilder]) throws {
        self.languages = languages
        self.builders = builders
        for language in languages {
            let builder = builders[language]!
            try builder.setApplicationID(SDESchema.applicationID)
            try builder.setUserVersion(SDESchema.version)
            try builder.create(NameRow.self)
            try builder.create(DescriptionRow.self)
            try builder.create(TextMeta.self)
        }
    }

    // MARK: - ID assignment

    /// Name. Deduplicated by the full set of languages: identical `en` may differ in other
    /// languages.
    func name(_ text: Localized) -> NameID {
        if let existing = nameIDs[text] { return existing }
        let id = NameID(rawValue: UInt32(names.count))
        names.append((id, text))
        nameIDs[text] = id
        return id
    }

    func name(_ text: Localized?) -> NameID? {
        text.map { name($0) }
    }

    /// Repeating short text: ship bonuses, attribute hints. Deduplicated.
    func description(_ text: Localized) -> DescriptionID {
        if let existing = descriptionIDs[text] { return existing }
        let id = append(text)
        descriptionIDs[text] = id
        return id
    }

    func description(_ text: Localized?) -> DescriptionID? {
        text.map { description($0) }
    }

    /// Long text without repeats: a type description. Not deduplicated, to avoid holding 140 MB of
    /// keys in memory.
    func uniqueDescription(_ text: Localized) -> DescriptionID {
        append(text)
    }

    func uniqueDescription(_ text: Localized?) -> DescriptionID? {
        text.map { uniqueDescription($0) }
    }

    private func append(_ text: Localized) -> DescriptionID {
        let id = DescriptionID(rawValue: nextDescriptionID)
        nextDescriptionID += 1
        descriptions.append((id, text))
        if descriptions.count >= Self.flushThreshold {
            // Nowhere to throw from here; a write error means a broken disk.
            try! flushDescriptions()
        }
        return id
    }

    private func flushDescriptions() throws {
        guard !descriptions.isEmpty else { return }
        for language in languages {
            let rows = descriptions.map { DescriptionRow(id: $0.id, text: $0.text[language]) }
            try builders[language]!.insert(rows)
        }
        descriptions.removeAll(keepingCapacity: true)
    }

    // MARK: - Finalization

    /// Appends names with ordinals and builds the search index.
    ///
    /// Order is mandatory: data, `create(fts:)` + `rebuild`, indexes; `rebuild` before the data is
    /// loaded produces an empty index without an error.
    func finish(buildNumber: Int, output: URL) throws {
        try flushDescriptions()

        for language in languages {
            let builder = builders[language]!

            try builder.insert(TextMeta(
                language: language.rawValue,
                buildNumber: buildNumber,
                tokenizer: language.tokenizer
            ))

            let ordinals = ordinals(for: language)
            let english = language == .en
            let rows = names.map { name in
                NameRow(
                    id: name.id,
                    text: name.text[language],
                    // In the English file the second column is empty, to avoid indexing twice.
                    textEn: english ? "" : name.text[.en],
                    ordinal: ordinals[Int(name.id.rawValue)]
                )
            }
            try builder.insert(rows)

            let index = FTS5Definition(
                NameSearchIndex.self,
                content: NameRow.self,
                rowID: \.id,
                options: options(for: language)
            )
            try builder.create(index)
            try builder.rebuild(index)
            try builder.optimize(index)

            try builder.createIndexes(NameRow.self)
            try builder.analyze()
            try builder.vacuum(into: output.appending(path: "text-\(language.rawValue).sqlite"))
            builder.close()
        }
    }

    /// Ordinals of names in the language's alphabet.
    ///
    /// Options match `localizedStandardCompare` (case- and diacritic-insensitive, numbers as
    /// numbers) but with the locale of the language being built, not the system one.
    private static let collationOptions: String.CompareOptions =
        [.caseInsensitive, .diacriticInsensitive, .numeric, .widthInsensitive, .forcedOrdering]

    private func ordinals(for language: Language) -> [UInt32] {
        let locale = language.locale
        let sorted = names.indices.sorted { lhs, rhs in
            let left = names[lhs].text[language]
            let right = names[rhs].text[language]
            let order = left.compare(right, options: Self.collationOptions, range: nil, locale: locale)
            // Equal strings are ordered by ID: ordinals are stable across builds.
            return order == .orderedSame ? lhs < rhs : order == .orderedAscending
        }
        var result = [UInt32](repeating: 0, count: names.count)
        for (ordinal, index) in sorted.enumerated() {
            result[Int(names[index].id.rawValue)] = UInt32(ordinal)
        }
        return result
    }

    private func options(for language: Language) -> FTS5Definition.Options {
        switch language.tokenizer {
        case .unicode61: .asYouType
        case .trigram: .substring
        }
    }
}
