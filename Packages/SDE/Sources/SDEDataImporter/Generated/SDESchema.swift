//
// SDESchema.swift
// DogmaKit
// SDE Version: 3632936, 2026-10-20T11:08:17Z
//

import Foundation

struct _sdeInfo: Identifiable, Codable {
    var _key: String = ""
    var id: String { _key }
    var buildNumber: Int = 0
    var releaseDate: String = ""
}

struct AncestryInfo: Identifiable, Codable {
    struct DescriptionInfo: Codable {
        var de: String = ""
        var en: String = ""
        var es: String = ""
        var fr: String = ""
        var ja: String = ""
        var ko: String = ""
        var ru: String = ""
        var zh: String = ""
    }

    struct NameInfo: Codable {
        var de: String = ""
        var en: String = ""
        var es: String = ""
        var fr: String = ""
        var ja: String = ""
        var ko: String = ""
        var ru: String = ""
        var zh: String = ""
    }

    var _key: Int = 0
    var id: Int { _key }
    var bloodlineID: Int = 0
    var charisma: Int = 0
    var description: DescriptionInfo
    var iconID: Int? = nil
    var intelligence: Int = 0
    var memory: Int = 0
    var name: NameInfo
    var perception: Int = 0
    var shortDescription: String? = nil
    var willpower: Int = 0
}

struct BloodlineInfo: Identifiable, Codable {
    struct DescriptionInfo: Codable {
        var de: String = ""
        var en: String = ""
        var es: String = ""
        var fr: String = ""
        var ja: String = ""
        var ko: String = ""
        var ru: String = ""
        var zh: String = ""
    }

    struct NameInfo: Codable {
        var de: String = ""
        var en: String = ""
        var es: String = ""
        var fr: String = ""
        var ja: String = ""
        var ko: String = ""
        var ru: String = ""
        var zh: String = ""
    }

    var _key: Int = 0
    var id: Int { _key }
    var charisma: Int = 0
    var corporationID: Int = 0
    var description: DescriptionInfo
    var iconID: Int? = nil
    var intelligence: Int = 0
    var memory: Int = 0
    var name: NameInfo
    var perception: Int = 0
    var raceID: Int = 0
    var willpower: Int = 0
}

struct BlueprintInfo: Identifiable, Codable {
    struct ActivitiesInfo: Codable {
        struct CopyingInfo: Codable {
            struct MaterialsInfo: Codable {
                var quantity: Int = 0
                var typeID: Int = 0
            }

            struct SkillsInfo: Codable {
                var level: Int = 0
                var typeID: Int = 0
            }

            var materials: [MaterialsInfo]? = nil
            var skills: [SkillsInfo]? = nil
            var time: Int = 0
        }

        struct InventionInfo: Codable {
            struct MaterialsInfo: Codable {
                var quantity: Int = 0
                var typeID: Int = 0
            }

            struct ProductsInfo: Codable {
                var probability: Double? = nil
                var quantity: Int = 0
                var typeID: Int = 0
            }

            struct SkillsInfo: Codable {
                var level: Int = 0
                var typeID: Int = 0
            }

            var materials: [MaterialsInfo]? = nil
            var products: [ProductsInfo]? = nil
            var skills: [SkillsInfo]? = nil
            var time: Int = 0
        }

        struct ManufacturingInfo: Codable {
            struct MaterialsInfo: Codable {
                var quantity: Int = 0
                var typeID: Int = 0
            }

            struct ProductsInfo: Codable {
                var quantity: Int = 0
                var typeID: Int = 0
            }

            struct SkillsInfo: Codable {
                var level: Int = 0
                var typeID: Int = 0
            }

            var materials: [MaterialsInfo]? = nil
            var products: [ProductsInfo]? = nil
            var skills: [SkillsInfo]? = nil
            var time: Int = 0
        }

        struct ReactionInfo: Codable {
            struct MaterialsInfo: Codable {
                var quantity: Int = 0
                var typeID: Int = 0
            }

            struct ProductsInfo: Codable {
                var quantity: Int = 0
                var typeID: Int = 0
            }

            struct SkillsInfo: Codable {
                var level: Int = 0
                var typeID: Int = 0
            }

            var materials: [MaterialsInfo] = []
            var products: [ProductsInfo] = []
            var skills: [SkillsInfo] = []
            var time: Int = 0
        }

