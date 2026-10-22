//
//  main.swift
//  SDE
//
//  Created by Artem Shimanski on 23.08.2026.
//

import Foundation

// Builds a set of files from an SDE dump:
//
//     SDEDataImporter <.SDE directory> <build directory> [--icons <PNG directory>] [language …]
//
// Without a language list all eight are built.

var arguments = CommandLine.arguments
// `--icons <directory>` is removed before positional arguments are parsed.
var iconsDirectory: URL?
if let index = arguments.firstIndex(of: "--icons") {
    guard index + 1 < arguments.count else {
        FileHandle.standardError.write(Data("после --icons ожидается каталог\n".utf8))
        exit(2)
    }
    iconsDirectory = URL(filePath: arguments[index + 1])
    arguments.removeSubrange(index...(index + 1))
}

guard arguments.count >= 3 else {
    FileHandle.standardError.write(Data("""
        использование: SDEDataImporter <каталог .SDE> <каталог сборки> [язык …]
        языки: \(Language.allCases.map(\.rawValue).joined(separator: ", "))

        """.utf8))
    exit(2)
}

let input = URL(filePath: arguments[1])
let output = URL(filePath: arguments[2])
let requested = arguments.dropFirst(3)

let languages: [Language]
if requested.isEmpty {
    languages = Language.allCases
}
else {
    languages = requested.map { name in
        guard let language = Language(rawValue: name) else {
            FileHandle.standardError.write(Data("неизвестный язык: \(name)\n".utf8))
            exit(2)
        }
        return language
    }
}

do {
    print("SDE: \(input.path(percentEncoded: false))")
    print("языки: \(languages.map(\.rawValue).joined(separator: ", "))")
    let start = ContinuousClock.now
    let importer = try Importer(sde: input, output: output, languages: languages, icons: iconsDirectory)
    try importer.run()
    let elapsed = ContinuousClock.now - start
    print("готово за \(elapsed.formatted(.units(allowed: [.minutes, .seconds])))")
}
catch {
    FileHandle.standardError.write(Data("ошибка: \(error)\n".utf8))
    exit(1)
}
