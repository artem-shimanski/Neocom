//
//  Importer+Icons.swift
//  SDE
//

import Foundation
import LiteRow
import LiteRowBuild
import SDEModels

/// Matching PNG files to icons.
enum IconImages {
    /// Prefix of `icons.iconFile` paths; icons outside it have no file.
    static let prefix = "res:/ui/texture/icons/"

    /// Finds the file of each icon from `wanted` in `directory`.
    ///
    /// The path after the prefix is compared case-insensitively.
    static func load(
        iconFiles: [IconID: String],
        wanted: Set<IconID>,
        directory: URL
    ) -> (rows: [IconImage], missing: Int) {
        var files: [String: URL] = [:]
        let root = directory.standardizedFileURL.resolvingSymlinksInPath()
        let rootComponents = root.pathComponents.count
        if let walker = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: [.isRegularFileKey]
        ) {
            for case let url as URL in walker {
                guard (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { continue }
                let relative = url.resolvingSymlinksInPath().pathComponents.dropFirst(rootComponents)
                files[relative.joined(separator: "/").lowercased()] = url
            }
        }

        var rows: [IconImage] = []
        var missing = 0
        for id in wanted.sorted(by: { $0.rawValue < $1.rawValue }) {
            guard let file = iconFiles[id],
                  file.lowercased().hasPrefix(prefix),
                  let url = files[String(file.dropFirst(prefix.count)).lowercased()],
                  let png = try? Data(contentsOf: url)
            else {
                missing += 1
                continue
            }
            rows.append(IconImage(id: id, png: png))
        }
        return (rows, missing)
    }
}

extension Importer {
    /// The `iconImages` table: PNGs for icons referenced by market groups.
    func importIconImages(marketIcons: Set<IconID>) throws {
        var rows: [IconImage] = []
        if let directory = iconsDirectory,
           FileManager.default.fileExists(atPath: directory.path(percentEncoded: false)) {
            let raw = try JSONL.array(IconInfo.self, at: url("icons"))
            var iconFiles: [IconID: String] = [:]
            for icon in raw {
                if let id = UInt16(exactly: icon._key) { iconFiles[IconID(rawValue: id)] = icon.iconFile }
            }
            let result = IconImages.load(iconFiles: iconFiles, wanted: marketIcons, directory: directory)
            rows = result.rows
            print("иконки рынка: найдено \(rows.count), без файла \(result.missing)")
        }
        else {
            print("предупреждение: каталог иконок не задан или не найден — iconImages будет пустой")
        }
        try main.create(IconImage.self, filledWith: rows)
    }
}
