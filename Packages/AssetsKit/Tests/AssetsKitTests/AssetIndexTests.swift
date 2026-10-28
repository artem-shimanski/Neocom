import AssetsKit
import Foundation
import Testing

@Suite struct AssetTreeTests {
    @Test func summaryOfPageOne() throws {
        let index = try Fixture.index(records: Fixture.records())
        #expect(index.summary.items == 1000)
        #expect(index.summary.locations == 35)
        #expect(index.summary.ships == 15)
        #expect(index.summary.blueprintCopies == 855)
    }

    @Test func parentsOnOtherPagesAreRootsOfUnknownKind() throws {
        let index = try Fixture.index(records: Fixture.records())
        let thorax = try #require(index.location(Fixture.thorax))
        #expect(thorax.kind == .unknown)
        #expect(thorax.itemCount == 4)
        // Rack flags are still read as racks, even without the hull.
        let sections = index.contents(of: Fixture.thorax)
        #expect(sections.map(\.kind) == [.highSlots, .cargo])
        #expect(sections[0].capacity == nil)
    }

    @Test func addingParentsMovesThemUnderTheStation() throws {
        let index = try Fixture.index()
        #expect(index.location(Fixture.thorax) == nil)
        #expect(index.summary.locations == 33)
        #expect(index.summary.items == 1002)
        let rens = try #require(index.location(Fixture.rens))
        #expect(rens.name == "Rens VI - Moon 8 - Brutor Tribe Treasury")
        #expect(rens.system?.regionName == "Heimatar")
        // 23 records of its own, the Catalyst's contents, the Thorax and its 4, the
        // container and its 9.
        let catalystChildren = try #require(index.item(1014)).nestedCount
        #expect(rens.itemCount == 23 + catalystChildren + 1 + 4 + 1 + 9)
        // Catalyst, seven Velators, the Thorax.
        #expect(rens.shipCount == 9)
        #expect(rens.containerCount == 1)
    }

    @Test func regionsGroupKnownSystemsAndPutTheRestLast() throws {
        let index = try Fixture.index()
        #expect(index.regions.first?.name == "Heimatar")
        #expect(index.regions.first?.locations.map(\.id) == [Fixture.rens])
        let unplaced = try #require(index.regions.last)
        #expect(unplaced.name == nil)
        #expect(unplaced.locations.contains { $0.id == Fixture.structure && $0.kind == .structureNoAccess })
    }

    @Test func pathOfANestedItem() throws {
        let index = try Fixture.index()
        let blaster = try #require(index.contents(of: Fixture.thorax).first?.rows.first)
        let path = try #require(index.path(to: blaster.id))
        #expect(path.location?.id == Fixture.rens)
        #expect(path.parents.map(\.id) == [Fixture.thorax])
    }

    @Test func duplicateRecordsAcrossPagesAreKeptOnce() throws {
        let records = try Fixture.records()
        let index = try Fixture.index(records: records + records.prefix(10))
        #expect(index.summary.items == 1000)
    }
}

