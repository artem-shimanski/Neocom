//
//  Importer+Fitting.swift
//  SDE
//
//  Created by Artem Shimanski on 05.09.2026.
//

import Foundation
import LiteRow
import LiteRowBuild
import SDEModels
import DogmaKit

/// Type selected after the pass over `types.jsonl`.
struct KeptType {
    var groupID: GroupID
    var categoryID: CategoryID
    var metaGroupID: MetaGroupID?
    var metaLevel: Int?
    var volume: Double?
    /// English name: the link from a tactical mode to its hull is expressed only through it
    /// (`hullsWithModes`).
    var englishName: String
}

extension Importer {

    /// Derived fitting tables.
    ///
    /// Attributes and effects are looked up by name; a missing name is a build error.
    func importFitting() throws {
        let cpu = try attribute("cpu")
        let power = try attribute("power")
        let capacitorNeed = try attribute("capacitorNeed")
        let upgradeCost = try attribute("upgradeCost")
        let droneBandwidthUsed = try attribute("droneBandwidthUsed")
        let volume = try attribute("volume")
        let chargeSize = try attribute("chargeSize")
        let rigSize = try attribute("rigSize")
        let maxGroupFitted = try attribute("maxGroupFitted")
        let maxGroupActive = try attribute("maxGroupActive")
        let techLevel = try attribute("techLevel")
        let boosterness = try attribute("boosterness")

        // The module slot comes from the engine: a type that `DogmaKit` does not fit into any slot
        // does not make it into `dogmaItems`. The engine's `sde.bin` must be built from the same
        // dump.
        let catalog = try TypeCatalog()
        let turretFitted = try effect("turretFitted")
        let launcherFitted = try effect("launcherFitted")

        let shipTypeAttributes = names.attributes(prefix: "canFitShipType")
            + [try attribute("fitsToShipType")]
        let shipGroupAttributes = names.attributes(prefix: "canFitShipGroup")
        let chargeGroupAttributes = names.attributes(prefix: "chargeGroup")
        let requiredSkills = names.requiredSkills()

        var items: [DogmaItem] = []
        var ships: [DogmaShip] = []
        var shipTypes: [DogmaItemShipType] = []
        var shipGroups: [DogmaItemShipGroup] = []
        var chargeGroups: [DogmaItemChargeGroup] = []
        var skills: [DogmaItemSkill] = []

        // Hulls with tactical modes and the "mode → hull" link. SDE has no such link; its only
        // trace is the name: "Confessor Defense Mode" → "Confessor".
        var hullsByName: [String: TypeID] = [:]
        for (id, kept) in keptTypes where kept.categoryID == Scope.shipCategory {
            hullsByName[kept.englishName] = id
        }
        var hullsWithModes: Set<TypeID> = []
        var modeHulls: [(mode: TypeID, hull: TypeID)] = []

        for id in sortedTypes {
            let kept = keptTypes[id]!
            let record = dogma[id] ?? DogmaRecord()

            var kind = DogmaItemKind.none
            switch catalog.slot(of: id) {
            case .hi: kind = .hi
            case .med: kind = .med
            case .low: kind = .low
            case .rig: kind = .rig
            case .subsystem: kind = .subsystem
            case .mode: kind = .mode
            case .service: kind = .service
            case nil: break
            }
            var hardpoint = DogmaHardpoint.none
            for effect in record.effects {
                switch effect.id {
                case turretFitted: hardpoint = .turret
                case launcherFitted: hardpoint = .launcher
                default: break
                }
            }
            kind = resolve(kind: kind, of: id, kept: kept, record: record, boosterness: boosterness)
            guard kind != .none else { continue }

            let restrictedTypes = targets(shipTypeAttributes, in: record).map { TypeID(rawValue: UInt32($0)) }
            let restrictedGroups = targets(shipGroupAttributes, in: record)
                .compactMap { UInt16(exactly: $0).map(GroupID.init(rawValue:)) }

            if kind == .mode {
                guard let hull = hull(ofMode: kept.englishName, in: hullsByName) else {
                    throw ImportError.missing("корпуса для режима «\(kept.englishName)»")
                }
                guard catalog.canFit(id, to: hull) else {
                    throw ImportError.missing("корпуса \(hull.rawValue) у режима «\(kept.englishName)» в DogmaKit")
                }
                hullsWithModes.insert(hull)
                modeHulls.append((id, hull))
            }

            for target in restrictedTypes where keptTypes[target] != nil {
                shipTypes.append(DogmaItemShipType(itemID: id, shipTypeID: target))
            }
            for target in restrictedGroups where groups[target] != nil {
                shipGroups.append(DogmaItemShipGroup(itemID: id, shipGroupID: target))
            }
            for group in targets(chargeGroupAttributes, in: record) {
                guard let groupID = UInt16(exactly: group).map(GroupID.init(rawValue:)),
                      groups[groupID] != nil
                else { continue }
                chargeGroups.append(DogmaItemChargeGroup(itemID: id, chargeGroupID: groupID))
            }
            for requirement in requiredSkills {
                guard let skill = record.value(requirement.skill).flatMap({ UInt32(exactly: $0.rounded()) }),
                      skill != 0
                else { continue }
                skills.append(DogmaItemSkill(
                    itemID: id,
                    skillID: TypeID(rawValue: skill),
                    level: Int(record.value(requirement.level) ?? 1)
                ))
            }

            items.append(DogmaItem(
                id: id,
                kind: kind,
                hardpoint: hardpoint,
                cpu: record.value(cpu),
                power: record.value(power),
                capacitorNeed: record.value(capacitorNeed),
                calibration: record.value(upgradeCost),
                droneBandwidthUsed: record.value(droneBandwidthUsed),
                volume: record.value(volume) ?? kept.volume,
                chargeSize: record.value(chargeSize).flatMap { UInt8(exactly: $0.rounded()) },
                rigSize: record.value(rigSize).flatMap { UInt8(exactly: $0.rounded()) },
                maxGroupFitted: record.value(maxGroupFitted).map { Int($0) },
                maxGroupActive: record.value(maxGroupActive).map { Int($0) },
                metaGroupID: kept.metaGroupID,
                metaLevel: kept.metaLevel,
                techLevel: record.value(techLevel).map { Int($0) },
                // Both a type and a group count as a restriction.
                hasShipRestrictions: !restrictedTypes.isEmpty || !restrictedGroups.isEmpty
            ))

            if kind == .ship || kind == .structure {
                ships.append(try ship(id: id, record: record))
            }
        }

        // Second pass: modes are known only after all types are visited.
        for index in ships.indices where hullsWithModes.contains(ships[index].id) {
            ships[index].hasTacticalModes = true
        }
        // The "mode → hull" link is stored alongside other fitting restrictions.
        for link in modeHulls {
            shipTypes.append(DogmaItemShipType(itemID: link.mode, shipTypeID: link.hull))
        }
        for index in items.indices where items[index].kind == .mode {
            items[index].hasShipRestrictions = true
        }

        try main.create(DogmaItem.self, filledWith: items)
        try main.create(DogmaShip.self, filledWith: ships)
        try main.create(DogmaItemShipType.self, filledWith: shipTypes, options: .keyOrdered)
        try main.create(DogmaItemShipGroup.self, filledWith: shipGroups, options: .keyOrdered)
        try main.create(DogmaItemChargeGroup.self, filledWith: chargeGroups, options: .keyOrdered)
        try main.create(DogmaItemSkill.self, filledWith: skills, options: .keyOrdered)
    }

