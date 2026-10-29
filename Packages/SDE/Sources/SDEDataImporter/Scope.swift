//
//  Scope.swift
//  SDE
//
//  Created by Artem Shimanski on 05.09.2026.
//

import SDEModels

/// What goes into the database.
///
/// The rule is "only `published`" plus the exceptions the UI needs: unpublished fit content the
/// engine calculates (`fitCategories`), tactical modes, environment effects and planets. Other
/// unpublished content (Infantry, NPC, scenery, QA types) is not imported; this also keeps
/// `GroupID` and `CategoryID` within `UInt16`: groups beyond it belong only to Infantry.
enum Scope {
    /// T3D tactical modes (group 1306). They have no effect of their own, so they are recognized by
    /// group.
    static let shipModifiersGroup = "Ship Modifiers"

    /// Groups of the Celestial category whose types carry system effects.
    ///
    /// The first five match the DogmaKit importer's `environmentGroupNames` and must not diverge
    /// from it: otherwise the UI offers an environment the engine does not know.
    static let environmentGroups: Set<String> = [
        "Effect Beacon",
        "Abyssal Hazards",
        "Non-Interactable Object",
        "MassiveEnvironments",
        "Triglavian Support Pylons",
        "Destructible Effect Beacon",
        "Beacon",
        "Super Weapon Beacon",
        "Wormhole",
    ]

    /// Planet type group.
    static let planetGroup = "Planet"

    /// Planetary interaction categories.
    static let planetaryCategories: Set<CategoryID> = [41, 42, 43, 2143]

    /// Colony structures.
    static let planetaryIndustryCategory: CategoryID = 41

    static let shipCategory: CategoryID = 6
    static let moduleCategory: CategoryID = 7
    static let chargeCategory: CategoryID = 8
    static let skillCategory: CategoryID = 16
    static let droneCategory: CategoryID = 18
    static let implantCategory: CategoryID = 20
    static let subsystemCategory: CategoryID = 32
    static let structureCategory: CategoryID = 65
    static let structureModuleCategory: CategoryID = 66
    static let fighterCategory: CategoryID = 87
    static let celestialCategory: CategoryID = 2

    /// Categories whose unpublished types are imported when they carry a `typeDogma` record: the
    /// DogmaKit importer keeps them, and a fit from outside (ESI, DNA, legacy) can hold them.
    /// Browsers and pickers hide them by `types.published`.
    static let fitCategories: Set<CategoryID> = [
        shipCategory, moduleCategory, chargeCategory, droneCategory, implantCategory,
        subsystemCategory, structureCategory, structureModuleCategory, fighterCategory,
    ]
}