@Suite struct AssetSectionTests {
    @Test func stationSections() throws {
        let index = try Fixture.index()
        let sections = index.contents(of: Fixture.rens)
        #expect(sections.map(\.title) == ["Ships", "Containers", "Modules", "Drones", "Charges",
                                          "Commodities", "Decryptors", "Special Edition Assets"])

        let ships = sections[0].rows
        #expect(ships.map(\.kind) == [.ship, .ship, .item])
        #expect(ships.map(\.typeName) == ["Catalyst", "Thorax", "Velator"])
        #expect(ships[2].quantity == 7)
        #expect(ships[2].isAssembled == false)

        let container = try #require(sections[1].rows.first)
        #expect(container.kind == .container)
        #expect(container.childCount == 9)

        let afterburners = try #require(sections[2].rows.first { $0.typeName == "Domination 10MN Afterburner" })
        #expect(afterburners.quantity == 2)
        #expect(sections[2].capacity == nil)
    }

    @Test func containerContentsAreSortedIntoCategories() throws {
        let index = try Fixture.index()
        let sections = index.contents(of: Fixture.container)
        #expect(sections.map(\.title) == ["Modules", "Charges", "Materials", "Commodities"])
        #expect(sections.map(\.rows.count) == [2, 2, 4, 1])
        #expect(sections[1].rows.map(\.name) == ["Combat Scanner Probe I", "Mjolnir Light Missile"])
        #expect(sections[1].rows[1].quantity == 3271)
    }

    @Test func identicalBlueprintCopiesAreOneRow() throws {
        let index = try Fixture.index()
        let sections = index.contents(of: Fixture.structure)
        #expect(sections.count == 1)
        let row = try #require(sections.first?.rows.first)
        #expect(sections[0].rows.count == 1)
        #expect(row.typeName == "Iron Charge S Blueprint")
        #expect(row.isBlueprintCopy)
        #expect(row.quantity == 854)
        #expect(row.itemIDs.count == 854)
        #expect(index.location(Fixture.structure)?.itemCount == 854)
    }

    @Test func copiesAndOriginalsDoNotStack() {
        let types: [Int64: AssetTypeInfo] = [
            1: AssetTypeInfo(typeID: 1, name: "Thing Blueprint", groupID: 10, groupName: "Blueprints",
                             categoryID: AssetCategory.blueprint, categoryName: "Blueprint"),
        ]
        let records = [
            AssetRecord(itemID: 100, typeID: 1, locationID: 60000004, locationFlag: "Hangar",
                        locationType: "station", quantity: 1, isSingleton: true, isBlueprintCopy: true),
            AssetRecord(itemID: 101, typeID: 1, locationID: 60000004, locationFlag: "Hangar",
                        locationType: "station", quantity: 1, isSingleton: true, isBlueprintCopy: false),
        ]
        let index = AssetIndex(records: records, types: types)
        #expect(index.contents(of: 60000004).first?.rows.count == 2)
        #expect(index.location(60000004)?.kind == .station)
    }

    @Test func nonHangarFlagsGetTheirOwnSection() throws {
        let types = try Fixture.types()
        let records = [
            AssetRecord(itemID: 1, typeID: 606, locationID: 60000004, locationFlag: "Hangar",
                        locationType: "station", quantity: 2, isSingleton: false),
            AssetRecord(itemID: 2, typeID: 606, locationID: 60000004, locationFlag: "CapsuleerDeliveries",
                        locationType: "station", quantity: 1, isSingleton: false),
            AssetRecord(itemID: 3, typeID: 606, locationID: 60000004, locationFlag: "AssetSafety",
                        locationType: "station", quantity: 1, isSingleton: false),
        ]
        let sections = AssetIndex(records: records, types: types).contents(of: 60000004)
        #expect(sections.map(\.title) == ["Ships", "Asset Safety", "Capsuleer Deliveries"])
    }

    @Test func shipSectionsCarryCapacities() throws {
        let index = try Fixture.index()
        let sections = index.contents(of: Fixture.thorax)
        #expect(sections.map(\.kind) == [.highSlots, .mediumSlots, .lowSlots, .rigSlots, .droneBay, .cargo])

        let high = sections[0]
        #expect(high.rows.count == 1)
        #expect(high.rows[0].name == "Heavy Neutron Blaster II")
        #expect(high.rows[0].quantity == 3)
        #expect(high.capacity == .slots(used: 3, total: 5))
        #expect(sections[1].capacity == .slots(used: 0, total: 4))
        #expect(sections[3].capacity == .slots(used: 0, total: 3))
        #expect(sections[4].capacity == .volume(used: 0, total: 50))

        let cargo = sections[5]
        #expect(cargo.rows.first?.quantity == 4370)
        guard case let .volume(used, total)? = cargo.capacity else {
            Issue.record("cargo has no capacity")
            return
        }
        #expect(total == 465)
        #expect(abs(used - 4370 * 0.0125) < 0.001)
    }

    @Test func customNamesReplaceTypeNames() throws {
        let index = try Fixture.index(names: [Fixture.thorax: "Test Pilot's Thorax", Fixture.container: "None"])
        let thorax = try #require(index.item(Fixture.thorax))
        #expect(thorax.name == "Test Pilot's Thorax")
        #expect(thorax.typeName == "Thorax")
        let container = try #require(index.item(Fixture.container))
        #expect(container.customName == nil)
        #expect(container.name == "Station Container")
    }
}