        struct Research_materialInfo: Codable {
            struct MaterialsInfo: Codable {
                var quantity: Int = 0
                var typeID: Int = 0
            }

            struct SkillsInfo: Codable {
                var level: Int = 0
                var typeID: Int = 0
            }

            var materials: [MaterialsInfo]? = nil
            var skills: [SkillsInfo]? = nil
            var time: Int = 0
        }

        struct Research_timeInfo: Codable {
            struct MaterialsInfo: Codable {
                var quantity: Int = 0
                var typeID: Int = 0
            }

            struct SkillsInfo: Codable {
                var level: Int = 0
                var typeID: Int = 0
            }

            var materials: [MaterialsInfo]? = nil
            var skills: [SkillsInfo]? = nil
            var time: Int = 0
        }

        var copying: CopyingInfo? = nil
        var invention: InventionInfo? = nil
        var manufacturing: ManufacturingInfo? = nil
        var reaction: ReactionInfo? = nil
        var research_material: Research_materialInfo? = nil
        var research_time: Research_timeInfo? = nil
    }

    var _key: Int = 0
    var id: Int { _key }
    var activities: ActivitiesInfo
    var blueprintTypeID: Int = 0
    var maxProductionLimit: Int = 0
}

struct CategoryInfo: Identifiable, Codable {
    struct NameInfo: Codable {
        var de: String = ""
        var en: String = ""
        var es: String = ""
        var fr: String = ""
        var ja: String = ""
        var ko: String = ""
        var ru: String = ""
        var zh: String = ""
    }

    var _key: Int = 0
    var id: Int { _key }
    var iconID: Int? = nil
    var name: NameInfo
    var published: Bool = false
}

struct CertificateInfo: Identifiable, Codable {
    struct DescriptionInfo: Codable {
        var de: String = ""
        var en: String = ""
        var es: String = ""
        var fr: String = ""
        var ja: String = ""
        var ko: String = ""
        var ru: String = ""
        var zh: String = ""
    }

    struct NameInfo: Codable {
        var de: String = ""
        var en: String = ""
        var es: String = ""
        var fr: String = ""
        var ja: String = ""
        var ko: String = ""
        var ru: String = ""
        var zh: String = ""
    }

    struct SkillTypesInfo: Identifiable, Codable {
        var _key: Int = 0
        var id: Int { _key }
        var advanced: Int = 0
        var basic: Int = 0
        var elite: Int = 0
        var improved: Int = 0
        var standard: Int = 0
    }

    var _key: Int = 0
    var id: Int { _key }
    var description: DescriptionInfo
    var groupID: Int = 0
    var name: NameInfo
    var recommendedFor: [Int]? = nil
    var skillTypes: [SkillTypesInfo] = []
}

struct CharacterAttributeInfo: Identifiable, Codable {
    struct NameInfo: Codable {
        var de: String = ""
        var en: String = ""
        var es: String = ""
        var fr: String = ""
        var ja: String = ""
        var ko: String = ""
        var ru: String = ""
        var zh: String = ""
    }

    var _key: Int = 0
    var id: Int { _key }
    var description: String = ""
    var iconID: Int = 0
    var name: NameInfo
    var notes: String = ""
    var shortDescription: String = ""
}

struct CloneGradeInfo: Identifiable, Codable {
    struct SkillsInfo: Codable {
        var level: Int = 0
        var typeID: Int = 0
    }

    var _key: Int = 0
    var id: Int { _key }
    var name: String = ""
    var skills: [SkillsInfo] = []
}

struct CompressibleTypeInfo: Identifiable, Codable {
    var _key: Int = 0
    var id: Int { _key }
    var compressedTypeID: Int = 0
}

struct ControlTowerResourceInfo: Identifiable, Codable {
    struct ResourcesInfo: Codable {
        var factionID: Int? = nil
        var minSecurityLevel: Double? = nil
        var purpose: Int = 0
        var quantity: Int = 0
        var resourceTypeID: Int = 0
    }

    var _key: Int = 0
    var id: Int { _key }
    var resources: [ResourcesInfo] = []
}

struct CorporationActivityInfo: Identifiable, Codable {
    struct NameInfo: Codable {
        var de: String = ""
        var en: String = ""
        var es: String = ""
        var fr: String = ""
        var ja: String = ""
        var ko: String = ""
        var ru: String = ""
        var zh: String = ""
    }

    var _key: Int = 0
    var id: Int { _key }
    var name: NameInfo
}

