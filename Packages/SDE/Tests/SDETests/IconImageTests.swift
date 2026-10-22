//
//  IconImageTests.swift
//  SDE
//

import Foundation
import LiteRow
import LiteRowBuild
import SDEKit
import SDEModels
import Testing
@testable import SDEDataImporter

@Suite("PNG-иконки рынка")
struct IconImageTests {
    private let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 1, 2, 3])

    @Test("иконка с файлом попадает в таблицу, без файла и вне префикса — нет")
    func importerMatching() throws {
        let directory = URL(filePath: NSTemporaryDirectory()).appending(path: "icons-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: directory.appending(path: "Inventory"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try png.write(to: directory.appending(path: "7_64_15.png"))
        try png.write(to: directory.appending(path: "Inventory/foo.png"))

        let result = IconImages.load(
            iconFiles: [
                1: "res:/ui/texture/icons/7_64_15.png",
                2: "res:/UI/Texture/Icons/inventory/FOO.png",
                3: "res:/ui/texture/icons/9_9_9.png",
                4: "res:/ui/texture/corps/x.png",
            ],
            wanted: [1, 2, 3, 4, 5],
            directory: directory
        )
        #expect(result.rows.map(\.id) == [1, 2])
        #expect(result.rows.allSatisfy { $0.png == png })
        #expect(result.missing == 3)
    }

    @Test("запрос SDEQuery.iconImage читает блоб; для иконки без картинки пусто")
    func query() async throws {
        let directory = URL(filePath: NSTemporaryDirectory()).appending(path: "iconq-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appending(path: "icons.sqlite")
        let builder = try DatabaseBuilder(creating: directory.appending(path: "icons.build.sqlite"))
        try builder.create(IconImage.self, filledWith: [IconImage(id: 1, png: png)])
        try builder.vacuum(into: file)
        builder.close()

        let database = try Database(main: file)
        let found = try await database.read { try $0.fetchAll(SDEQuery.iconImage(1)) }
        let absent = try await database.read { try $0.fetchAll(SDEQuery.iconImage(2)) }
        #expect(found.first?.png == png)
        #expect(absent.isEmpty)
    }
}
