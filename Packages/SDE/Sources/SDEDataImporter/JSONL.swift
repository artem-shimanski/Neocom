//
//  JSONL.swift
//  SDE
//
//  Created by Artem Shimanski on 05.09.2026.
//

import Foundation

enum ImportError: Error, CustomStringConvertible {
    case cannotOpen(URL)
    case malformedLine(URL, Int)
    case missing(String)

    var description: String {
        switch self {
        case let .cannotOpen(url): "не удалось открыть \(url.path(percentEncoded: false))"
        case let .malformedLine(url, line): "\(url.lastPathComponent):\(line) — строка не разбирается"
        case let .missing(what): "в выгрузке нет \(what)"
        }
    }
}

/// Line-by-line JSONL reading without an intermediate collection.
///
/// The file is read in chunks and split on `\n`; large files are processed as a stream, small ones
/// are collected into a dictionary. Reading is synchronous.
enum JSONL {
    /// Chunk size.
    private static let chunkSize = 4 << 20

    static func forEach<T: Decodable>(
        _ type: T.Type,
        at url: URL,
        _ body: (T) throws -> Void
    ) throws {
        guard let handle = try? FileHandle(forReadingFrom: url) else {
            throw ImportError.cannotOpen(url)
        }
        defer { try? handle.close() }

        let decoder = JSONDecoder()
        var tail = Data()
        var lineNumber = 0

        // The remainder of a chunk without a line boundary is carried to the start of the next.
        while let chunk = try handle.read(upToCount: chunkSize), !chunk.isEmpty {
            var data = tail
            data.append(chunk)
            var start = data.startIndex
            while let newline = data[start...].firstIndex(of: 0x0A) {
                try decode(data[start..<newline], into: &lineNumber, at: url, with: decoder, body)
                start = data.index(after: newline)
            }
            tail = Data(data[start...])
        }
        if !tail.isEmpty {
            try decode(tail[...], into: &lineNumber, at: url, with: decoder, body)
        }
    }

    private static func decode<T: Decodable>(
        _ line: Data.SubSequence,
        into lineNumber: inout Int,
        at url: URL,
        with decoder: JSONDecoder,
        _ body: (T) throws -> Void
    ) throws {
        lineNumber += 1
        guard line.contains(where: { $0 != 0x20 && $0 != 0x0D && $0 != 0x09 }) else { return }
        let object: T
        do { object = try decoder.decode(T.self, from: Data(line)) }
        catch { throw ImportError.malformedLine(url, lineNumber) }
        try body(object)
    }

    /// The whole file as a dictionary, for reference tables that need random access.
    static func dictionary<T: Decodable, Key: Hashable>(
        _ type: T.Type,
        at url: URL,
        key: (T) -> Key
    ) throws -> [Key: T] {
        var result: [Key: T] = [:]
        try forEach(T.self, at: url) { result[key($0)] = $0 }
        return result
    }

    static func array<T: Decodable>(_ type: T.Type, at url: URL) throws -> [T] {
        var result: [T] = []
        try forEach(T.self, at: url) { result.append($0) }
        return result
    }
}