struct DbuffCollectionInfo: Identifiable, Codable {
    struct DisplayNameInfo: Codable {
        var de: String? = nil
        var en: String = ""
        var es: String? = nil
        var fr: String? = nil
        var ja: String? = nil
        var ko: String? = nil
        var ru: String? = nil
        var zh: String? = nil
    }

    struct ItemModifiersInfo: Codable {
        var dogmaAttributeID: Int = 0
    }

    struct LocationGroupModifiersInfo: Codable {
        var dogmaAttributeID: Int = 0
        var groupID: Int = 0
    }

    struct LocationModifiersInfo: Codable {
        var dogmaAttributeID: Int = 0
    }

    struct LocationRequiredSkillModifiersInfo: Codable {
        var dogmaAttributeID: Int = 0
        var skillID: Int = 0
    }

    var _key: Int = 0
    var id: Int { _key }
    var aggregateMode: String = ""
    var developerDescription: String = ""
    var displayName: DisplayNameInfo? = nil
    var itemModifiers: [ItemModifiersInfo]? = nil
    var locationGroupModifiers: [LocationGroupModifiersInfo]? = nil
    var locationModifiers: [LocationModifiersInfo]? = nil
    var locationRequiredSkillModifiers: [LocationRequiredSkillModifiersInfo]? = nil
    var operationName: String = ""
    var showOutputValueInUI: String = ""
}

struct DogmaAttributeCategoryInfo: Identifiable, Codable {
    var _key: Int = 0
    var id: Int { _key }
    var description: String? = nil
    var name: String = ""
}

struct DogmaAttributeInfo: Identifiable, Codable {
    struct DisplayNameInfo: Codable {
        var de: String? = nil
        var en: String = ""
        var es: String? = nil
        var fr: String? = nil
        var ja: String? = nil
        var ko: String? = nil
        var ru: String? = nil
        var zh: String? = nil
    }

    struct TooltipDescriptionInfo: Codable {
        var de: String = ""
        var en: String = ""
        var es: String = ""
        var fr: String = ""
        var ja: String = ""
        var ko: String = ""
        var ru: String = ""
        var zh: String = ""
    }

    struct TooltipTitleInfo: Codable {
        var de: String = ""
        var en: String = ""
        var es: String = ""
        var fr: String = ""
        var ja: String = ""
        var ko: String = ""
        var ru: String = ""
        var zh: String = ""
    }

    var _key: Int = 0
    var id: Int { _key }
    var attributeCategoryID: Int? = nil
    var chargeRechargeTimeID: Int? = nil
    var dataType: Int = 0
    var defaultValue: Double = 0
    var description: String? = nil
    var displayName: DisplayNameInfo? = nil
    var displayWhenZero: Bool = false
    var highIsGood: Bool = false
    var iconID: Int? = nil
    var maxAttributeID: Int? = nil
    var minAttributeID: Int? = nil
    var name: String = ""
    var published: Bool = false
    var stackable: Bool = false
    var tooltipDescription: TooltipDescriptionInfo? = nil
    var tooltipTitle: TooltipTitleInfo? = nil
    var unitID: Int? = nil
}

struct DogmaEffectInfo: Identifiable, Codable {
    struct DescriptionInfo: Codable {
        var de: String = ""
        var en: String = ""
        var es: String = ""
        var fr: String = ""
        var ja: String = ""
        var ko: String = ""
        var ru: String = ""
        var zh: String = ""
    }

    struct DisplayNameInfo: Codable {
        var de: String = ""
        var en: String = ""
        var es: String = ""
        var fr: String = ""
        var ja: String = ""
        var ko: String = ""
        var ru: String = ""
        var zh: String = ""
    }

    struct ModifierInfo: Codable {
        var domain: String = ""
        var effectID: Int? = nil
        var `func`: String = ""
        var groupID: Int? = nil
        var modifiedAttributeID: Int? = nil
        var modifyingAttributeID: Int? = nil
        var operation: Int? = nil
        var skillTypeID: Int? = nil
    }