@Suite struct AssetSearchTests {
    @Test func stacksAreOneHitPerLocation() throws {
        let index = try Fixture.index()
        let results = index.search("velator")
        #expect(results.count == 4)
        let rens = try #require(results.first { $0.location.id == Fixture.rens })
        #expect(rens.hits.count == 1)
        #expect(rens.hits[0].row.quantity == 7)
        #expect(rens.hits[0].parents.isEmpty)
    }

    @Test func caseAndDiacriticsAreIgnored() throws {
        let index = try Fixture.index(names: [Fixture.container: "Sälvage"])
        let results = index.search("SALVAGE")
        let hit = try #require(results.first?.hits.first)
        #expect(hit.row.id == Fixture.container)
    }

    @Test func everyWordMustMatchSomewhere() throws {
        let index = try Fixture.index()
        // "neutron" is in the type name, "rens" in the location's.
        let results = index.search("neutron rens")
        #expect(results.map(\.location.id) == [Fixture.rens])
        let hit = try #require(results.first?.hits.first)
        #expect(hit.row.quantity == 3)
        #expect(hit.parents.map(\.id) == [Fixture.thorax])
        #expect(index.search("neutron jita").isEmpty)
    }

    @Test func groupNamesMatch() throws {
        let index = try Fixture.index()
        let hits = index.search("salvaged materials").flatMap(\.hits)
        #expect(hits.allSatisfy { $0.row.groupName == "Salvaged Materials" })
        #expect(hits.filter { $0.parents.map(\.id) == [Fixture.container] }.count == 4)
    }

    @Test func limitCapsTheHits() throws {
        let index = try Fixture.index()
        #expect(index.search("e", limit: 5).flatMap(\.hits).count == 5)
        #expect(index.search("   ").isEmpty)
    }
}

@Suite struct AssetFittingTests {
    @Test func fittingOfAnAssembledShip() throws {
        let index = try Fixture.index(names: [Fixture.thorax: "Brawler"])
        let fitting = try #require(index.fitting(ofShip: Fixture.thorax))
        #expect(fitting.shipTypeID == 627)
        #expect(fitting.name == "Brawler")
        #expect(Set(fitting.items.map(\.flag)) == ["HiSlot1", "HiSlot3", "HiSlot4"])
        #expect(fitting.items.allSatisfy { $0.typeID == fitting.items[0].typeID && $0.quantity == 1 })
    }

    @Test func dronesAndFightersAreIncludedCargoIsNot() {
        let types: [Int64: AssetTypeInfo] = [
            1: AssetTypeInfo(typeID: 1, name: "Hull", groupID: 26, groupName: "Cruiser",
                             categoryID: AssetCategory.ship, categoryName: "Ship"),
            2: AssetTypeInfo(typeID: 2, name: "Drone", groupID: 100, groupName: "Combat Drone",
                             categoryID: 18, categoryName: "Drone"),
        ]
        let records = [
            AssetRecord(itemID: 10, typeID: 1, locationID: 60000004, locationFlag: "Hangar",
                        locationType: "station", quantity: 1, isSingleton: true),
            AssetRecord(itemID: 11, typeID: 2, locationID: 10, locationFlag: "DroneBay",
                        locationType: "item", quantity: 3, isSingleton: false),
            AssetRecord(itemID: 12, typeID: 2, locationID: 10, locationFlag: "DroneBay",
                        locationType: "item", quantity: 2, isSingleton: false),
            AssetRecord(itemID: 13, typeID: 2, locationID: 10, locationFlag: "FighterTube0",
                        locationType: "item", quantity: 1, isSingleton: false),
            AssetRecord(itemID: 14, typeID: 2, locationID: 10, locationFlag: "Cargo",
                        locationType: "item", quantity: 9, isSingleton: false),
        ]
        let index = AssetIndex(records: records, types: types)
        let fitting = index.fitting(ofShip: 10)
        #expect(fitting?.items == [
            AssetFitting.Item(typeID: 2, flag: "DroneBay", quantity: 5),
            AssetFitting.Item(typeID: 2, flag: "FighterBay", quantity: 1),
        ])
        #expect(index.fitting(ofShip: 11) == nil)
    }
}

