//
//  Importer.swift
//  SDE
//
//  Created by Artem Shimanski on 05.09.2026.
//

import Foundation
import LiteRow
import LiteRowBuild
import SDEModels

// Raw schema names (`TypeInfo`, `GroupInfo`, …) shadow same-named SDEModels models, so the models
// get aliases; an unqualified `TypeInfo` is a JSONL row.
typealias TypeRow = SDEModels.TypeInfo
typealias GroupRow = SDEModels.GroupInfo
typealias CategoryRow = SDEModels.CategoryInfo
typealias MarketGroupRow = SDEModels.MarketGroupInfo
typealias MetaGroupRow = SDEModels.MetaGroupInfo
typealias IconRow = SDEModels.IconInfo
typealias RaceRow = SDEModels.RaceInfo
typealias BloodlineRow = SDEModels.BloodlineInfo
typealias AncestryRow = SDEModels.AncestryInfo
typealias CharacterAttributeRow = SDEModels.CharacterAttributeInfo
typealias CloneGradeRow = SDEModels.CloneGradeInfo
typealias CertificateRow = SDEModels.CertificateInfo
typealias FactionRow = SDEModels.FactionInfo
typealias RegionRow = SDEModels.RegionInfo
typealias ConstellationRow = SDEModels.ConstellationInfo
typealias SolarSystemRow = SDEModels.SolarSystemInfo
typealias DogmaAttributeRow = SDEModels.DogmaAttributeInfo
typealias DogmaAttributeCategoryRow = SDEModels.DogmaAttributeCategoryInfo
typealias DogmaEffectRow = SDEModels.DogmaEffectInfo
typealias DogmaUnitRow = SDEModels.DogmaUnitInfo
typealias DbuffCollectionRow = SDEModels.DbuffCollectionInfo
typealias BlueprintRow = SDEModels.BlueprintInfo
typealias PlanetSchematicRow = SDEModels.PlanetSchematicInfo
typealias StationOperationRow = SDEModels.StationOperationInfo
typealias StationServiceRow = SDEModels.StationServiceInfo
typealias CorporationActivityRow = SDEModels.CorporationActivityInfo
typealias DynamicItemAttributeRow = SDEModels.DynamicItemAttributeInfo
typealias CompressibleTypeRow = SDEModels.CompressibleTypeInfo

final class Importer {
    let sde: URL
    let output: URL
    let languages: [Language]
    /// PNG icon directory; without it the `iconImages` table stays empty.
    let iconsDirectory: URL?

    let main: DatabaseBuilder
    let textBuilder: TextBuilder

    var names = DogmaNames()
    var dogma: [TypeID: DogmaRecord] = [:]
    var groups: [GroupID: GroupInfo] = [:]
    var categories: [CategoryID: CategoryInfo] = [:]
    /// Groups whose types may enter the database unpublished.
    var exceptionGroups: Set<GroupID> = []
    var planetaryGroups: Set<GroupID> = []
    var modeGroup: GroupID?
    var planetGroup: GroupID?

    /// Selected types with the data needed by derived tables.
    var keptTypes: [TypeID: KeptType] = [:]
    var sortedTypes: [TypeID] = []

    init(sde: URL, output: URL, languages: [Language], icons: URL? = nil) throws {
        self.sde = sde
        self.iconsDirectory = icons
        self.output = output
        self.languages = languages

        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        main = try DatabaseBuilder(creating: output.appending(path: "sde.build.sqlite"))

        var textBuilders: [Language: DatabaseBuilder] = [:]
        for language in languages {
            textBuilders[language] = try DatabaseBuilder(
                creating: output.appending(path: "text-\(language.rawValue).build.sqlite")
            )
        }
        textBuilder = try TextBuilder(languages: languages, builders: textBuilders)
    }

    func url(_ file: String) -> URL { sde.appending(path: file + ".jsonl") }

    // MARK: - Build