    var _key: Int = 0
    var id: Int { _key }
    var description: DescriptionInfo? = nil
    var disallowAutoRepeat: Bool = false
    var dischargeAttributeID: Int? = nil
    var displayName: DisplayNameInfo? = nil
    var distribution: Int? = nil
    var durationAttributeID: Int? = nil
    var effectCategoryID: Int = 0
    var electronicChance: Bool = false
    var falloffAttributeID: Int? = nil
    var fittingUsageChanceAttributeID: Int? = nil
    var guid: String? = nil
    var iconID: Int? = nil
    var isAssistance: Bool = false
    var isOffensive: Bool = false
    var isWarpSafe: Bool = false
    var modifierInfo: [ModifierInfo]? = nil
    var name: String = ""
    var npcActivationChanceAttributeID: Int? = nil
    var npcUsageChanceAttributeID: Int? = nil
    var propulsionChance: Bool = false
    var published: Bool = false
    var rangeAttributeID: Int? = nil
    var rangeChance: Bool = false
    var resistanceAttributeID: Int? = nil
    var trackingSpeedAttributeID: Int? = nil
}

struct DogmaUnitInfo: Identifiable, Codable {
    struct DescriptionInfo: Codable {
        var de: String = ""
        var en: String = ""
        var es: String = ""
        var fr: String = ""
        var ja: String = ""
        var ko: String = ""
        var ru: String = ""
        var zh: String = ""
    }

    struct DisplayNameInfo: Codable {
        var de: String = ""
        var en: String = ""
        var es: String = ""
        var fr: String = ""
        var ja: String = ""
        var ko: String = ""
        var ru: String = ""
        var zh: String = ""
    }

    var _key: Int = 0
    var id: Int { _key }
    var description: DescriptionInfo? = nil
    var displayName: DisplayNameInfo? = nil
    var name: String = ""
}

struct DynamicItemAttributeInfo: Identifiable, Codable {
    struct AttributeIDsInfo: Identifiable, Codable {
        var _key: Int = 0
        var id: Int { _key }
        var highIsGood: Bool? = nil
        var max: Double = 0
        var min: Double = 0
    }

    struct InputOutputMappingInfo: Codable {
        var applicableTypes: [Int] = []
        var resultingType: Int = 0
    }

    var _key: Int = 0
    var id: Int { _key }
    var attributeIDs: [AttributeIDsInfo] = []
    var inputOutputMapping: [InputOutputMappingInfo] = []
}

struct FactionInfo: Identifiable, Codable {
    struct DescriptionInfo: Codable {
        var de: String = ""
        var en: String = ""
        var es: String = ""
        var fr: String = ""
        var ja: String = ""
        var ko: String = ""
        var ru: String = ""
        var zh: String = ""
    }

    struct NameInfo: Codable {
        var de: String = ""
        var en: String = ""
        var es: String = ""
        var fr: String = ""
        var ja: String = ""
        var ko: String = ""
        var ru: String = ""
        var zh: String = ""
    }

    struct ShortDescriptionInfo: Codable {
        var de: String = ""
        var en: String = ""
        var es: String = ""
        var fr: String = ""
        var ja: String = ""
        var ko: String = ""
        var ru: String = ""
        var zh: String = ""
    }

    var _key: Int = 0
    var id: Int { _key }
    var corporationID: Int? = nil
    var description: DescriptionInfo
    var flatLogo: String? = nil
    var flatLogoWithName: String? = nil
    var iconID: Int = 0
    var memberRaces: [Int] = []
    var militiaCorporationID: Int? = nil
    var name: NameInfo
    var shortDescription: ShortDescriptionInfo? = nil
    var sizeFactor: Int = 0
    var solarSystemID: Int = 0
    var uniqueName: Bool = false
}

struct GroupInfo: Identifiable, Codable {
    struct NameInfo: Codable {
        var de: String? = nil
        var en: String = ""
        var es: String? = nil
        var fr: String? = nil
        var ja: String? = nil
        var ko: String? = nil
        var ru: String? = nil
        var zh: String? = nil
    }

    var _key: Int = 0
    var id: Int { _key }
    var anchorable: Bool = false
    var anchored: Bool = false
    var categoryID: Int = 0
    var fittableNonSingleton: Bool = false
    var iconID: Int? = nil
    var name: NameInfo
    var published: Bool = false
    var useBasePrice: Bool = false
}

struct IconInfo: Identifiable, Codable {
    var _key: Int = 0
    var id: Int { _key }
    var iconFile: String = ""
}

struct MapConstellationInfo: Identifiable, Codable {
    struct NameInfo: Codable {
        var de: String = ""
        var en: String = ""
        var es: String = ""
        var fr: String = ""
        var ja: String = ""
        var ko: String = ""
        var ru: String = ""
        var zh: String = ""
    }

