//
//  Importer+Industry.swift
//  SDE
//
//  Created by Artem Shimanski on 05.09.2026.
//

import Foundation
import LiteRow
import LiteRowBuild
import SDEModels

extension Importer {

    // MARK: - Blueprints

    /// Blueprint activities in SDE are six named fields with their own material, skill and product
    /// types and no common protocol, so the blocks repeat.
    func importIndustry() throws {
        var blueprints: [BlueprintRow] = []
        var activities: [BlueprintActivityInfo] = []
        // Dictionaries: the dump contains duplicates (blueprint 20344 lists skill 11442 twice in
        // copying). On merge a skill takes the higher level; materials and products are summed.
        var materials: [BlueprintMaterial.PrimaryKey: BlueprintMaterial] = [:]
        var products: [BlueprintProduct.PrimaryKey: BlueprintProduct] = [:]
        var skills: [BlueprintSkill.PrimaryKey: BlueprintSkill] = [:]

        try JSONL.forEach(BlueprintInfo.self, at: url("blueprints")) { raw in
            let id = TypeID(rawValue: UInt32(raw._key))
            guard self.keptTypes[id] != nil else { return }
            blueprints.append(BlueprintRow(id: id, maxProductionLimit: raw.maxProductionLimit))

            func material(_ activity: BlueprintActivity, _ typeID: Int, _ quantity: Int) {
                let row = BlueprintMaterial(blueprintID: id, activity: activity,
                                            materialTypeID: TypeID(rawValue: UInt32(typeID)),
                                            quantity: quantity)
                materials[row.primaryKey, default: row].quantity =
                    (materials[row.primaryKey].map { $0.quantity } ?? 0) + quantity
            }
            func skill(_ activity: BlueprintActivity, _ typeID: Int, _ level: Int) {
                let row = BlueprintSkill(blueprintID: id, activity: activity,
                                         skillID: TypeID(rawValue: UInt32(typeID)), level: level)
                skills[row.primaryKey, default: row].level = max(skills[row.primaryKey]?.level ?? 0, level)
            }
            func product(_ activity: BlueprintActivity, _ typeID: Int, _ quantity: Int, _ probability: Double?) {
                let row = BlueprintProduct(blueprintID: id, activity: activity,
                                           productTypeID: TypeID(rawValue: UInt32(typeID)),
                                           quantity: quantity, probability: probability)
                products[row.primaryKey, default: row].quantity =
                    (products[row.primaryKey].map { $0.quantity } ?? 0) + quantity
            }

            if let it = raw.activities.manufacturing {
                activities.append(.init(blueprintID: id, activity: .manufacturing, time: it.time))
                for m in it.materials ?? [] { material(.manufacturing, m.typeID, m.quantity) }
                for s in it.skills ?? [] { skill(.manufacturing, s.typeID, s.level) }
                for p in it.products ?? [] { product(.manufacturing, p.typeID, p.quantity, nil) }
            }
            if let it = raw.activities.invention {
                activities.append(.init(blueprintID: id, activity: .invention, time: it.time))
                for m in it.materials ?? [] { material(.invention, m.typeID, m.quantity) }
                for s in it.skills ?? [] { skill(.invention, s.typeID, s.level) }
                for p in it.products ?? [] { product(.invention, p.typeID, p.quantity, p.probability) }
            }
            if let it = raw.activities.reaction {
                activities.append(.init(blueprintID: id, activity: .reaction, time: it.time))
                for m in it.materials { material(.reaction, m.typeID, m.quantity) }
                for s in it.skills { skill(.reaction, s.typeID, s.level) }
                for p in it.products { product(.reaction, p.typeID, p.quantity, nil) }
            }
            if let it = raw.activities.copying {
                activities.append(.init(blueprintID: id, activity: .copying, time: it.time))
                for m in it.materials ?? [] { material(.copying, m.typeID, m.quantity) }
                for s in it.skills ?? [] { skill(.copying, s.typeID, s.level) }
            }
            if let it = raw.activities.research_material {
                activities.append(.init(blueprintID: id, activity: .researchMaterial, time: it.time))
                for m in it.materials ?? [] { material(.researchMaterial, m.typeID, m.quantity) }
                for s in it.skills ?? [] { skill(.researchMaterial, s.typeID, s.level) }
            }
            if let it = raw.activities.research_time {
                activities.append(.init(blueprintID: id, activity: .researchTime, time: it.time))
                for m in it.materials ?? [] { material(.researchTime, m.typeID, m.quantity) }
                for s in it.skills ?? [] { skill(.researchTime, s.typeID, s.level) }
            }
        }

        try main.create(BlueprintRow.self, filledWith: blueprints)
        try main.create(BlueprintActivityInfo.self, filledWith: activities, options: .keyOrdered)
        try main.create(BlueprintMaterial.self, filledWith: materials.values, options: .keyOrdered)
        try main.create(BlueprintProduct.self, filledWith: products.values, options: .keyOrdered)
        try main.create(BlueprintSkill.self, filledWith: skills.values, options: .keyOrdered)
    }