    func run() throws {
        try main.setApplicationID(SDESchema.applicationID)
        try main.setUserVersion(SDESchema.version)

        let version = try step("версия") { try importVersion() }
        try step("справочники dogma") { try importDogmaReference() }
        try step("категории и группы") { try importGroups() }
        try step("dogma типов") { try loadTypeDogma() }
        try step("типы") { try importTypes() }
        try step("рынок") { try importMarket() }
        try step("бонусы кораблей") { try importTraits() }
        try step("материалы") { try importMaterials() }
        try step("мутаплазмиды") { try importMutaplasmids() }
        try step("персонаж") { try importCharacter() }
        try step("сертификаты") { try importCertificates() }
        try step("промышленность") { try importIndustry() }
        try step("планетарка") { try importPlanetary() }
        try step("станции") { try importStations() }
        try step("карта") { try importUniverse() }
        try step("таблицы фитинга") { try importFitting() }
        try step("навыки") { try importSkills() }

        try step("индексы") {
            try createIndexes()
            try main.analyze()
        }
        try step("основной файл") {
            try main.vacuum(into: output.appending(path: "sde.sqlite"))
            main.close()
        }
        try step("языковые файлы") {
            try textBuilder.finish(buildNumber: version.buildNumber, output: output)
        }
        try removeIntermediates()
    }

    private func step<T>(_ title: String, _ body: () throws -> T) rethrows -> T {
        let start = ContinuousClock.now
        let result = try body()
        let elapsed = ContinuousClock.now - start
        let seconds = Double(elapsed.components.seconds)
            + Double(elapsed.components.attoseconds) / 1e18
        // Padded by character count: printf width counts bytes.
        let padded = title.padding(toLength: max(title.count, 22), withPad: " ", startingAt: 0)
        print("  \(padded) \(seconds.formatted(.number.precision(.fractionLength(2)))) c")
        return result
    }

    /// Intermediate build files; the finished file is produced only via `VACUUM INTO`.
    private func removeIntermediates() throws {
        let manager = FileManager.default
        for name in ["sde.build.sqlite"] + languages.map({ "text-\($0.rawValue).build.sqlite" }) {
            for suffix in ["", "-wal", "-shm", "-journal"] {
                let url = output.appending(path: name + suffix)
                if manager.fileExists(atPath: url.path(percentEncoded: false)) {
                    try manager.removeItem(at: url)
                }
            }
        }
    }

    // MARK: - Version

    private func importVersion() throws -> Meta {
        guard let raw = try JSONL.array(_sdeInfo.self, at: url("_sde")).first else {
            throw ImportError.missing("_sde.jsonl")
        }
        let meta = Meta(buildNumber: raw.buildNumber, releaseDate: raw.releaseDate)
        try main.create(Meta.self, filledWith: [meta])
        return meta
    }

    // MARK: - Dogma reference tables

    private func importDogmaReference() throws {
        let categories = try JSONL.array(DogmaAttributeCategoryInfo.self, at: url("dogmaAttributeCategories"))
        try main.create(DogmaAttributeCategoryRow.self, filledWith: categories.map {
            DogmaAttributeCategoryRow(
                id: AttributeCategoryID(rawValue: UInt16($0._key)),
                name: $0.name,
                descriptionID: $0.description.map { textBuilder.description(Localized(same: $0)) }
            )
        })

        let attributes = try JSONL.array(DogmaAttributeInfo.self, at: url("dogmaAttributes"))
        for attribute in attributes {
            names.attributes[attribute.name] = AttributeID(rawValue: UInt16(attribute._key))
        }
        try main.create(DogmaAttributeRow.self, filledWith: attributes.map { raw in
            DogmaAttributeRow(
                id: AttributeID(rawValue: UInt16(raw._key)),
                name: raw.name,
                displayNameID: textBuilder.name(raw.displayName?.localized),
                descriptionID: raw.description.map { textBuilder.description(Localized(same: $0)) },
                tooltipTitleID: textBuilder.name(raw.tooltipTitle?.localized),
                tooltipDescriptionID: textBuilder.description(raw.tooltipDescription?.localized),
                attributeCategoryID: raw.attributeCategoryID.map { AttributeCategoryID(rawValue: UInt16($0)) },
                unitID: raw.unitID.map { UnitID(rawValue: UInt16($0)) },
                iconID: raw.iconID.map { IconID(rawValue: UInt16($0)) },
                defaultValue: raw.defaultValue,
                minAttributeID: raw.minAttributeID.map { AttributeID(rawValue: UInt16($0)) },
                maxAttributeID: raw.maxAttributeID.map { AttributeID(rawValue: UInt16($0)) },
                chargeRechargeTimeID: raw.chargeRechargeTimeID.map { AttributeID(rawValue: UInt16($0)) },
                dataType: raw.dataType,
                displayWhenZero: raw.displayWhenZero,
                highIsGood: raw.highIsGood,
                stackable: raw.stackable,
                published: raw.published
            )
        })

        let units = try JSONL.array(DogmaUnitInfo.self, at: url("dogmaUnits"))
        try main.create(DogmaUnitRow.self, filledWith: units.map { raw in
            DogmaUnitRow(
                id: UnitID(rawValue: UInt16(raw._key)),
                name: raw.name,
                displayNameID: textBuilder.name(raw.displayName?.localized),
                descriptionID: textBuilder.description(raw.description?.localized)
            )
        })

        try importEffects()
    }