    struct PositionInfo: Codable {
        var x: Int = 0
        var y: Double = 0
        var z: Double = 0
    }

    var _key: Int = 0
    var id: Int { _key }
    var factionID: Int? = nil
    var name: NameInfo
    var position: PositionInfo
    var regionID: Int = 0
    var solarSystemIDs: [Int] = []
    var wormholeClassID: Int? = nil
}

struct MapRegionInfo: Identifiable, Codable {
    struct DescriptionInfo: Codable {
        var de: String = ""
        var en: String = ""
        var es: String = ""
        var fr: String = ""
        var ja: String = ""
        var ko: String = ""
        var ru: String = ""
        var zh: String = ""
    }

    struct NameInfo: Codable {
        var de: String = ""
        var en: String = ""
        var es: String = ""
        var fr: String = ""
        var ja: String = ""
        var ko: String = ""
        var ru: String = ""
        var zh: String = ""
    }

    struct PositionInfo: Codable {
        var x: Int = 0
        var y: Int = 0
        var z: Double = 0
    }

    var _key: Int = 0
    var id: Int { _key }
    var constellationIDs: [Int] = []
    var description: DescriptionInfo? = nil
    var factionID: Int? = nil
    var name: NameInfo
    var nebulaID: Int = 0
    var position: PositionInfo
    var wormholeClassID: Int? = nil
}

struct MapSolarSystemInfo: Identifiable, Codable {
    struct NameInfo: Codable {
        var de: String = ""
        var en: String = ""
        var es: String = ""
        var fr: String = ""
        var ja: String = ""
        var ko: String = ""
        var ru: String = ""
        var zh: String = ""
    }

    struct PositionInfo: Codable {
        var x: Int = 0
        var y: Int = 0
        var z: Double = 0
    }

    struct Position2DInfo: Codable {
        var x: Int = 0
        var y: Int = 0
    }

    var _key: Int = 0
    var id: Int { _key }
    var border: Bool? = nil
    var constellationID: Int = 0
    var corridor: Bool? = nil
    var disallowedAnchorCategories: [Int]? = nil
    var disallowedAnchorGroups: [Int]? = nil
    var factionID: Int? = nil
    var fringe: Bool? = nil
    var hub: Bool? = nil
    var international: Bool? = nil
    var luminosity: Double? = nil
    var name: NameInfo
    var planetIDs: [Int]? = nil
    var position: PositionInfo
    var position2D: Position2DInfo? = nil
    var radius: Int = 0
    var regionID: Int = 0
    var regional: Bool? = nil
    var securityClass: String? = nil
    var securityStatus: Double = 0
    var starID: Int? = nil
    var stargateIDs: [Int]? = nil
    var visualEffect: String? = nil
    var wormholeClassID: Int? = nil
}

struct MarketGroupInfo: Identifiable, Codable {
    struct DescriptionInfo: Codable {
        var de: String = ""
        var en: String = ""
        var es: String = ""
        var fr: String = ""
        var ja: String = ""
        var ko: String = ""
        var ru: String = ""
        var zh: String = ""
    }

    struct NameInfo: Codable {
        var de: String? = nil
        var en: String = ""
        var es: String? = nil
        var fr: String? = nil
        var ja: String? = nil
        var ko: String? = nil
        var ru: String? = nil
        var zh: String? = nil
    }

    var _key: Int = 0
    var id: Int { _key }
    var description: DescriptionInfo? = nil
    var hasTypes: Bool = false
    var iconID: Int? = nil
    var name: NameInfo
    var parentGroupID: Int? = nil
}

struct MasteryInfo: Identifiable, Codable {
    struct _valueInfo: Identifiable, Codable {
        var _key: Int = 0
        var id: Int { _key }
        var _value: [Int] = []
    }

    var _key: Int = 0
    var id: Int { _key }
    var _value: [_valueInfo] = []
}

struct MetaGroupInfo: Identifiable, Codable {
    struct ColorInfo: Codable {
        var b: Double = 0
        var g: Double = 0
        var r: Double = 0
    }

    struct DescriptionInfo: Codable {
        var de: String = ""
        var en: String = ""
        var es: String = ""
        var fr: String = ""
        var ja: String = ""
        var ko: String = ""
        var ru: String = ""
        var zh: String = ""
    }

    struct NameInfo: Codable {
        var de: String = ""
        var en: String = ""
        var es: String = ""
        var fr: String = ""
        var ja: String = ""
        var ko: String = ""
        var ru: String = ""
        var zh: String = ""
    }