    // MARK: - Planetary

    func importPlanetary() throws {
        let schematics = try JSONL.array(PlanetSchematicInfo.self, at: url("planetSchematics"))
        try main.create(PlanetSchematicRow.self, filledWith: schematics.map { raw in
            PlanetSchematicRow(
                id: SchematicID(rawValue: UInt16(raw._key)),
                nameID: textBuilder.name(raw.name.localized),
                cycleTime: raw.cycleTime
            )
        })
        try main.create(PlanetSchematicType.self, filledWith: schematics.flatMap { raw in
            raw.types.map {
                PlanetSchematicType(
                    schematicID: SchematicID(rawValue: UInt16(raw._key)),
                    typeID: TypeID(rawValue: UInt32($0._key)),
                    isInput: $0.isInput,
                    quantity: $0.quantity
                )
            }
        }, options: .keyOrdered)
        try main.create(PlanetSchematicFacility.self, filledWith: schematics.flatMap { raw in
            raw.pins.map {
                PlanetSchematicFacility(
                    schematicID: SchematicID(rawValue: UInt16(raw._key)),
                    facilityTypeID: TypeID(rawValue: UInt32($0))
                )
            }
        }, options: .keyOrdered)
    }

    // MARK: - Stations and starbases

    func importStations() throws {
        var towerResources: [ControlTowerResource] = []
        try JSONL.forEach(ControlTowerResourceInfo.self, at: url("controlTowerResources")) { raw in
            let towerID = TypeID(rawValue: UInt32(raw._key))
            guard self.keptTypes[towerID] != nil else { return }
            for resource in raw.resources {
                towerResources.append(ControlTowerResource(
                    towerID: towerID,
                    resourceTypeID: TypeID(rawValue: UInt32(resource.resourceTypeID)),
                    quantity: resource.quantity,
                    purpose: resource.purpose,
                    factionID: resource.factionID.map { FactionID(rawValue: UInt32($0)) },
                    minSecurityLevel: resource.minSecurityLevel
                ))
            }
        }
        try main.create(ControlTowerResource.self, filledWith: towerResources, options: .keyOrdered)

        let services = try JSONL.array(StationServiceInfo.self, at: url("stationServices"))
        try main.create(StationServiceRow.self, filledWith: services.map { raw in
            StationServiceRow(
                id: StationServiceID(rawValue: UInt16(raw._key)),
                nameID: textBuilder.name(raw.serviceName.localized),
                descriptionID: textBuilder.description(raw.description?.localized)
            )
        })

        let operations = try JSONL.array(StationOperationInfo.self, at: url("stationOperations"))
        try main.create(StationOperationRow.self, filledWith: operations.map { raw in
            StationOperationRow(
                id: StationOperationID(rawValue: UInt16(raw._key)),
                nameID: textBuilder.name(raw.operationName.localized),
                descriptionID: textBuilder.description(raw.description?.localized),
                activityID: raw.activityID,
                border: raw.border,
                corridor: raw.corridor,
                fringe: raw.fringe,
                hub: raw.hub,
                ratio: raw.ratio,
                manufacturingFactor: raw.manufacturingFactor,
                researchFactor: raw.researchFactor
            )
        })
        try main.create(StationOperationService.self, filledWith: operations.flatMap { raw in
            raw.services.map {
                StationOperationService(
                    operationID: StationOperationID(rawValue: UInt16(raw._key)),
                    serviceID: StationServiceID(rawValue: UInt16($0))
                )
            }
        }, options: .keyOrdered)
        // The nested element's `_key` is the race, `_value` the station type.
        try main.create(StationOperationStationType.self, filledWith: operations.flatMap { raw in
            (raw.stationTypes ?? []).compactMap { entry -> StationOperationStationType? in
                guard let raceID = UInt16(exactly: entry._key).map(RaceID.init(rawValue:)) else { return nil }
                return StationOperationStationType(
                    operationID: StationOperationID(rawValue: UInt16(raw._key)),
                    raceID: raceID,
                    stationTypeID: TypeID(rawValue: UInt32(entry._value))
                )
            }
        }, options: .keyOrdered)

        let activities = try JSONL.array(CorporationActivityInfo.self, at: url("corporationActivities"))
        try main.create(CorporationActivityRow.self, filledWith: activities.map { raw in
            CorporationActivityRow(
                id: CorporationActivityID(rawValue: UInt16(raw._key)),
                nameID: textBuilder.name(raw.name.localized)
            )
        })
    }