    private func importEffects() throws {
        let effects = try JSONL.array(EffectRecord.self, at: url("dogmaEffects"))
        for effect in effects {
            names.effects[effect.name] = EffectID(rawValue: UInt16(effect._key))
        }
        try main.create(DogmaEffectRow.self, filledWith: effects.map { raw in
            DogmaEffectRow(
                id: EffectID(rawValue: UInt16(raw._key)),
                name: raw.name,
                displayNameID: textBuilder.name(raw.displayName?.localized),
                descriptionID: textBuilder.description(raw.description?.localized),
                effectCategoryID: raw.effectCategoryID,
                iconID: raw.iconID.map { IconID(rawValue: UInt16($0)) },
                guid: raw.guid,
                dischargeAttributeID: raw.dischargeAttributeID.map { AttributeID(rawValue: UInt16($0)) },
                durationAttributeID: raw.durationAttributeID.map { AttributeID(rawValue: UInt16($0)) },
                falloffAttributeID: raw.falloffAttributeID.map { AttributeID(rawValue: UInt16($0)) },
                rangeAttributeID: raw.rangeAttributeID.map { AttributeID(rawValue: UInt16($0)) },
                trackingSpeedAttributeID: raw.trackingSpeedAttributeID.map { AttributeID(rawValue: UInt16($0)) },
                resistanceAttributeID: raw.resistanceAttributeID.map { AttributeID(rawValue: UInt16($0)) },
                fittingUsageChanceAttributeID: raw.fittingUsageChanceAttributeID.map { AttributeID(rawValue: UInt16($0)) },
                npcActivationChanceAttributeID: raw.npcActivationChanceAttributeID.map { AttributeID(rawValue: UInt16($0)) },
                npcUsageChanceAttributeID: raw.npcUsageChanceAttributeID.map { AttributeID(rawValue: UInt16($0)) },
                distribution: raw.distribution,
                disallowAutoRepeat: raw.disallowAutoRepeat,
                electronicChance: raw.electronicChance,
                isAssistance: raw.isAssistance,
                isOffensive: raw.isOffensive,
                isWarpSafe: raw.isWarpSafe,
                propulsionChance: raw.propulsionChance,
                rangeChance: raw.rangeChance,
                published: raw.published
            )
        })

        var modifiers: [DogmaEffectModifier] = []
        for effect in effects {
            for (index, modifier) in (effect.modifierInfo ?? []).enumerated() {
                guard let function = ModifierFunction(sdeName: modifier.function) else {
                    // An unknown modifier kind is a new game mechanism; skipping it would yield an
                    // effect that does nothing.
                    throw ImportError.missing("вид модификатора «\(modifier.function)» (эффект \(effect._key))")
                }
                modifiers.append(DogmaEffectModifier(
                    effectID: EffectID(rawValue: UInt16(effect._key)),
                    index: index,
                    function: function,
                    domain: modifier.domain,
                    modifiedAttributeID: modifier.modifiedAttributeID.map { AttributeID(rawValue: UInt16($0)) },
                    modifyingAttributeID: modifier.modifyingAttributeID.map { AttributeID(rawValue: UInt16($0)) },
                    operation: modifier.operation,
                    groupID: modifier.groupID.flatMap { UInt16(exactly: $0).map(GroupID.init(rawValue:)) },
                    skillTypeID: modifier.skillTypeID.map { TypeID(rawValue: UInt32($0)) },
                    stoppedEffectID: modifier.effectID.map { EffectID(rawValue: UInt16($0)) }
                ))
            }
        }
        try main.create(DogmaEffectModifier.self, filledWith: modifiers, options: .keyOrdered)

        try importWarfareBuffs()
    }