    /// Hull of a tactical destroyer by its mode name.
    ///
    /// Mode suffixes do not reduce to three canonical ones (Anhinga has Primary / Secondary /
    /// Tertiary Mode), so the last two words are dropped.
    private func hull(ofMode name: String, in hulls: [String: TypeID]) -> TypeID? {
        let words = name.split(separator: " ")
        guard words.count > 2 else { return nil }
        return hulls[words.dropLast(2).joined(separator: " ")]
    }

    /// Item kind where there is no slot: ships, charges, drones, implants and the rest.
    private func resolve(
        kind: DogmaItemKind,
        of id: TypeID,
        kept: KeptType,
        record: DogmaRecord,
        boosterness: AttributeID
    ) -> DogmaItemKind {
        let groupName = groups[kept.groupID]?.name.en ?? ""

        // A structure rig has the same `rigSlot` effect but does not fit on a ship.
        if kind == .rig, kept.categoryID == Scope.structureModuleCategory { return .structureRig }
        if kind != .none { return kind }

        switch kept.categoryID {
        case Scope.shipCategory: return .ship
        case Scope.structureCategory: return .structure
        case Scope.chargeCategory: return .charge
        case Scope.droneCategory: return .drone
        case Scope.fighterCategory:
            return groupName.hasPrefix("Structure ") ? .structureFighter : .fighter
        // A subsystem without a slot is not a fit item.
        case Scope.subsystemCategory: return .none
        case Scope.implantCategory:
            // Booster and implant share a category; a booster is told apart by `boosterness`.
            return record.value(boosterness) != nil ? .booster : .implant
        case Scope.celestialCategory:
            if groupName == Scope.planetGroup { return .planet }
            return exceptionGroups.contains(kept.groupID) ? .environment : .none
        case Scope.planetaryIndustryCategory:
            return .planetaryFacility
        default:
            // Modules without a slot, including a mode with no hull in DogmaKit.
            return .none
        }
    }