@Suite struct AssetPerformanceTests {
    /// Twenty pages' worth: the build and a search must stay well under a second.
    @Test func twentyThousandRecords() throws {
        let page = try Fixture.records()
        var records: [AssetRecord] = []
        for copy in 0..<20 {
            let offset = Int64(copy) * 10_000_000_000_000
            records += page.map { record in
                var record = record
                record.itemID += offset
                // Keep station roots shared; shift item parents with their children.
                if record.locationType == "item" { record.locationID += offset }
                return record
            }
        }
        let types = try Fixture.types()
        let clock = ContinuousClock()
        var index: AssetIndex?
        let build = clock.measure { index = AssetIndex(records: records, types: types) }
        let search = clock.measure { _ = index?.search("blueprint") }
        #expect(index?.summary.items == 20_000)
        #expect(build < .seconds(2))
        #expect(search < .seconds(1))
    }
}

@Suite struct AssetStrategicCruiserTests {
    /// A Strategic Cruiser's hull has no high, medium or low slots of its own; its subsystems
    /// bring them.
    @Test func subsystemsAddTheirSlots() {
        let types: [Int64: AssetTypeInfo] = [
            1: AssetTypeInfo(typeID: 1, name: "Legion", groupID: 963, groupName: "Strategic Cruiser",
                             categoryID: AssetCategory.ship, categoryName: "Ship",
                             slots: .init(rig: 3, subsystem: 4)),
            2: AssetTypeInfo(typeID: 2, name: "Offensive", groupID: 956, groupName: "Offensive Systems",
                             categoryID: 32, categoryName: "Subsystem",
                             slotModifiers: .init(high: 6, medium: 0, low: 0)),
            3: AssetTypeInfo(typeID: 3, name: "Defensive", groupID: 954, groupName: "Defensive Systems",
                             categoryID: 32, categoryName: "Subsystem",
                             slotModifiers: .init(high: 0, medium: 1, low: 3)),
            4: AssetTypeInfo(typeID: 4, name: "Laser", groupID: 53, groupName: "Energy Weapon",
                             categoryID: AssetCategory.module, categoryName: "Module"),
        ]
        var records = [
            AssetRecord(itemID: 10, typeID: 1, locationID: 60000004, locationFlag: "Hangar",
                        locationType: "station", quantity: 1, isSingleton: true),
            AssetRecord(itemID: 11, typeID: 2, locationID: 10, locationFlag: "SubSystemSlot0",
                        locationType: "item", quantity: 1, isSingleton: true),
            AssetRecord(itemID: 12, typeID: 3, locationID: 10, locationFlag: "SubSystemSlot1",
                        locationType: "item", quantity: 1, isSingleton: true),
        ]
        for slot in 0..<5 {
            records.append(AssetRecord(itemID: 20 + Int64(slot), typeID: 4, locationID: 10,
                                       locationFlag: "HiSlot\(slot)", locationType: "item",
                                       quantity: 1, isSingleton: true))
        }
        let sections = AssetIndex(records: records, types: types).contents(of: 10)
        let byKind = Dictionary(uniqueKeysWithValues: sections.map { ($0.kind, $0) })
        #expect(byKind[.highSlots]?.capacity == .slots(used: 5, total: 6))
        // Empty racks the subsystems open still show.
        #expect(byKind[.mediumSlots]?.capacity == .slots(used: 0, total: 1))
        #expect(byKind[.lowSlots]?.capacity == .slots(used: 0, total: 3))
        #expect(byKind[.subsystemSlots]?.capacity == .slots(used: 2, total: 4))
        #expect(byKind[.rigSlots]?.capacity == .slots(used: 0, total: 3))
    }