    private func importWarfareBuffs() throws {
        let buffs = try JSONL.array(DbuffCollectionInfo.self, at: url("dbuffCollections"))
        try main.create(DbuffCollectionRow.self, filledWith: buffs.map { raw in
            DbuffCollectionRow(
                id: WarfareBuffID(rawValue: UInt16(raw._key)),
                displayNameID: textBuilder.name(raw.displayName?.localized),
                developerDescription: raw.developerDescription,
                aggregateMode: raw.aggregateMode,
                operationName: raw.operationName,
                showOutputValueInUI: raw.showOutputValueInUI
            )
        })

        try main.create(DbuffItemModifier.self, filledWith: buffs.flatMap { raw in
            (raw.itemModifiers ?? []).map {
                DbuffItemModifier(buffID: WarfareBuffID(rawValue: UInt16(raw._key)),
                                  attributeID: AttributeID(rawValue: UInt16($0.dogmaAttributeID)))
            }
        }, options: .keyOrdered)

        try main.create(DbuffLocationModifier.self, filledWith: buffs.flatMap { raw in
            (raw.locationModifiers ?? []).map {
                DbuffLocationModifier(buffID: WarfareBuffID(rawValue: UInt16(raw._key)),
                                      attributeID: AttributeID(rawValue: UInt16($0.dogmaAttributeID)))
            }
        }, options: .keyOrdered)

        try main.create(DbuffLocationGroupModifier.self, filledWith: buffs.flatMap { raw in
            (raw.locationGroupModifiers ?? []).map {
                DbuffLocationGroupModifier(buffID: WarfareBuffID(rawValue: UInt16(raw._key)),
                                           attributeID: AttributeID(rawValue: UInt16($0.dogmaAttributeID)),
                                           groupID: GroupID(rawValue: UInt16($0.groupID)))
            }
        }, options: .keyOrdered)

        try main.create(DbuffLocationRequiredSkillModifier.self, filledWith: buffs.flatMap { raw in
            (raw.locationRequiredSkillModifiers ?? []).map {
                DbuffLocationRequiredSkillModifier(buffID: WarfareBuffID(rawValue: UInt16(raw._key)),
                                                   attributeID: AttributeID(rawValue: UInt16($0.dogmaAttributeID)),
                                                   skillID: TypeID(rawValue: UInt32($0.skillID)))
            }
        }, options: .keyOrdered)
    }

    // MARK: - Categories and groups

    private func importGroups() throws {
        let rawCategories = try JSONL.array(CategoryInfo.self, at: url("categories"))
        let rawGroups = try JSONL.array(GroupInfo.self, at: url("groups"))

        // Category 350001 (Infantry) is the only one whose IDs do not fit in UInt16; it has no
        // published types.
        for raw in rawCategories {
            guard let id = UInt16(exactly: raw._key).map(CategoryID.init(rawValue:)) else { continue }
            categories[id] = raw
        }
        for raw in rawGroups {
            guard let id = UInt16(exactly: raw._key).map(GroupID.init(rawValue:)),
                  let categoryID = UInt16(exactly: raw.categoryID).map(CategoryID.init(rawValue:)),
                  categories[categoryID] != nil
            else { continue }
            groups[id] = raw

            let name = raw.name.en
            let category = categoryID
            if name == Scope.shipModifiersGroup {
                modeGroup = id
                exceptionGroups.insert(id)
            }
            else if category == Scope.celestialCategory, Scope.environmentGroups.contains(name) {
                exceptionGroups.insert(id)
            }
            else if category == Scope.celestialCategory, name == Scope.planetGroup {
                planetGroup = id
                exceptionGroups.insert(id)
            }
            if Scope.planetaryCategories.contains(category) {
                planetaryGroups.insert(id)
            }
        }

        try main.create(CategoryRow.self, filledWith: categories.map { id, raw in
            CategoryRow(id: id,
                        nameID: textBuilder.name(raw.name.localized),
                        iconID: raw.iconID.map { IconID(rawValue: UInt16($0)) },
                        published: raw.published)
        })
        try main.create(GroupRow.self, filledWith: groups.map { id, raw in
            GroupRow(id: id,
                     categoryID: CategoryID(rawValue: UInt16(raw.categoryID)),
                     nameID: textBuilder.name(raw.name.localized),
                     iconID: raw.iconID.map { IconID(rawValue: UInt16($0)) },
                     published: raw.published,
                     anchorable: raw.anchorable,
                     anchored: raw.anchored,
                     fittableNonSingleton: raw.fittableNonSingleton,
                     useBasePrice: raw.useBasePrice)
        })

        let icons = try JSONL.array(IconInfo.self, at: url("icons"))
        try main.create(IconRow.self, filledWith: icons.compactMap { raw in
            UInt16(exactly: raw._key).map { IconRow(id: IconID(rawValue: $0), iconFile: raw.iconFile) }
        })
    }