    // MARK: - Map

    /// Names and hierarchy only; planets, moons and belts are not in the database (284 MB of
    /// JSONL).
    func importUniverse() throws {
        let regions = try JSONL.array(MapRegionInfo.self, at: url("mapRegions"))
        try main.create(RegionRow.self, filledWith: regions.map { raw in
            RegionRow(
                id: RegionID(rawValue: UInt32(raw._key)),
                nameID: textBuilder.name(raw.name.localized),
                descriptionID: textBuilder.uniqueDescription(raw.description?.localized),
                factionID: raw.factionID.map { FactionID(rawValue: UInt32($0)) },
                wormholeClassID: raw.wormholeClassID
            )
        })

        let constellations = try JSONL.array(MapConstellationInfo.self, at: url("mapConstellations"))
        try main.create(ConstellationRow.self, filledWith: constellations.map { raw in
            ConstellationRow(
                id: ConstellationID(rawValue: UInt32(raw._key)),
                regionID: RegionID(rawValue: UInt32(raw.regionID)),
                nameID: textBuilder.name(raw.name.localized),
                factionID: raw.factionID.map { FactionID(rawValue: UInt32($0)) },
                wormholeClassID: raw.wormholeClassID
            )
        })

        var systems: [SolarSystemRow] = []
        try JSONL.forEach(MapSolarSystemInfo.self, at: url("mapSolarSystems")) { raw in
            systems.append(SolarSystemRow(
                id: SolarSystemID(rawValue: UInt32(raw._key)),
                constellationID: ConstellationID(rawValue: UInt32(raw.constellationID)),
                regionID: RegionID(rawValue: UInt32(raw.regionID)),
                nameID: self.textBuilder.name(raw.name.localized),
                securityStatus: raw.securityStatus,
                securityClass: raw.securityClass,
                factionID: raw.factionID.map { FactionID(rawValue: UInt32($0)) },
                wormholeClassID: raw.wormholeClassID
            ))
        }
        try main.create(SolarSystemRow.self, filledWith: systems)

        let factions = try JSONL.array(FactionInfo.self, at: url("factions"))
        try main.create(FactionRow.self, filledWith: factions.map { raw in
            FactionRow(
                id: FactionID(rawValue: UInt32(raw._key)),
                nameID: textBuilder.name(raw.name.localized),
                descriptionID: textBuilder.uniqueDescription(raw.description.localized),
                shortDescriptionID: textBuilder.description(raw.shortDescription?.localized),
                iconID: UInt16(exactly: raw.iconID).map(IconID.init(rawValue:)),
                corporationID: raw.corporationID.map { CorporationID(rawValue: UInt32($0)) },
                militiaCorporationID: raw.militiaCorporationID.map { CorporationID(rawValue: UInt32($0)) },
                solarSystemID: SolarSystemID(rawValue: UInt32(raw.solarSystemID)),
                flatLogo: raw.flatLogo,
                flatLogoWithName: raw.flatLogoWithName,
                sizeFactor: raw.sizeFactor,
                uniqueName: raw.uniqueName
            )
        })
        try main.create(FactionMemberRace.self, filledWith: factions.flatMap { raw in
            raw.memberRaces.compactMap { race -> FactionMemberRace? in
                guard let raceID = UInt16(exactly: race).map(RaceID.init(rawValue:)) else { return nil }
                return FactionMemberRace(factionID: FactionID(rawValue: UInt32(raw._key)), raceID: raceID)
            }
        }, options: .keyOrdered)
    }
}
