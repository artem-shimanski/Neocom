//
//  Fixture.swift
//  SDE
//
//  Created by Artem Shimanski on 05.09.2026.
//

import Foundation
import LiteRow
import LiteRowBuild
import SDEKit
import SDEModels

/// A small database laid out like the real one: same models and order of operations, with no
/// dependency on `.SDE`.
///
/// Data: a ship, an unrestricted module, a ship-restricted module and a charge, plus two skills and
/// an implant. Skill B requires A, Rifter (587) requires B.
struct Fixture {
    static let buildNumber = 3284752

    let directory: URL
    let main: URL
    let text: [String: URL]

    struct Name {
        var id: NameID
        var text: String
        var textEn: String
        var ordinal: UInt32
    }

    // Names in two languages to test search; "Rifter" is not translated into Russian.
    static let names: [Name] = [
        .init(id: 0, text: "Rifter", textEn: "Rifter", ordinal: 2),
        .init(id: 1, text: "Малый щитовой расширитель", textEn: "Small Shield Extender", ordinal: 0),
        .init(id: 2, text: "Ионный бластер", textEn: "Ion Blaster", ordinal: 1),
        .init(id: 3, text: "Антивещество", textEn: "Antimatter Charge", ordinal: 3),
    ]

    static let types: [TypeInfo] = [
        TypeInfo(id: 587, groupID: 25, nameID: 0, marketGroupID: 4, published: true),
        TypeInfo(id: 377, groupID: 40, nameID: 1, marketGroupID: 5, metaGroupID: 1, published: true),
        TypeInfo(id: 3178, groupID: 74, nameID: 2, marketGroupID: 6, metaGroupID: 1, published: true),
        TypeInfo(id: 222, groupID: 83, nameID: 3, marketGroupID: 7, published: true),
    ]

    static let items: [DogmaItem] = [
        DogmaItem(id: 587, kind: .ship),
        DogmaItem(id: 377, kind: .med, cpu: 20, power: 12),
        // Ship type restriction: fits only the Rifter.
        DogmaItem(id: 3178, kind: .hi, hardpoint: .turret, cpu: 14, power: 130,
                  hasShipRestrictions: true),
        DogmaItem(id: 222, kind: .charge),
    ]

    /// Market: 1 → 2 → {4, 5, 6, 7}.
    static let marketGroups: [MarketGroupInfo] = [
        MarketGroupInfo(id: 1, nameID: 0),
        MarketGroupInfo(id: 2, parentID: 1, nameID: 0),
        MarketGroupInfo(id: 4, parentID: 2, nameID: 0, hasTypes: true),
        MarketGroupInfo(id: 5, parentID: 2, nameID: 0, hasTypes: true),
        MarketGroupInfo(id: 6, parentID: 2, nameID: 0, hasTypes: true),
        MarketGroupInfo(id: 7, parentID: 1, nameID: 0, hasTypes: true),
    ]

    /// Skill A: rank 1, no requirements.
    static let skillA: TypeID = 3300
    /// Skill B: rank 3, requires A at level 3.
    static let skillB: TypeID = 3301
    /// Implant with a +3 Perception bonus.
    static let implant: TypeID = 3302

    static let skills: [DogmaSkill] = [
        DogmaSkill(id: skillA, rank: 1, primaryAttribute: .perception, secondaryAttribute: .willpower),
        DogmaSkill(id: skillB, rank: 3, primaryAttribute: .intelligence, secondaryAttribute: .memory),
    ]

    static let implantAttributes: [DogmaImplantAttribute] = [
        DogmaImplantAttribute(implantID: implant, attribute: .perception, bonus: 3)
    ]

    /// Skill requirements: B requires A at level 3, Rifter (587) requires B at level 1.
    static let skillRequirements: [DogmaItemSkill] = [
        DogmaItemSkill(itemID: skillB, skillID: skillA, level: 3),
        DogmaItemSkill(itemID: 587, skillID: skillB, level: 1),
    ]