    // MARK: - Type dogma

    private func loadTypeDogma() throws {
        try JSONL.forEach(TypeDogmaInfo.self, at: url("typeDogma")) { raw in
            let id = TypeID(rawValue: UInt32(raw._key))
            var record = DogmaRecord()
            record.attributes = raw.dogmaAttributes.compactMap { attribute in
                UInt16(exactly: attribute.attributeID)
                    .map { (AttributeID(rawValue: $0), attribute.value) }
            }
            record.effects = (raw.dogmaEffects ?? []).compactMap { effect in
                UInt16(exactly: effect.effectID)
                    .map { (EffectID(rawValue: $0), effect.isDefault) }
            }
            dogma[id] = record
        }
    }

    // MARK: - Types

    /// The single pass over `types.jsonl` (141 MB).
    ///
    /// Descriptions go to the language files from here, in batches; only names stay in memory,
    /// since they must be sorted as a whole to compute `ordinal`.
    private func importTypes() throws {
        var rows: [TypeRow] = []
        rows.reserveCapacity(32768)

        try JSONL.forEach(TypeInfo.self, at: url("types")) { raw in
            guard let groupID = UInt16(exactly: raw.groupID).map(GroupID.init(rawValue:)),
                  groups[groupID] != nil,
                  isIncluded(raw, groupID: groupID)
            else { return }

            let id = TypeID(rawValue: UInt32(raw._key))
            let metaGroupID = raw.metaGroupID.flatMap { UInt16(exactly: $0).map(MetaGroupID.init(rawValue:)) }
            keptTypes[id] = KeptType(
                groupID: groupID,
                categoryID: CategoryID(rawValue: UInt16(self.groups[groupID]!.categoryID)),
                metaGroupID: metaGroupID,
                metaLevel: raw.metaLevel,
                volume: raw.volume,
                englishName: raw.name.en
            )
            rows.append(TypeRow(
                id: id,
                groupID: groupID,
                nameID: textBuilder.name(raw.name.localized),
                descriptionID: textBuilder.uniqueDescription(raw.description?.localized),
                marketGroupID: raw.marketGroupID.flatMap { UInt16(exactly: $0).map(MarketGroupID.init(rawValue:)) },
                metaGroupID: metaGroupID,
                metaLevel: raw.metaLevel,
                variationParentID: raw.variationParentTypeID.map { TypeID(rawValue: UInt32($0)) },
                raceID: raw.raceID.flatMap { UInt16(exactly: $0).map(RaceID.init(rawValue:)) },
                factionID: raw.factionID.map { FactionID(rawValue: UInt32($0)) },
                iconID: raw.iconID.flatMap { UInt16(exactly: $0).map(IconID.init(rawValue:)) },
                graphicID: raw.graphicID,
                soundID: raw.soundID,
                basePrice: raw.basePrice,
                capacity: raw.capacity,
                mass: raw.mass,
                radius: raw.radius,
                volume: raw.volume,
                portionSize: raw.portionSize,
                published: raw.published
            ))
        }

        sortedTypes = keptTypes.keys.sorted { $0.rawValue < $1.rawValue }
        try main.create(TypeRow.self, filledWith: rows)

        // Strings are built lazily: there are one and a half million of them.
        try main.create(TypeAttribute.self, options: .keyOrdered)
        try main.insert(sortedTypes.lazy.flatMap { id in
            (self.dogma[id]?.attributes ?? []).lazy.map {
                TypeAttribute(typeID: id, attributeID: $0.id, value: $0.value)
            }
        })
        try main.create(TypeEffect.self, options: .keyOrdered)
        try main.insert(sortedTypes.lazy.flatMap { id in
            (self.dogma[id]?.effects ?? []).lazy.map {
                TypeEffect(typeID: id, effectID: $0.id, isDefault: $0.isDefault)
            }
        })

        let metaGroups = try JSONL.array(MetaGroupInfo.self, at: url("metaGroups"))
        try main.create(MetaGroupRow.self, filledWith: metaGroups.map { raw in
            MetaGroupRow(
                id: MetaGroupID(rawValue: UInt16(raw._key)),
                nameID: textBuilder.name(raw.name.localized),
                descriptionID: textBuilder.description(raw.description?.localized),
                iconID: raw.iconID.map { IconID(rawValue: UInt16($0)) },
                iconSuffix: raw.iconSuffix,
                colorR: raw.color?.r,
                colorG: raw.color?.g,
                colorB: raw.color?.b
            )
        })

        let compressible = try JSONL.array(CompressibleTypeInfo.self, at: url("compressibleTypes"))
        try main.create(CompressibleTypeRow.self, filledWith: compressible.compactMap { raw in
            let id = TypeID(rawValue: UInt32(raw._key))
            guard keptTypes[id] != nil else { return nil }
            return CompressibleTypeRow(id: id, compressedTypeID: TypeID(rawValue: UInt32(raw.compressedTypeID)))
        })
    }

