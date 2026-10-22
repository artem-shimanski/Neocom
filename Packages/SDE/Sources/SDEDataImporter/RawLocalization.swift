//
//  RawLocalization.swift
//  SDE
//
//  Created by Artem Shimanski on 05.09.2026.
//

// Bridge between the raw schema and `Localized`.
//
// The localized fields of `SDESchema.swift` are forty-one nested types with the same eight
// properties but different language optionality. A `String` property does not satisfy the `var ru:
// String? { get }` requirement, so the protocol requires only `localized` and the body is printed
// per type. The list depends on the schema: a vanished type causes a compile error.

extension AncestryInfo.DescriptionInfo: Localizable {
    var localized: Localized { Localized(de: de, en: en, es: es, fr: fr, ja: ja, ko: ko, ru: ru, zh: zh) }
}
extension AncestryInfo.NameInfo: Localizable {
    var localized: Localized { Localized(de: de, en: en, es: es, fr: fr, ja: ja, ko: ko, ru: ru, zh: zh) }
}
extension BloodlineInfo.DescriptionInfo: Localizable {
    var localized: Localized { Localized(de: de, en: en, es: es, fr: fr, ja: ja, ko: ko, ru: ru, zh: zh) }
}
extension BloodlineInfo.NameInfo: Localizable {
    var localized: Localized { Localized(de: de, en: en, es: es, fr: fr, ja: ja, ko: ko, ru: ru, zh: zh) }
}
extension CategoryInfo.NameInfo: Localizable {
    var localized: Localized { Localized(de: de, en: en, es: es, fr: fr, ja: ja, ko: ko, ru: ru, zh: zh) }
}
extension CertificateInfo.DescriptionInfo: Localizable {
    var localized: Localized { Localized(de: de, en: en, es: es, fr: fr, ja: ja, ko: ko, ru: ru, zh: zh) }
}
extension CertificateInfo.NameInfo: Localizable {
    var localized: Localized { Localized(de: de, en: en, es: es, fr: fr, ja: ja, ko: ko, ru: ru, zh: zh) }
}
extension CharacterAttributeInfo.NameInfo: Localizable {
    var localized: Localized { Localized(de: de, en: en, es: es, fr: fr, ja: ja, ko: ko, ru: ru, zh: zh) }
}
extension CorporationActivityInfo.NameInfo: Localizable {
    var localized: Localized { Localized(de: de, en: en, es: es, fr: fr, ja: ja, ko: ko, ru: ru, zh: zh) }
}
extension DbuffCollectionInfo.DisplayNameInfo: Localizable {
    var localized: Localized { Localized(de: de, en: en, es: es, fr: fr, ja: ja, ko: ko, ru: ru, zh: zh) }
}
extension DogmaAttributeInfo.DisplayNameInfo: Localizable {
    var localized: Localized { Localized(de: de, en: en, es: es, fr: fr, ja: ja, ko: ko, ru: ru, zh: zh) }
}
extension DogmaAttributeInfo.TooltipDescriptionInfo: Localizable {
    var localized: Localized { Localized(de: de, en: en, es: es, fr: fr, ja: ja, ko: ko, ru: ru, zh: zh) }
}
extension DogmaAttributeInfo.TooltipTitleInfo: Localizable {
    var localized: Localized { Localized(de: de, en: en, es: es, fr: fr, ja: ja, ko: ko, ru: ru, zh: zh) }
}
extension DogmaEffectInfo.DescriptionInfo: Localizable {
    var localized: Localized { Localized(de: de, en: en, es: es, fr: fr, ja: ja, ko: ko, ru: ru, zh: zh) }
}
extension DogmaEffectInfo.DisplayNameInfo: Localizable {
    var localized: Localized { Localized(de: de, en: en, es: es, fr: fr, ja: ja, ko: ko, ru: ru, zh: zh) }
}
extension DogmaUnitInfo.DescriptionInfo: Localizable {
    var localized: Localized { Localized(de: de, en: en, es: es, fr: fr, ja: ja, ko: ko, ru: ru, zh: zh) }
}
extension DogmaUnitInfo.DisplayNameInfo: Localizable {
    var localized: Localized { Localized(de: de, en: en, es: es, fr: fr, ja: ja, ko: ko, ru: ru, zh: zh) }
}
extension FactionInfo.DescriptionInfo: Localizable {
    var localized: Localized { Localized(de: de, en: en, es: es, fr: fr, ja: ja, ko: ko, ru: ru, zh: zh) }
}
extension FactionInfo.NameInfo: Localizable {
    var localized: Localized { Localized(de: de, en: en, es: es, fr: fr, ja: ja, ko: ko, ru: ru, zh: zh) }
}
extension FactionInfo.ShortDescriptionInfo: Localizable {
    var localized: Localized { Localized(de: de, en: en, es: es, fr: fr, ja: ja, ko: ko, ru: ru, zh: zh) }
}
extension GroupInfo.NameInfo: Localizable {
    var localized: Localized { Localized(de: de, en: en, es: es, fr: fr, ja: ja, ko: ko, ru: ru, zh: zh) }
}
extension MapConstellationInfo.NameInfo: Localizable {
    var localized: Localized { Localized(de: de, en: en, es: es, fr: fr, ja: ja, ko: ko, ru: ru, zh: zh) }
}
extension MapRegionInfo.DescriptionInfo: Localizable {
    var localized: Localized { Localized(de: de, en: en, es: es, fr: fr, ja: ja, ko: ko, ru: ru, zh: zh) }
}
extension MapRegionInfo.NameInfo: Localizable {
    var localized: Localized { Localized(de: de, en: en, es: es, fr: fr, ja: ja, ko: ko, ru: ru, zh: zh) }
}
extension MapSolarSystemInfo.NameInfo: Localizable {
    var localized: Localized { Localized(de: de, en: en, es: es, fr: fr, ja: ja, ko: ko, ru: ru, zh: zh) }
}
extension MarketGroupInfo.DescriptionInfo: Localizable {
    var localized: Localized { Localized(de: de, en: en, es: es, fr: fr, ja: ja, ko: ko, ru: ru, zh: zh) }
}
extension MarketGroupInfo.NameInfo: Localizable {
    var localized: Localized { Localized(de: de, en: en, es: es, fr: fr, ja: ja, ko: ko, ru: ru, zh: zh) }
}
extension MetaGroupInfo.DescriptionInfo: Localizable {
    var localized: Localized { Localized(de: de, en: en, es: es, fr: fr, ja: ja, ko: ko, ru: ru, zh: zh) }
}
extension MetaGroupInfo.NameInfo: Localizable {
    var localized: Localized { Localized(de: de, en: en, es: es, fr: fr, ja: ja, ko: ko, ru: ru, zh: zh) }
}
extension PlanetSchematicInfo.NameInfo: Localizable {
    var localized: Localized { Localized(de: de, en: en, es: es, fr: fr, ja: ja, ko: ko, ru: ru, zh: zh) }
}
extension RaceInfo.DescriptionInfo: Localizable {
    var localized: Localized { Localized(de: de, en: en, es: es, fr: fr, ja: ja, ko: ko, ru: ru, zh: zh) }
}
extension RaceInfo.NameInfo: Localizable {
    var localized: Localized { Localized(de: de, en: en, es: es, fr: fr, ja: ja, ko: ko, ru: ru, zh: zh) }
}
extension StationOperationInfo.DescriptionInfo: Localizable {
    var localized: Localized { Localized(de: de, en: en, es: es, fr: fr, ja: ja, ko: ko, ru: ru, zh: zh) }
}
extension StationOperationInfo.OperationNameInfo: Localizable {
    var localized: Localized { Localized(de: de, en: en, es: es, fr: fr, ja: ja, ko: ko, ru: ru, zh: zh) }
}
extension StationServiceInfo.DescriptionInfo: Localizable {
    var localized: Localized { Localized(de: de, en: en, es: es, fr: fr, ja: ja, ko: ko, ru: ru, zh: zh) }
}
extension StationServiceInfo.ServiceNameInfo: Localizable {
    var localized: Localized { Localized(de: de, en: en, es: es, fr: fr, ja: ja, ko: ko, ru: ru, zh: zh) }
}
extension TypeBonusInfo.MiscBonusesInfo.BonusTextInfo: Localizable {
    var localized: Localized { Localized(de: de, en: en, es: es, fr: fr, ja: ja, ko: ko, ru: ru, zh: zh) }
}
extension TypeBonusInfo.RoleBonusesInfo.BonusTextInfo: Localizable {
    var localized: Localized { Localized(de: de, en: en, es: es, fr: fr, ja: ja, ko: ko, ru: ru, zh: zh) }
}
extension TypeBonusInfo.TypesInfo._valueInfo.BonusTextInfo: Localizable {
    var localized: Localized { Localized(de: de, en: en, es: es, fr: fr, ja: ja, ko: ko, ru: ru, zh: zh) }
}
extension TypeInfo.DescriptionInfo: Localizable {
    var localized: Localized { Localized(de: de, en: en, es: es, fr: fr, ja: ja, ko: ko, ru: ru, zh: zh) }
}
extension TypeInfo.NameInfo: Localizable {
    var localized: Localized { Localized(de: de, en: en, es: es, fr: fr, ja: ja, ko: ko, ru: ru, zh: zh) }
}