    init(languages: [String] = ["ru", "en"], textBuildNumber: Int? = nil) throws {
        directory = URL(filePath: NSTemporaryDirectory())
            .appending(path: "SDETests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        main = directory.appending(path: "sde.sqlite")

        let builder = try DatabaseBuilder(creating: directory.appending(path: "sde.build.sqlite"))
        try builder.setApplicationID(SDESchema.applicationID)
        try builder.setUserVersion(SDESchema.version)
        try builder.create(Meta.self, filledWith: [
            Meta(buildNumber: Self.buildNumber, releaseDate: "2026-03-31T11:27:11Z")
        ])
        try builder.create(TypeInfo.self, filledWith: Self.types)
        try builder.create(DogmaItem.self, filledWith: Self.items)
        try builder.create(DogmaShip.self, filledWith: [
            DogmaShip(id: 587, hiSlots: 3, medSlots: 3, lowSlots: 4, rigSlots: 3,
                      turretHardpoints: 3, launcherHardpoints: 2,
                      cpuOutput: 130, powerOutput: 41)
        ])
        try builder.create(DogmaItemShipType.self,
                           filledWith: [DogmaItemShipType(itemID: 3178, shipTypeID: 587)],
                           options: .keyOrdered)
        try builder.create(DogmaItemShipGroup.self, filledWith: [], options: .keyOrdered)
        try builder.create(DogmaItemChargeGroup.self,
                           filledWith: [DogmaItemChargeGroup(itemID: 3178, chargeGroupID: 83)],
                           options: .keyOrdered)
        try builder.create(DogmaItemSkill.self, filledWith: Self.skillRequirements, options: .keyOrdered)
        try builder.create(DogmaSkill.self, filledWith: Self.skills)
        try builder.create(DogmaImplantAttribute.self, filledWith: Self.implantAttributes, options: .keyOrdered)
        try builder.create(MarketGroupInfo.self, filledWith: Self.marketGroups)
        try builder.create(MarketGroupTree.self, filledWith: Self.closure(), options: .keyOrdered)
        try builder.createIndexes(TypeInfo.self)
        try builder.createIndexes(DogmaItem.self)
        try builder.createIndexes(DogmaItemShipType.self)
        try builder.createIndexes(DogmaItemChargeGroup.self)
        try builder.createIndexes(DogmaItemSkill.self)
        try builder.createIndexes(DogmaSkill.self)
        try builder.createIndexes(DogmaImplantAttribute.self)
        try builder.analyze()
        try builder.vacuum(into: main)
        builder.close()

        var files: [String: URL] = [:]
        for language in languages {
            let url = directory.appending(path: "text-\(language).sqlite")
            try Self.buildText(
                language: language,
                buildNumber: textBuildNumber ?? Self.buildNumber,
                work: directory.appending(path: "text-\(language).build.sqlite"),
                output: url
            )
            files[language] = url
        }
        text = files
    }

    private static func closure() -> [MarketGroupTree] {
        var parents: [MarketGroupID: MarketGroupID] = [:]
        for group in marketGroups { if let parent = group.parentID { parents[group.id] = parent } }
        var result: [MarketGroupTree] = []
        for group in marketGroups {
            var ancestor: MarketGroupID? = group.id
            var depth = 0
            while let current = ancestor {
                result.append(MarketGroupTree(ancestorID: current, descendantID: group.id, depth: depth))
                ancestor = parents[current]
                depth += 1
            }
        }
        return result
    }

    private static func buildText(
        language: String,
        buildNumber: Int,
        work: URL,
        output: URL
    ) throws {
        let builder = try DatabaseBuilder(creating: work)
        try builder.setApplicationID(SDESchema.applicationID)
        try builder.setUserVersion(SDESchema.version)
        try builder.create(TextMeta.self, filledWith: [
            TextMeta(language: language, buildNumber: buildNumber, tokenizer: .unicode61)
        ])
        try builder.create(DescriptionRow.self, filledWith: [])
        let english = language == "en"
        try builder.create(NameRow.self, filledWith: names.map { name in
            NameRow(
                id: name.id,
                text: english ? name.textEn : name.text,
                // In the English file the second column is empty.
                textEn: english ? "" : name.textEn,
                ordinal: name.ordinal
            )
        })
        // The index is built over a populated table: otherwise `rebuild` produces an empty index.
        let index = FTS5Definition(
            NameSearchIndex.self,
            content: NameRow.self,
            rowID: \.id,
            options: .asYouType
        )
        try builder.create(index)
        try builder.rebuild(index)
        try builder.optimize(index)
        try builder.createIndexes(NameRow.self)
        try builder.analyze()
        try builder.vacuum(into: output)
        builder.close()
    }

    func open(language: String = "ru") async throws -> SDEDatabase {
        try await SDEDatabase(main: main, text: text[language]!)
    }

    func remove() {
        try? FileManager.default.removeItem(at: directory)
    }
}