    /// Type selection rule: published ones plus four exceptions; beacons must also carry dogma.
    private func isIncluded(_ raw: TypeInfo, groupID: GroupID) -> Bool {
        if raw.published { return true }
        guard exceptionGroups.contains(groupID) else { return false }
        if groupID == modeGroup || groupID == planetGroup { return true }
        let record = dogma[TypeID(rawValue: UInt32(raw._key))]
        return !(record?.attributes.isEmpty ?? true) || !(record?.effects.isEmpty ?? true)
    }

    // MARK: - Market

    private func importMarket() throws {
        let raw = try JSONL.array(MarketGroupInfo.self, at: url("marketGroups"))
        var parents: [MarketGroupID: MarketGroupID] = [:]
        let rows = raw.compactMap { group -> MarketGroupRow? in
            guard let id = UInt16(exactly: group._key).map(MarketGroupID.init(rawValue:)) else { return nil }
            let parent = group.parentGroupID.flatMap { UInt16(exactly: $0).map(MarketGroupID.init(rawValue:)) }
            if let parent { parents[id] = parent }
            return MarketGroupRow(
                id: id,
                parentID: parent,
                nameID: textBuilder.name(group.name.localized),
                descriptionID: textBuilder.description(group.description?.localized),
                iconID: group.iconID.flatMap { UInt16(exactly: $0).map(IconID.init(rawValue:)) },
                hasTypes: group.hasTypes
            )
        }
        try main.create(MarketGroupRow.self, filledWith: rows)
        try importIconImages(marketIcons: Set(rows.compactMap(\.iconID)))

        // Closure: an "ancestor — descendant" pair for every link, including the pair with itself.
        var closure: [MarketGroupTree] = []
        for row in rows {
            var ancestor: MarketGroupID? = row.id
            var depth = 0
            while let current = ancestor {
                closure.append(MarketGroupTree(ancestorID: current, descendantID: row.id, depth: depth))
                ancestor = parents[current]
                depth += 1
                precondition(depth < 32, "цикл в дереве рыночных групп у \(row.id.rawValue)")
            }
        }
        try main.create(MarketGroupTree.self, filledWith: closure, options: .keyOrdered)
    }
}
