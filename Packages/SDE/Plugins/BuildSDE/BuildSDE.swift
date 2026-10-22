//
//  BuildSDE.swift
//  SDE
//

import Foundation
import PackagePlugin

/// Full build of the databases from an SDE dump, from the Xcode context menu or the terminal.
///
/// ```bash
/// swift package --allow-writing-to-package-directory build-sde        # all eight languages
/// swift package --allow-writing-to-package-directory build-sde ru en  # only these two
/// ```
///
/// The importer writes to a single directory, so the build runs in the plugin's work directory and
/// the files are distributed to `Sources/SDEData*/Data` as a separate step: a failed build leaves
/// no half set in the targets.
@main
struct BuildSDEPlugin: CommandPlugin {
    /// Languages that have targets in the package; matches `Package.swift` and the importer's
    /// `Language`.
    static let languages = ["de", "en", "es", "fr", "ja", "ko", "ru", "zh"]

    func performCommand(context: PluginContext, arguments: [String]) async throws {
        let packageURL = context.package.directoryURL
        let options = try Options(arguments: arguments)
        let languages = options.languages.isEmpty ? Self.languages : options.languages

        let sde = try options.sde.map { URL(filePath: $0) }
            ?? Self.sdeDirectory(package: packageURL)
        // `_sde.jsonl` distinguishes a dump from an empty directory.
        guard FileManager.default.fileExists(
            atPath: sde.appending(path: "_sde.jsonl").path(percentEncoded: false)
        ) else {
            throw PluginError("в каталоге выгрузки нет _sde.jsonl: \(sde.path(percentEncoded: false))")
        }

        let icons = Self.iconsDirectory(package: packageURL)

        let work = context.pluginWorkDirectoryURL.appending(path: "SDEBuild")
        try? FileManager.default.removeItem(at: work)
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)

        print("выгрузка: \(sde.path(percentEncoded: false))")
        print("языки:    \(languages.joined(separator: ", "))")

        let importer = try context.tool(named: "SDEDataImporter")
        try Self.run(
            importer.url,
            arguments: [sde.path(percentEncoded: false), work.path(percentEncoded: false)]
                + (icons.map { ["--icons", $0.path(percentEncoded: false)] } ?? [])
                + languages
        )

        try Self.place(
            work.appending(path: "sde.sqlite"),
            into: packageURL.appending(path: "Sources/SDEDataMain/Data")
        )
        for language in languages {
            try Self.place(
                work.appending(path: "text-\(language).sqlite"),
                into: packageURL.appending(path: "Sources/SDEData\(language.uppercased())/Data")
            )
        }
        try? FileManager.default.removeItem(at: work)
    }

    // MARK: - Arguments

    /// Command-line parsing.
    ///
    /// `--target <name>` pairs passed by Xcode are skipped: the target does not affect the build,
    /// but the name would end up in the language list.
    struct Options {
        var languages: [String] = []
        var sde: String?

        init(arguments: [String]) throws {
            var rest = arguments[...]
            while let argument = rest.popFirst() {
                switch argument {
                case "--target":
                    _ = rest.popFirst()
                case "--sde":
                    guard let value = rest.popFirst() else {
                        throw PluginError("после --sde ожидается путь к каталогу выгрузки")
                    }
                    sde = value
                case let language where BuildSDEPlugin.languages.contains(language):
                    languages.append(language)
                default:
                    throw PluginError(
                        "неизвестный аргумент «\(argument)»; языки: "
                            + BuildSDEPlugin.languages.joined(separator: ", ")
                    )
                }
            }
        }
    }

    // MARK: - Dump location

    private struct Config: Decodable {
        var sde: String
        /// Optional directory of PNG icons (not in git, like `.SDE`).
        var icons: String?
    }

    /// Icon directory from `.sde-config.json`; no key or no config means no icons.
    private static func iconsDirectory(package: URL) -> URL? {
        let configURL = package.appending(path: ".sde-config.json")
        guard let data = try? Data(contentsOf: configURL),
              let path = try? JSONDecoder().decode(Config.self, from: data).icons
        else { return nil }
        return path.hasPrefix("/") ? URL(filePath: path) : package.appending(path: path)
    }

    /// Dump path from `.sde-config.json`; a relative path is resolved from the package root.
    private static func sdeDirectory(package: URL) throws -> URL {
        let configURL = package.appending(path: ".sde-config.json")
        guard let data = try? Data(contentsOf: configURL) else {
            throw PluginError("не читается \(configURL.path(percentEncoded: false))")
        }
        let config = try JSONDecoder().decode(Config.self, from: data)
        let path = config.sde
        return path.hasPrefix("/") ? URL(filePath: path) : package.appending(path: path)
    }

    // MARK: - Running the importer

    private static func run(_ tool: URL, arguments: [String]) throws {
        let process = Process()
        process.executableURL = tool
        process.arguments = arguments
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw PluginError("импортёр завершился с кодом \(process.terminationStatus)")
        }
    }

    // MARK: - Distribution to targets

    /// Moves one finished file into the target's resources.
    ///
    /// A move, not a copy: the files weigh tens of megabytes; `moveItem` fails across volumes, in
    /// which case the file is copied.
    private static func place(_ file: URL, into directory: URL) throws {
        let manager = FileManager.default
        guard manager.fileExists(atPath: file.path(percentEncoded: false)) else {
            throw PluginError("импортёр не создал \(file.lastPathComponent)")
        }
        try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = directory.appending(path: file.lastPathComponent)
        if manager.fileExists(atPath: destination.path(percentEncoded: false)) {
            try manager.removeItem(at: destination)
        }
        do { try manager.moveItem(at: file, to: destination) }
        catch { try manager.copyItem(at: file, to: destination) }

        let size = (try? destination.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        let megabytes = Double(size) / 1_048_576
        print(
            "  \(destination.lastPathComponent) → \(directory.lastPathComponent(of: 2)) "
                + "(\(megabytes.formatted(.number.precision(.fractionLength(1)))) МБ)"
        )
    }
}

private extension URL {
    /// The last `count` path components, for the log.
    func lastPathComponent(of count: Int) -> String {
        pathComponents.suffix(count).joined(separator: "/")
    }
}

struct PluginError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}
