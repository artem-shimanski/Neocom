//
//  Text.swift
//  SDE
//
//  Created by Artem Shimanski on 04.09.2026.
//

import LiteRow

extension DatabaseFile {
    /// The language file is the only attached database; the schema is the same for all languages.
    public static let text = DatabaseFile(schemaName: "text")
}

/// Short string that is displayed and searched.
///
/// `textEn` allows searching in the native language and English at once with one query and one
/// ranking; in `text-en.sqlite` the column is empty.
///
/// `ordinal` is the name's position in this language's alphabet, computed at build time; list
/// sorting uses it, not the text.
@Table("names", schema: .text)
public struct NameRow: Identifiable {
    @PrimaryKey public var id: NameID
    public var text: String
    public var textEn: String = ""
    @Index public var ordinal: UInt32 = 0
}

/// Long text: type description, ship bonus text, attribute hint.
///
/// A separate table, to stay off the pages scanned when iterating a list; not in the search index.
/// The text comes from SDE as is, with markup like `<a href=showinfo:3302>`.
@Table("descriptions", schema: .text)
public struct DescriptionRow: Identifiable {
    @PrimaryKey public var id: DescriptionID
    public var text: String
}

/// Search index over `names` (fts5, external content).
///
/// Column names match the content table's columns; column order is the weight order in
/// `FTS5Ranking.bm25(weights:)`.
@Table("names_fts", schema: .text)
public struct NameSearchIndex {
    public var text: String
    public var textEn: String
}

/// Tokenizer of the language file's search index.
///
/// Written at build time; determines the pattern factory: `unicode61` —
/// `FTS5Pattern.all(_:prefix:)`, `trigram` (Chinese, Japanese) — `FTS5Pattern.phrase(_:)`.
public enum TextTokenizer: String, Sendable, Hashable, SQLiteValue {
    case unicode61
    case trigram
}

/// The only row of the language file: language and build.
///
/// String IDs are assigned by the main database build, so `buildNumber` is checked on open.
@Table("meta", schema: .text)
public struct TextMeta: Identifiable {
    @PrimaryKey public var id: Int = 0
    public var language: String
    public var buildNumber: Int
    public var tokenizer: TextTokenizer
}