    var _key: Int = 0
    var id: Int { _key }
    var color: ColorInfo? = nil
    var description: DescriptionInfo? = nil
    var iconID: Int? = nil
    var iconSuffix: String? = nil
    var name: NameInfo
}

struct PlanetResourceInfo: Identifiable, Codable {
    struct ReagentInfo: Codable {
        var amount_per_cycle: Int = 0
        var cycle_period: Int = 0
        var secured_capacity: Int = 0
        var type_id: Int = 0
        var unsecured_capacity: Int = 0
    }

    var _key: Int = 0
    var id: Int { _key }
    var power: Int? = nil
    var reagent: ReagentInfo? = nil
    var workforce: Int? = nil
}

struct PlanetSchematicInfo: Identifiable, Codable {
    struct NameInfo: Codable {
        var de: String = ""
        var en: String = ""
        var es: String = ""
        var fr: String = ""
        var ja: String = ""
        var ko: String = ""
        var ru: String = ""
        var zh: String = ""
    }

    struct TypesInfo: Identifiable, Codable {
        var _key: Int = 0
        var id: Int { _key }
        var isInput: Bool = false
        var quantity: Int = 0
    }

    var _key: Int = 0
    var id: Int { _key }
    var cycleTime: Int = 0
    var name: NameInfo
    var pins: [Int] = []
    var types: [TypesInfo] = []
}

struct RaceInfo: Identifiable, Codable {
    struct DescriptionInfo: Codable {
        var de: String = ""
        var en: String = ""
        var es: String = ""
        var fr: String = ""
        var ja: String = ""
        var ko: String = ""
        var ru: String = ""
        var zh: String = ""
    }

    struct NameInfo: Codable {
        var de: String = ""
        var en: String = ""
        var es: String = ""
        var fr: String = ""
        var ja: String = ""
        var ko: String = ""
        var ru: String = ""
        var zh: String = ""
    }

    struct SkillsInfo: Identifiable, Codable {
        var _key: Int = 0
        var id: Int { _key }
        var _value: Int = 0
    }

    var _key: Int = 0
    var id: Int { _key }
    var description: DescriptionInfo? = nil
    var iconID: Int? = nil
    var name: NameInfo
    var shipTypeID: Int? = nil
    var skills: [SkillsInfo]? = nil
}

struct StationOperationInfo: Identifiable, Codable {
    struct DescriptionInfo: Codable {
        var de: String? = nil
        var en: String = ""
        var es: String? = nil
        var fr: String? = nil
        var ja: String? = nil
        var ko: String? = nil
        var ru: String? = nil
        var zh: String? = nil
    }

    struct OperationNameInfo: Codable {
        var de: String? = nil
        var en: String = ""
        var es: String? = nil
        var fr: String? = nil
        var ja: String? = nil
        var ko: String? = nil
        var ru: String? = nil
        var zh: String? = nil
    }

    struct StationTypesInfo: Identifiable, Codable {
        var _key: Int = 0
        var id: Int { _key }
        var _value: Int = 0
    }

    var _key: Int = 0
    var id: Int { _key }
    var activityID: Int = 0
    var border: Double = 0
    var corridor: Double = 0
    var description: DescriptionInfo? = nil
    var fringe: Double = 0
    var hub: Double = 0
    var manufacturingFactor: Double = 0
    var operationName: OperationNameInfo
    var ratio: Double = 0
    var researchFactor: Double = 0
    var services: [Int] = []
    var stationTypes: [StationTypesInfo]? = nil
}

struct StationServiceInfo: Identifiable, Codable {
    struct DescriptionInfo: Codable {
        var de: String = ""
        var en: String = ""
        var es: String = ""
        var fr: String = ""
        var ja: String = ""
        var ko: String = ""
        var ru: String = ""
        var zh: String = ""
    }

    struct ServiceNameInfo: Codable {
        var de: String = ""
        var en: String = ""
        var es: String = ""
        var fr: String = ""
        var ja: String = ""
        var ko: String = ""
        var ru: String = ""
        var zh: String = ""
    }

    var _key: Int = 0
    var id: Int { _key }
    var description: DescriptionInfo? = nil
    var serviceName: ServiceNameInfo
}

struct TranslationLanguageInfo: Identifiable, Codable {
    var _key: String = ""
    var id: String { _key }
    var name: String = ""
}