    /// Hull slots and budgets. Base values: without skills, subsystems and bonuses.
    private func ship(id: TypeID, record: DogmaRecord) throws -> DogmaShip {
        func count(_ name: String) throws -> Int {
            Int(record.value(try attribute(name)) ?? 0)
        }
        func value(_ name: String) throws -> Double {
            record.value(try attribute(name)) ?? 0
        }
        return DogmaShip(
            id: id,
            hiSlots: try count("hiSlots"),
            medSlots: try count("medSlots"),
            lowSlots: try count("lowSlots"),
            rigSlots: try count("rigSlots"),
            subsystemSlots: try count("maxSubSystems"),
            serviceSlots: try count("serviceSlots"),
            turretHardpoints: try count("turretSlotsLeft"),
            launcherHardpoints: try count("launcherSlotsLeft"),
            cpuOutput: try value("cpuOutput"),
            powerOutput: try value("powerOutput"),
            calibration: try value("upgradeCapacity"),
            droneCapacity: try value("droneCapacity"),
            droneBandwidth: try value("droneBandwidth"),
            rigSize: record.value(try attribute("rigSize")).flatMap { UInt8(exactly: $0.rounded()) },
            shieldCapacity: try value("shieldCapacity"),
            armorHP: try value("armorHP"),
            structureHP: try value("hp"),
            capacitorCapacity: try value("capacitorCapacity"),
            maxVelocity: try value("maxVelocity")
        )
    }

    /// Values of the `canFitShipType1…12` attribute group, converted to integers.
    ///
    /// Zero is an unused slot of the set; it must be skipped, otherwise the module gets a "type 0
    /// only" restriction.
    private func targets(_ attributes: [AttributeID], in record: DogmaRecord) -> [Int] {
        attributes.compactMap { id in
            guard let value = record.value(id), value > 0 else { return nil }
            return Int(value.rounded())
        }
    }

    func attribute(_ name: String) throws -> AttributeID {
        guard let id = names[attribute: name] else { throw ImportError.missing("атрибута \(name)") }
        return id
    }

    func effect(_ name: String) throws -> EffectID {
        guard let id = names[effect: name] else { throw ImportError.missing("эффекта \(name)") }
        return id
    }

    // MARK: - Indexes

    /// Indexes are created after the data: with an existing index the b-tree is rebuilt on every
    /// row.
    func createIndexes() throws {
        try main.createIndexes(TypeRow.self)
        try main.createIndexes(GroupRow.self)
        try main.createIndexes(MarketGroupRow.self)
        try main.createIndexes(DogmaAttributeRow.self)
        try main.createIndexes(DogmaItem.self)
        try main.createIndexes(DogmaItemShipType.self)
        try main.createIndexes(DogmaItemShipGroup.self)
        try main.createIndexes(DogmaItemChargeGroup.self)
        try main.createIndexes(DogmaItemSkill.self)
        try main.createIndexes(DogmaSkill.self)
        try main.createIndexes(DogmaImplantAttribute.self)
        try main.createIndexes(CertificateRecommendation.self)
        try main.createIndexes(BlueprintProduct.self)
        try main.createIndexes(PlanetSchematicType.self)
        try main.createIndexes(ConstellationRow.self)
        try main.createIndexes(SolarSystemRow.self)
    }
}