    /// Modifiers the caller did not supply: the rack still never reads `2/0`.
    @Test func totalIsNeverBelowWhatIsFitted() {
        let types: [Int64: AssetTypeInfo] = [
            1: AssetTypeInfo(typeID: 1, name: "Legion", groupID: 963, groupName: "Strategic Cruiser",
                             categoryID: AssetCategory.ship, categoryName: "Ship",
                             slots: .init(subsystem: 4)),
            4: AssetTypeInfo(typeID: 4, name: "Laser", groupID: 53, groupName: "Energy Weapon",
                             categoryID: AssetCategory.module, categoryName: "Module"),
        ]
        let records = [
            AssetRecord(itemID: 10, typeID: 1, locationID: 60000004, locationFlag: "Hangar",
                        locationType: "station", quantity: 1, isSingleton: true),
            AssetRecord(itemID: 20, typeID: 4, locationID: 10, locationFlag: "HiSlot0",
                        locationType: "item", quantity: 1, isSingleton: true),
            AssetRecord(itemID: 21, typeID: 4, locationID: 10, locationFlag: "HiSlot1",
                        locationType: "item", quantity: 1, isSingleton: true),
        ]
        let sections = AssetIndex(records: records, types: types).contents(of: 10)
        #expect(sections.first { $0.kind == .highSlots }?.capacity == .slots(used: 2, total: 2))
    }
}

@Suite struct AssetQuantityTests {
    /// Stacks keep the server's quantity all the way to the row.
    @Test func stackQuantitiesReachTheRow() throws {
        let index = try Fixture.index(records: Fixture.records())
        let row = try #require(index.item(1103))
        #expect(row.kind == .item)
        #expect(row.quantity == 1000)
        let rows = index.contents(of: 60004651).flatMap(\.rows)
        #expect(rows.contains { $0.itemIDs.contains(1103) && $0.quantity >= 1000 })
    }
}

@Suite struct AssetSafetyWrapTests {
    /// Type 60 is unpublished and may be missing from the static data: it is still a container,
    /// and has a name.
    @Test func wrapOpensAsAContainer() {
        let records = [
            AssetRecord(itemID: 10, typeID: AssetCategory.assetSafetyWrap, locationID: 60000004,
                        locationFlag: "AssetSafety", locationType: "station", quantity: 1, isSingleton: true),
        ]
        let index = AssetIndex(records: records, types: [:])
        let row = index.item(10)
        #expect(row?.kind == .container)
        #expect(row?.name == "Asset Safety Wrap")
    }
}

@Suite struct AssetCorporationTests {
    private static let station: Int64 = 60000004
    private static let office: Int64 = 100

    private static let types: [Int64: AssetTypeInfo] = [
        1: AssetTypeInfo(typeID: 1, name: "Rifter", groupID: 25, groupName: "Frigate",
                         categoryID: AssetCategory.ship, categoryName: "Ship"),
        2: AssetTypeInfo(typeID: 2, name: "Container", groupID: 12, groupName: "Cargo Container",
                         categoryID: 2, categoryName: "Celestial"),
        4: AssetTypeInfo(typeID: 4, name: "Laser", groupID: 53, groupName: "Energy Weapon",
                         categoryID: AssetCategory.module, categoryName: "Module"),
        27: AssetTypeInfo(typeID: 27, name: "Office", groupID: 15, groupName: "Station",
                          categoryID: 3, categoryName: "Station"),
    ]

