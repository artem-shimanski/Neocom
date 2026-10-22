//
//  SDEDatabase.swift
//  SDE
//
//  Created by Artem Shimanski on 05.09.2026.
//

import Foundation
import Synchronization
import LiteRow
@_exported import SDEModels

public enum SDEError: Error, CustomStringConvertible {
    /// The main and language files were built from different SDE dumps: string IDs are assigned by
    /// the main database build, and a foreign language file silently yields wrong names.
    case buildMismatch(main: Int, text: Int)
    case emptyDatabase

    public var description: String {
        switch self {
        case let .buildMismatch(main, text):
            "языковой файл собран из другой выгрузки SDE: основная база — билд \(main), "
                + "языковая — \(text)"
        case .emptyDatabase:
            "в базе нет таблицы meta — это не файл SDE или он собран не до конца"
        }
    }
}

/// A set of SDE files opened for reading: the main file and one language file under the `text`
/// schema. English names are the second column of the same language file.
public final class SDEDatabase: Sendable {
    public let database: Database
    public let buildNumber: Int

    /// Everything that changes on a language switch, as one value under a mutex.
    ///
    /// Written by `setLanguage`, read by `pattern(_:)` from any thread; the mutex is needed for
    /// `Sendable`.
    private let textInfo: Mutex<TextInfo>

    struct TextInfo: Sendable {
        var language: String
        var tokenizer: TextTokenizer
    }

    public var language: String { textInfo.withLock { $0.language } }

    /// Search index tokenizer of the language file: the pattern factory depends on it.
    public var tokenizer: TextTokenizer { textInfo.withLock { $0.tokenizer } }

    /// Opens the set.
    ///
    /// LiteRow checks `applicationID` and `schemaVersion` on every `ATTACH`; the dump match is
    /// checked here against the `meta` of both files.
    public init(main: URL, text url: URL) async throws {
        database = try Database(
            main: main,
            attached: [.text: url],
            options: Database.Options(
                schemaVersion: SDESchema.version,
                applicationID: SDESchema.applicationID
            )
        )
        let (mainMeta, textMeta) = try await database.read { reader in
            (try reader.fetchOne(Meta.all().query()),
             try reader.fetchOne(TextMeta.all().query()))
        }
        guard let mainMeta, let textMeta else { throw SDEError.emptyDatabase }
        guard mainMeta.buildNumber == textMeta.buildNumber else {
            throw SDEError.buildMismatch(main: mainMeta.buildNumber, text: textMeta.buildNumber)
        }
        buildNumber = mainMeta.buildNumber
        textInfo = Mutex(TextInfo(language: textMeta.language, tokenizer: textMeta.tokenizer))
    }

    /// Pattern for `MATCH` from user input.
    ///
    /// Returns `nil` if there are no tokens: an empty `MATCH` is an fts5 error. A raw string must
    /// not be passed to `MATCH`.
    public func pattern(_ input: String) -> FTS5Pattern? {
        switch textInfo.withLock({ $0.tokenizer }) {
        case .unicode61:
            // An asterisk on the last token: the user has not finished typing it.
            return .all(input, prefix: true)
        case .trigram:
            // Trigrams need no prefix index: a phrase is found from the middle of a word.
            return .phrase(input)
        }
    }

    /// Ranking weights: the native language outweighs English. Order is the `names_fts` columns
    /// (`text`, `textEn`).
    public static let searchRanking = FTS5Ranking.bm25(weights: [4, 1])

    /// Switches the language without reopening the main database. The new file is validated before
    /// the swap.
    @MainActor
    public func setLanguage(text url: URL) async throws {
        try await database.replace(.text, with: .file(url))
        let meta = try await database.read { reader in
            try reader.fetchOne(TextMeta.all().query())
        }
        guard let meta else { throw SDEError.emptyDatabase }
        guard meta.buildNumber == buildNumber else {
            throw SDEError.buildMismatch(main: buildNumber, text: meta.buildNumber)
        }
        textInfo.withLock { $0 = TextInfo(language: meta.language, tokenizer: meta.tokenizer) }
    }
}