struct TypeBonusInfo: Identifiable, Codable {
    struct MiscBonusesInfo: Codable {
        struct BonusTextInfo: Codable {
            var de: String = ""
            var en: String = ""
            var es: String = ""
            var fr: String = ""
            var ja: String = ""
            var ko: String = ""
            var ru: String = ""
            var zh: String = ""
        }

        var bonus: Double? = nil
        var bonusText: BonusTextInfo
        var importance: Int = 0
        var isPositive: Bool? = nil
        var unitID: Int? = nil
    }

    struct RoleBonusesInfo: Codable {
        struct BonusTextInfo: Codable {
            var de: String? = nil
            var en: String = ""
            var es: String? = nil
            var fr: String? = nil
            var ja: String? = nil
            var ko: String? = nil
            var ru: String? = nil
            var zh: String? = nil
        }

        var bonus: Double? = nil
        var bonusText: BonusTextInfo
        var importance: Int = 0
        var unitID: Int? = nil
    }

    struct TypesInfo: Identifiable, Codable {
        struct _valueInfo: Codable {
            struct BonusTextInfo: Codable {
                var de: String? = nil
                var en: String = ""
                var es: String? = nil
                var fr: String? = nil
                var ja: String? = nil
                var ko: String? = nil
                var ru: String? = nil
                var zh: String? = nil
            }

            var bonus: Double? = nil
            var bonusText: BonusTextInfo
            var importance: Int = 0
            var unitID: Int? = nil
        }

        var _key: Int = 0
        var id: Int { _key }
        var _value: [_valueInfo] = []
    }

    var _key: Int = 0
    var id: Int { _key }
    var iconID: Int? = nil
    var miscBonuses: [MiscBonusesInfo]? = nil
    var roleBonuses: [RoleBonusesInfo]? = nil
    var types: [TypesInfo]? = nil
}

struct TypeDogmaInfo: Identifiable, Codable {
    struct DogmaAttributesInfo: Codable {
        var attributeID: Int = 0
        var value: Double = 0
    }

    struct DogmaEffectsInfo: Codable {
        var effectID: Int = 0
        var isDefault: Bool = false
    }

    var _key: Int = 0
    var id: Int { _key }
    var dogmaAttributes: [DogmaAttributesInfo] = []
    var dogmaEffects: [DogmaEffectsInfo]? = nil
}

struct TypeMaterialInfo: Identifiable, Codable {
    struct MaterialsInfo: Codable {
        var materialTypeID: Int = 0
        var quantity: Int = 0
    }

    struct RandomizedMaterialsInfo: Codable {
        var materialTypeID: Int = 0
        var quantityMax: Int = 0
        var quantityMin: Int = 0
    }

    var _key: Int = 0
    var id: Int { _key }
    var materials: [MaterialsInfo]? = nil
    var randomizedMaterials: [RandomizedMaterialsInfo]? = nil
}

struct TypeInfo: Identifiable, Codable {
    struct DescriptionInfo: Codable {
        var de: String? = nil
        var en: String = ""
        var es: String? = nil
        var fr: String? = nil
        var ja: String? = nil
        var ko: String? = nil
        var ru: String? = nil
        var zh: String? = nil
    }

    struct NameInfo: Codable {
        var de: String? = nil
        var en: String = ""
        var es: String? = nil
        var fr: String? = nil
        var ja: String? = nil
        var ko: String? = nil
        var ru: String? = nil
        var zh: String? = nil
    }

    var _key: Int = 0
    var id: Int { _key }
    var basePrice: Double? = nil
    var capacity: Double? = nil
    var description: DescriptionInfo? = nil
    var factionID: Int? = nil
    var graphicID: Int? = nil
    var groupID: Int = 0
    var iconID: Int? = nil
    var isDynamicType: Bool? = nil
    var isRepackable: Bool? = nil
    var marketGroupID: Int? = nil
    var mass: Double? = nil
    var metaGroupID: Int? = nil
    var metaLevel: Int? = nil
    var name: NameInfo
    var packagedVolume: Double? = nil
    var portionSize: Int = 0
    var published: Bool = false
    var raceID: Int? = nil
    var radius: Double? = nil
    var shipTreeGroupID: Int? = nil
    var soundID: Int? = nil
    var techLevel: Int? = nil
    var variationParentTypeID: Int? = nil
    var volume: Double? = nil
}
