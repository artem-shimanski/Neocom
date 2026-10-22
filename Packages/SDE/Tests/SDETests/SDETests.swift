//
//  SDETests.swift
//  SDE
//

import Foundation
import LiteRow
import SDEKit
import SDEModels
import Testing

@Suite("Открытие набора")
struct OpenTests {
    @Test("сборки основного и языкового файла сверяются при открытии")
    func buildMismatch() async throws {
        let fixture = try Fixture(languages: ["ru"], textBuildNumber: Fixture.buildNumber - 1)
        defer { fixture.remove() }

        await #expect(throws: SDEError.self) {
            _ = try await fixture.open()
        }
    }

    @Test("совпадающие сборки открываются, язык и токенайзер читаются из meta")
    func opens() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }

        let sde = try await fixture.open(language: "ru")
        #expect(sde.language == "ru")
        #expect(sde.tokenizer == .unicode61)
        #expect(sde.buildNumber == Fixture.buildNumber)
    }

    @Test("смена языка не переоткрывает основную базу")
    @MainActor
    func changeLanguage() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }

        let sde = try await fixture.open(language: "ru")
        let revision = sde.database.revision
        try await sde.setLanguage(text: fixture.text["en"]!)
        #expect(sde.language == "en")
        #expect(sde.database.revision > revision)

        let rows = try await sde.database.read { reader in
            try reader.fetchAll(SDEQuery.items(kind: .med))
        }
        #expect(rows.first?.name == "Small Shield Extender")
    }
}

@Suite("Поиск")
struct SearchTests {
    @Test("на своём языке и на английском — одним запросом")
    func bothLanguages() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let sde = try await fixture.open(language: "ru")

        // An English query finds the name in the `textEn` column of the same file.
        let byEnglish = try await search(sde, "shield ext")
        #expect(byEnglish.map(\.id) == [377])

        let byRussian = try await search(sde, "щитово")
        #expect(byRussian.map(\.id) == [377])
    }

    @Test("ввод без токенов — это не ошибка базы, а пустой результат")
    func emptyInput() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let sde = try await fixture.open()

        // An empty parse result is `nil`: `???` is a syntax error for fts5.
        #expect(sde.pattern("???") == nil)
    }

    @Test("ввод с дефисом не ломает запрос")
    func punctuation() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let sde = try await fixture.open()

        // Without escaping, the `-` in `Ion-Blaster` would cause `fts5: syntax error`.
        let rows = try await search(sde, "Ion-Blaster")
        #expect(rows.map(\.id) == [3178])
    }

    @Test("фильтр по виду сужает поиск")
    func kindFilter() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let sde = try await fixture.open()

        let all = try await search(sde, "Antimatter")
        #expect(all.map(\.id) == [222])
        #expect(try await search(sde, "Antimatter", kind: .charge).map(\.id) == [222])
        #expect(try await search(sde, "Antimatter", kind: .med).isEmpty)
    }

    private func search(
        _ sde: SDEDatabase,
        _ input: String,
        kind: DogmaItemKind? = nil
    ) async throws -> [ItemListRow] {
        guard let pattern = sde.pattern(input) else { return [] }
        return try await sde.database.read { reader in
            try reader.fetchAll(SDEQuery.search(pattern, kind: kind))
        }
    }
}

@Suite("Просмотр")
struct BrowseTests {
    @Test("список сортируется по алфавиту языка, а не по тексту")
    func ordinalOrder() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let sde = try await fixture.open(language: "ru")

        // Ordered by `ordinal` (Russian alphabet), not by text.
        let rows = try await sde.database.read { reader in
            try reader.fetchAll(SDEQuery.items(inMarketGroup: 1))
        }
        #expect(rows.map(\.id) == [377, 3178, 587, 222])
    }

    @Test("рыночная группа отдаёт и внуков")
    func marketSubtree() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let sde = try await fixture.open()

        let underRoot = try await sde.database.read { reader in
            try reader.fetchAll(SDEQuery.items(inMarketGroup: 1))
        }
        let underBranch = try await sde.database.read { reader in
            try reader.fetchAll(SDEQuery.items(inMarketGroup: 2))
        }
        #expect(underRoot.count == 4)
        // Group 2 contains 4, 5, 6 but not 7: it hangs off the root.
        #expect(Set(underBranch.map(\.id)) == [587, 377, 3178])
    }

    @Test("отсутствие ограничений означает «подходит всем», а не «данных нет»")
    func restrictions() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let sde = try await fixture.open()

        let intoRifter = try await sde.database.read { reader in
            try reader.fetchAll(SDEQuery.items(kind: .hi, fitting: 587, of: 25))
        }
        #expect(intoRifter.map(\.id) == [3178])

        let intoOther = try await sde.database.read { reader in
            try reader.fetchAll(SDEQuery.items(kind: .hi, fitting: 999, of: 26))
        }
        #expect(intoOther.isEmpty)

        let unrestricted = try await sde.database.read { reader in
            try reader.fetchAll(SDEQuery.items(kind: .med, fitting: 999, of: 26))
        }
        #expect(unrestricted.map(\.id) == [377])
    }

    @Test("заряды модуля берутся по группе заряда")
    func charges() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let sde = try await fixture.open()

        let rows = try await sde.database.read { reader in
            try reader.fetchAll(SDEQuery.charges(for: 3178))
        }
        #expect(rows.map(\.id) == [222])
    }

    @Test("краткое описание корабля приезжает одним запросом")
    func shipSummary() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let sde = try await fixture.open(language: "en")

        let rows = try await sde.database.read { reader in
            try reader.fetchAll(SDEQuery.ships(inMarketGroup: 1))
        }
        let rifter = try #require(rows.first)
        #expect(rifter.name == "Rifter")
        #expect(rifter.hiSlots == 3)
        #expect(rifter.medSlots == 3)
        #expect(rifter.lowSlots == 4)
        #expect(rifter.cpuOutput == 130)
        #expect(rifter.powerOutput == 41)
    }
}

@Suite("Навыки и импланты")
struct SkillTests {
    @Test("DogmaSkill читается по id и отдаёт ранг и оба атрибута")
    func skillByID() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let sde = try await fixture.open()

        let row = try await sde.database.read { reader in
            try reader.fetchOne(DogmaSkill.self, key: Fixture.skillB)
        }
        let skill = try #require(row)
        #expect(skill.rank == 3)
        #expect(skill.primaryAttribute == .intelligence)
        #expect(skill.secondaryAttribute == .memory)
    }

    @Test("DogmaItemSkill по itemID навыка B отдаёт требование навыка A третьего уровня")
    func skillPrerequisite() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let sde = try await fixture.open()

        // Skill prerequisites live in the same table as fit requirements.
        let rows = try await sde.database.read { reader in
            try reader.fetchAll(DogmaItemSkill.all().filter { row in row.itemID == Fixture.skillB }.query())
        }
        #expect(rows.map(\.skillID) == [Fixture.skillA])
        #expect(rows.map(\.level) == [3])
    }

    @Test("DogmaImplantAttribute по implantID отдаёт +3 к перцепции")
    func implantBonus() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let sde = try await fixture.open()

        let rows = try await sde.database.read { reader in
            try reader.fetchAll(DogmaImplantAttribute.all().filter { row in row.implantID == Fixture.implant }.query())
        }
        #expect(rows.map(\.attribute) == [.perception])
        #expect(rows.map(\.bonus) == [3])
    }
}