    private static func record(_ id: Int64, _ type: Int64, in location: Int64, _ flag: String,
                               quantity: Int64 = 1, singleton: Bool = true) -> AssetRecord {
        AssetRecord(itemID: id, typeID: type, locationID: location, locationFlag: flag,
                    locationType: location == station ? "station" : "item", quantity: quantity,
                    isSingleton: singleton)
    }

    private static let records = [
        record(office, 27, in: station, "OfficeFolder", singleton: false),
        record(10, 1, in: office, "CorpSAG1"),
        record(11, 4, in: office, "CorpSAG1", quantity: 5, singleton: false),
        record(12, 2, in: office, "CorpSAG2"),
        record(13, 4, in: 12, "Unlocked", quantity: 3, singleton: false),
        record(14, 4, in: office, "CorpSAG3", quantity: 2, singleton: false),
        record(15, 4, in: office, "CorpDeliveries", singleton: false),
    ]

    private static let index = AssetIndex(records: records, types: types)

    @Test func officeIsNotAnItem() throws {
        let index = Self.index
        #expect(index.summary.items == 6)
        #expect(index.summary.locations == 1)
        let station = try #require(index.location(Self.station))
        #expect(station.itemCount == 6)
        #expect(station.shipCount == 1)
        #expect(station.containerCount == 1)
        let sections = index.contents(of: Self.station)
        #expect(sections.map(\.kind) == [.flag("CorpDeliveries")])
        #expect(sections.flatMap(\.rows).map(\.id) == [15])
    }

    @Test func divisionsAreCounted() {
        let divisions = Self.index.divisions(at: Self.station)
        #expect(divisions.map(\.number) == [1, 2, 3])
        #expect(divisions[0].itemCount == 2)
        #expect(divisions[0].shipCount == 1)
        #expect(divisions[1].itemCount == 2)
        #expect(divisions[1].containerCount == 1)
        #expect(divisions[2].itemCount == 1)
        #expect(Self.index.divisions(at: 60000005).isEmpty)
    }

    @Test func divisionContentsAreSectioned() {
        let first = Self.index.contents(ofDivision: 1, at: Self.station)
        #expect(first.map(\.kind) == [.ships, .category(AssetCategory.module)])
        #expect(first[1].rows.first?.quantity == 5)
        let second = Self.index.contents(ofDivision: 2, at: Self.station)
        #expect(second.map(\.kind) == [.containers])
        #expect(second[0].rows.first?.childCount == 1)
        #expect(Self.index.contents(ofDivision: 4, at: Self.station).isEmpty)
    }

    @Test func pathCarriesTheDivision() throws {
        let inContainer = try #require(Self.index.path(to: 13))
        #expect(inContainer.division == 2)
        #expect(inContainer.parents.map(\.id) == [12])
        #expect(inContainer.location?.id == Self.station)
        let loose = try #require(Self.index.path(to: 14))
        #expect(loose.division == 3)
        #expect(loose.parents.isEmpty)
        #expect(try #require(Self.index.path(to: 15)).division == nil)
    }

    @Test func searchCarriesTheDivision() {
        let hits = Self.index.search("laser").flatMap(\.hits)
        let byRow = Dictionary(uniqueKeysWithValues: hits.map { ($0.row.itemIDs.first ?? 0, $0) })
        #expect(byRow[13]?.division == 2)
        #expect(byRow[13]?.parents.map(\.id) == [12])
        #expect(byRow[14]?.division == 3)
        #expect(byRow[15]?.division == nil)
    }

    @Test func personalAssetsHaveNoDivisions() throws {
        let index = try Fixture.index()
        #expect(index.divisions(at: Fixture.rens).isEmpty)
        #expect(try #require(index.path(to: Fixture.thorax)).division == nil)
    }
}
