import DemoExport
import DemoFixtures
import Foundation
import Testing

let realID: Int64 = 2_112_345_678
let realCorp: Int64 = 98_765_432
let realAlliance: Int64 = 99_001_234
let structure: Int64 = 1_035_000_000_001
let ship: Int64 = 1_040_000_000_001
let container: Int64 = 1_040_000_000_002
let recordedAt = Date(timeIntervalSince1970: 1_792_497_600)

func entry(_ operationID: String, _ path: String, query: String = "", method: String = "GET", status: Int = 200,
           pages: Int? = nil, body: DemoJSON?, request: DemoJSON? = nil) -> DemoArchive.Entry {
    DemoArchive.Entry(operationID: operationID, method: method, path: path, query: query,
                      bodyDigest: DemoRequestKey.digest(of: request), status: status,
                      headers: DemoArchive.Headers(xPages: pages), body: body, requestBody: request)
}

func object(_ pairs: [String: DemoJSON]) -> DemoJSON { .object(pairs) }

func fitting(_ id: Int64, ship: Int64, _ name: String) -> DemoJSON {
    object(["fitting_id": .int(id), "ship_type_id": .int(ship), "name": .string(name),
            "description": .string("Created with Neocom on iOS"),
            "items": .array([object(["flag": .string("HiSlot0"), "quantity": .int(1), "type_id": .int(2929)])])])
}

/// What the real pilot has of the skills the configured queue trains: id, level, points.
let queuedSkills: [(Int64, Int64, Int64)] = [
    (3386, 2, 1415), (3388, 2, 4243), (3443, 4, 45255), (3551, 4, 45255), (12208, 4, 226_275),
]

func fakeRecording() -> DemoRecording {
    let me = "/characters/\(realID)"
    let entries: [DemoArchive.Entry] = [
        entry("GetCharactersDetail", me, body: object([
            "name": .string("Real Capsuleer"), "corporation_id": .int(realCorp), "alliance_id": .int(realAlliance),
            "birthday": .string("2015-03-01T10:00:00Z"), "description": .string("I am Real Capsuleer"),
            "security_status": .double(1.5), "title": .string("CEO"),
        ])),
        entry("GetCharactersCharacterIdAssets", me + "/assets", pages: 2, body: .array([
            object(["item_id": .int(ship), "location_id": .int(structure), "location_type": .string("item"),
                    "location_flag": .string("Hangar"), "type_id": .int(587), "quantity": .int(1), "is_singleton": .bool(true)]),
            object(["item_id": .int(container), "location_id": .int(60_003_760), "location_type": .string("station"),
                    "location_flag": .string("Hangar"), "type_id": .int(3297), "quantity": .int(1), "is_singleton": .bool(true)]),
        ])),
        entry("GetCharactersCharacterIdAssets", me + "/assets", query: "page=2", pages: 2, body: .array([
            object(["item_id": .int(1_040_000_000_003), "location_id": .int(container), "location_type": .string("item"),
                    "location_flag": .string("Unlocked"), "type_id": .int(34), "quantity": .int(100), "is_singleton": .bool(false)]),
        ])),
        entry("PostCharactersCharacterIdAssetsNames", me + "/assets/names", method: "POST",
              body: .array([
                  object(["item_id": .int(ship), "name": .string("Real Capsuleer's Rifter")]),
                  object(["item_id": .int(container), "name": .string("Ore stash")]),
                  object(["item_id": .int(1_040_000_000_003), "name": .string("Real Capsuleers Tritanium")]),
                  object(["item_id": .int(1_040_000_000_009), "name": .string("Real Capsuleer's Atron")]),
              ]),
              request: .array([.int(ship), .int(container), .int(1_040_000_000_003), .int(1_040_000_000_009)])),
        entry("GetCharactersCharacterIdClones", me + "/clones", body: object([
            "home_location": object(["location_id": .int(structure), "location_type": .string("structure")]),
            "jump_clones": .array([]),
        ])),
        entry("GetCharactersCharacterIdLocation", me + "/location", body: object([
            "solar_system_id": .int(30_000_142), "structure_id": .int(structure),
        ])),
        entry("GetCharactersCharacterIdContracts", me + "/contracts", pages: 1, body: .array([
            object(["contract_id": .int(1), "issuer_id": .int(realID), "issuer_corporation_id": .int(realCorp),
                    "assignee_id": .int(95_000_001), "acceptor_id": .int(0), "for_corporation": .bool(false),
                    "date_issued": .string("2026-10-19T08:00:00Z"), "title": .string("Courier")]),
        ])),
        entry("GetCharactersCharacterIdMail", me + "/mail", body: .array([
            object(["mail_id": .int(1), "from": .int(95_000_003), "subject": .string("Private")]),
        ])),
        entry("PostUniverseNames", "/universe/names", method: "POST", body: .array([
            object(["id": .int(realID), "name": .string("Real Capsuleer"), "category": .string("character")]),
            object(["id": .int(realCorp), "name": .string("Real Corp"), "category": .string("corporation")]),
            object(["id": .int(95_000_001), "name": .string("Other Guy"), "category": .string("character")]),
            object(["id": .int(30_000_142), "name": .string("Jita"), "category": .string("solar_system")]),
            object(["id": .int(3_008_666), "name": .string("Unreferenced Agent"), "category": .string("character")]),
            object(["id": .int(98_000_777), "name": .string("Unrelated Corp"), "category": .string("corporation")]),
        ]), request: .array([.int(realID), .int(realCorp), .int(95_000_001), .int(30_000_142), .int(3_008_666),
                             .int(98_000_777)])),
        entry("GetCharactersCharacterIdKillmailsRecent", me + "/killmails/recent", pages: 1, body: .array([
            object(["killmail_id": .int(123_456), "killmail_hash": .string("0123456789abcdef0123456789abcdef01234567")]),
        ])),
        entry("GetKillmailsKillmailIdKillmailHash", "/killmails/123456/0123456789abcdef0123456789abcdef01234567",
              body: object([
                  "killmail_id": .int(123_456), "killmail_time": .string("2026-10-18T20:00:00Z"),
                  "solar_system_id": .int(30_000_142),
                  "victim": object(["character_id": .int(realID), "corporation_id": .int(realCorp),
                                    "alliance_id": .int(realAlliance), "ship_type_id": .int(587)]),
                  "attackers": .array([object(["character_id": .int(95_000_002), "final_blow": .bool(true)])]),
              ])),
        entry("GetMarketsPrices", "/markets/prices", body: .array([object(["type_id": .int(34)])])),
        entry("GetCharactersCharacterIdPlanets", me + "/planets", status: 404, body: object(["error": .string("x")])),
        entry("GetCharactersCharacterIdFittings", me + "/fittings", body: .array([
            fitting(1, ship: 12023, "test"),
            fitting(2, ship: 12023, "Deimos - Range"),
            fitting(3, ship: 23913, "Тест"),
            fitting(4, ship: 17738, "Machariel"),
            fitting(5, ship: 17715, "Gila - New Setup 1 copy 1"),
            fitting(6, ship: 17738, "Machariel 2"),
            fitting(7, ship: 16227, "TEST Ferox"),
            fitting(8, ship: 35832, "*Simulated Astrahus 2"),
        ])),
        entry("GetCharactersCharacterIdAttributes", me + "/attributes", body: object([
            "charisma": .int(20), "intelligence": .int(20), "memory": .int(20), "perception": .int(20),
            "willpower": .int(20), "bonus_remaps": .int(1),
        ])),
        entry("GetCharactersCharacterIdSkills", me + "/skills", body: object([
            "total_sp": .int(5_000_000), "skills": .array(queuedSkills.map { id, level, points in
                object(["skill_id": .int(id), "trained_skill_level": .int(level), "active_skill_level": .int(level),
                        "skillpoints_in_skill": .int(points)])
            }),
        ])),
        entry("GetCharactersCharacterIdSkillqueue", me + "/skillqueue", body: .array([
            object(["skill_id": .int(3386), "finished_level": .int(3), "queue_position": .int(0)]),
        ])),
        entry("GetCharactersCharacterIdOrders", me + "/orders", body: .array([])),
        entry("GetCharactersCharacterIdOrdersHistory", me + "/orders/history", pages: 1, body: .array([
            object(["order_id": .int(7_445_440_502), "type_id": .int(3446), "is_corporation": .bool(false),
                    "issued": .string("2026-10-15T08:28:49Z"), "location_id": .int(60_004_588), "region_id": .int(10_000_030),
                    "price": .double(35000), "range": .string("station"), "duration": .int(0),
                    "volume_remain": .int(0), "volume_total": .int(1), "state": .string("expired")]),
        ])),
        entry("GetCharactersCharacterIdIndustryJobs", me + "/industry/jobs", query: "include_completed=true", body: .array([])),
        entry("GetUniverseStructuresStructureId", "/universe/structures/\(structure)",
              body: object(["name": .string("Real Corp Keepstar")])),
    ]
    return DemoRecording(recordedAt: recordedAt, compatibilityDate: "2026-07-21", pilotID: realID,
                         ownerHash: "OwnerHashXYZ=", entries: entries)
}

func loadConfig() throws -> DemoConfig {
    let url = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("DemoConfig.json")
    return try DemoConfig.decode(from: Data(contentsOf: url))
}

@Suite struct ExporterTests {
    @Test func anonymisesTheRecording() throws {
        let config = try loadConfig()
        let recording = fakeRecording()
        let exporter = DemoExporter(config: config)
        let archive = try exporter.export(recording)
        let demo = "/characters/\(DemoIDs.characterID)"
        func body(_ operationID: String, _ path: String, query: String = "") -> DemoJSON? {
            archive.entries.first { $0.operationID == operationID && $0.path == path && $0.query == query }?.body
        }

        #expect(archive.compatibilityDate == recording.compatibilityDate)
        #expect(archive.recordedAt == recordedAt)
        #expect(archive.pilot == DemoArchive.Pilot(id: DemoIDs.characterID, name: "Demo Pilot", corporationID: 1_000_044))
        #expect(archive.plan == config.plan)

        let profile = try #require(body("GetCharactersDetail", demo))
        #expect(profile["name"] == .string("Demo Pilot"))
        #expect(profile["corporation_id"] == .int(1_000_044))
        #expect(profile["alliance_id"] == nil)
        #expect(profile["description"] == .string(""))
        #expect(profile["title"] == nil)
        #expect(profile["corporation_title"] == nil)

        let assets = try #require(body("GetCharactersCharacterIdAssets", demo + "/assets")?.array)
        #expect(assets[0]["location_id"] == .int(60_004_420))
        #expect(assets[0]["location_type"] == .string("station"))
        #expect(assets[0]["item_id"] == .int(ship))
        #expect(assets[1]["location_id"] == .int(60_003_760))
        let inner = try #require(body("GetCharactersCharacterIdAssets", demo + "/assets", query: "page=2")?.array)
        #expect(inner[0]["location_id"] == .int(container))
        #expect(inner[0]["location_type"] == .string("item"))
        #expect(archive.assetNames == [String(ship): "Demo Pilot's Rifter", "1040000000003": "Demo Pilot's Tritanium"])

        let clones = try #require(body("GetCharactersCharacterIdClones", demo + "/clones"))
        #expect(clones["home_location"] == .object(["location_id": .int(60_004_420), "location_type": .string("station")]))
        let location = try #require(body("GetCharactersCharacterIdLocation", demo + "/location"))
        #expect(location == .object(["solar_system_id": .int(30_001_407), "station_id": .int(60_004_420)]))

        let contracts = try #require(body("GetCharactersCharacterIdContracts", demo + "/contracts")?.array)
        #expect(contracts.count == config.contracts.count)
        #expect(contracts.allSatisfy { $0["contract_id"]?.int.map(DemoIDs.contains) == true })

        let killmail = try #require(body("GetCharactersCharacterIdKillmailsRecent", demo + "/killmails/recent")?.array?.first)
        let killmailID = try #require(killmail["killmail_id"]?.int)
        let hash = try #require(killmail["killmail_hash"]?.string)
        #expect(DemoIDs.contains(killmailID))
        #expect(hash.count == 40 && hash != "0123456789abcdef0123456789abcdef01234567")
        let detail = try #require(body("GetKillmailsKillmailIdKillmailHash", "/killmails/\(killmailID)/\(hash)"))
        #expect(detail["killmail_id"] == .int(killmailID))
        #expect(detail["victim"] == .object(["character_id": .int(DemoIDs.characterID),
                                             "corporation_id": .int(1_000_044), "ship_type_id": .int(587)]))
        let attacker = try #require(detail["attackers"]?.array?.first?["character_id"]?.int)
        #expect(DemoIDs.contains(attacker))
        #expect(archive.names[String(attacker)]?.category == "character")
        #expect(config.syntheticCharacterNames.contains(archive.names[String(attacker)]?.name ?? ""))

        #expect(!archive.entries.contains { $0.operationID == "GetMarketsPrices" || $0.status != 200 && $0.status != 201 })
        #expect(!archive.entries.contains { $0.operationID.hasPrefix("GetUniverseStructures") || $0.requestBody != nil })
        let mails = archive.entries.filter { $0.operationID == "GetCharactersCharacterIdMailMailId" }
        #expect(mails.count == config.mail.messages.count)
        let inbox = try #require(body("GetCharactersCharacterIdMail", demo + "/mail")?.array)
        #expect(inbox.count == config.mail.messages.count)
        #expect(inbox.first?["timestamp"] == .string("2026-10-20T09:30:00Z"))
        #expect(body("GetCharactersCharacterIdMail", demo + "/mail", query: "labels=16")?.array?.count == 1)
        let labels = try #require(body("GetCharactersCharacterIdMailLabels", demo + "/mail/labels"))
        #expect(labels["total_unread_count"] == .int(3))
        #expect(body("GetCharactersCharacterIdContacts", demo + "/contacts")?.array?.count == config.contacts.count)

        #expect(archive.names[String(DemoIDs.characterID)]?.name == "Demo Pilot")
        #expect(archive.names["30000142"]?.name == "Jita")
        #expect(archive.names["95000001"] == nil)
        #expect(archive.names["3008666"] == nil)
        #expect(archive.names["98000777"] == nil)
        #expect(archive.names["8000000000004001"]?.name == "Northline Logistics")
        #expect(archive.names[String(realCorp)] == nil)
        #expect(archive.names["8000000000001001"]?.name == "Teva Raskold")

        let data = try exporter.encode(archive, recording: recording)
        let text = String(decoding: data, as: UTF8.self)
        #expect(!text.contains("Real Capsuleer") && !text.contains("Other Guy") && !text.contains("Private"))
        #expect(try exporter.encode(exporter.export(recording), recording: recording) == data)
        #expect(text.contains("\n  \"compatibilityDate\""))
    }

    @Test func leakCheckFailsOnARealId() throws {
        let exporter = DemoExporter(config: try loadConfig())
        let recording = fakeRecording()
        var archive = try exporter.export(recording)
        _ = try exporter.encode(archive, recording: recording)

        var planted = archive
        planted.entries[0].body = .array([.int(realID)])
        #expect(throws: DemoExportError.self) { try exporter.encode(planted, recording: recording) }

        archive.assetNames["1"] = "eyJhbGciOiJSUzI1NiJ9.payload"
        #expect(throws: DemoExportError.self) { try exporter.encode(archive, recording: recording) }

        let identity = try DemoRealIdentity(recording: recording)
        let findings = DemoExporter.leaks(in: Data("x \(realCorp)1 OwnerHashXYZ= Real Capsuleer".utf8), identity: identity)
        #expect(findings.count == 2)
    }

    @Test func trimsToTheBudget() throws {
        var config = try loadConfig()
        let recording = fakeRecording()
        let size = try DemoExporter(config: config).export(recording).encoded().count
        config.sizeBudget = size - 1
        let archive = try DemoExporter(config: config).export(recording)
        #expect(try archive.encoded().count <= size - 1)
        let pages = archive.entries.filter { $0.operationID == "GetCharactersCharacterIdAssets" }
        #expect(pages.count == 1)
        #expect(pages.first?.headers.xPages == 1)

        config.sizeBudget = 1000
        #expect(throws: DemoExportError.self) { try DemoExporter(config: config).export(recording) }
    }

    @Test func overlaysReplaceTheBusinessRoutes() throws {
        let config = try loadConfig()
        let archive = try DemoExporter(config: config).export(fakeRecording())
        let demo = "/characters/\(DemoIDs.characterID)"
        func body(_ operationID: String, _ path: String, query: String = "") -> [DemoJSON]? {
            archive.entries.first { $0.operationID == operationID && $0.path == path && $0.query == query }?.body?.array
        }
        func keys(_ json: DemoJSON?) -> Set<String> { Set(json?.object?.keys ?? [:].keys) }
        func date(_ json: DemoJSON?) -> Date? {
            json?.string.flatMap { try? Date($0, strategy: .iso8601) }
        }
        let orderKeys: Set = ["order_id", "type_id", "is_corporation", "location_id", "region_id", "price",
                              "volume_total", "volume_remain", "range", "duration", "issued"]

        let orders = try #require(body("GetCharactersCharacterIdOrders", demo + "/orders"))
        #expect(orders.count == config.orders.open.count)
        for order in orders {
            #expect(keys(order).isSuperset(of: orderKeys.union(["is_buy_order"])) && order["state"] == nil)
            #expect(try #require(date(order["issued"])) < recordedAt)
            if order["is_buy_order"] == .bool(true) { #expect(order["escrow"] != nil && order["min_volume"] != nil) }
        }
        let history = try #require(body("GetCharactersCharacterIdOrdersHistory", demo + "/orders/history"))
        #expect(history.count == 1 + config.orders.history.count)
        #expect(history.first?["order_id"] == .int(7_445_440_502))
        #expect(history.allSatisfy { keys($0).isSuperset(of: orderKeys.union(["state"])) })

        let jobs = try #require(body("GetCharactersCharacterIdIndustryJobs", demo + "/industry/jobs",
                                     query: "include_completed=true"))
        #expect(jobs.count == config.industryJobs.count)
        let jobKeys: Set = ["activity_id", "blueprint_id", "blueprint_location_id", "blueprint_type_id", "duration",
                            "end_date", "facility_id", "installer_id", "job_id", "output_location_id", "runs",
                            "start_date", "station_id", "status"]
        for job in jobs {
            #expect(keys(job).isSuperset(of: jobKeys))
            #expect(job["installer_id"] == .int(DemoIDs.characterID))
            let start = try #require(date(job["start_date"])), end = try #require(date(job["end_date"]))
            #expect(end.timeIntervalSince(start) == Double(try #require(job["duration"]?.int)))
            #expect(start < recordedAt)
            #expect(job["status"] == .string("active") ? end > recordedAt : end <= recordedAt)
        }

        let contracts = try #require(body("GetCharactersCharacterIdContracts", demo + "/contracts"))
        #expect(contracts.count == config.contracts.count)
        let contractKeys: Set = ["acceptor_id", "assignee_id", "availability", "contract_id", "date_expired", "date_issued",
                                 "for_corporation", "issuer_corporation_id", "issuer_id", "status", "type"]
        for (contract, source) in zip(contracts, config.contracts) {
            #expect(keys(contract).isSuperset(of: contractKeys))
            #expect(archive.names[String(source.issuerID)] != nil)
            #expect(archive.names[String(source.issuerCorporationID)] != nil)
            let items = try #require(body("GetCharactersCharacterIdContractsContractIdItems",
                                          demo + "/contracts/\(source.contractID)/items"))
            #expect(items.count == source.items.count)
            #expect(items.allSatisfy {
                keys($0) == ["record_id", "type_id", "quantity", "is_included", "is_singleton"]
                    && $0["record_id"]?.int.map(DemoIDs.contains) == true
            })
        }
        #expect(archive.names["60003760"]?.category == "station")
    }

    @Test func skillQueueFollowsTheRecordedSkills() throws {
        let config = try loadConfig()
        let archive = try DemoExporter(config: config).export(fakeRecording())
        let queue = try #require(archive.entries.first { $0.operationID == "GetCharactersCharacterIdSkillqueue" }?.body?.array)
        #expect(queue.count == config.skillQueue.entries.count)
        #expect((5 ... 7).contains(queue.count))
        #expect([1, 2, 3, 4, 5].map { DemoExporter.skillPoints(rank: 1, level: $0) } == [250, 1415, 8000, 45255, 256_000])
        #expect(DemoExporter.skillPoints(rank: 5, level: 4) == 226_275)

        var levels = Dictionary(uniqueKeysWithValues: queuedSkills.map { ($0.0, $0.1) })
        var previousFinish: Date?
        for (position, (entry, source)) in zip(queue, config.skillQueue.entries).enumerated() {
            #expect(entry["queue_position"] == .int(Int64(position)))
            #expect(entry["skill_id"] == .int(source.skillID))
            let level = try #require(entry["finished_level"]?.int)
            #expect(level == (levels[source.skillID] ?? 0) + 1)
            levels[source.skillID] = level
            let startPoints = try #require(entry["level_start_sp"]?.int), endPoints = try #require(entry["level_end_sp"]?.int)
            #expect(startPoints == DemoExporter.skillPoints(rank: source.rank, level: Int(level) - 1))
            #expect(endPoints == DemoExporter.skillPoints(rank: source.rank, level: Int(level)))
            #expect(entry["training_start_sp"]?.int == startPoints)
            if let points = queuedSkills.first(where: { $0.0 == source.skillID && $0.1 == level - 1 })?.2 {
                #expect(points == startPoints)
            }

            let start = try #require(entry["start_date"]?.string.flatMap { try? Date($0, strategy: .iso8601) })
            let finish = try #require(entry["finish_date"]?.string.flatMap { try? Date($0, strategy: .iso8601) })
            if let previousFinish { #expect(start == previousFinish) }
            previousFinish = finish
            let attribute = { (name: String) in Double(20 + (config.skillQueue.attributeBonus[name] ?? 0)) }
            let rate = (attribute(source.primary) + attribute(source.secondary) / 2) / 60
            #expect(abs(finish.timeIntervalSince(start) - Double(endPoints - startPoints) / rate) <= 1)
            if position == 0 {
                #expect(start < recordedAt && finish > recordedAt)
                #expect(finish.timeIntervalSince(recordedAt) < 12 * 3600)
            }
        }
    }

    @Test func skillQueueRejectsSkillsItDoesNotFollow() throws {
        let config = try loadConfig()
        var recording = fakeRecording()
        let index = try #require(recording.entries.firstIndex { $0.operationID == "GetCharactersCharacterIdSkills" })
        recording.entries[index].body = .object(["skills": .array([
            .object(["skill_id": .int(3386), "trained_skill_level": .int(1), "skillpoints_in_skill": .int(250)]),
        ])])
        #expect(throws: DemoExportError.self) { try DemoExporter(config: config).export(recording) }

        var synthetic = config
        synthetic.orders.open[0].orderID = 6_000_000_001
        #expect(throws: DemoExportError.self) { try DemoExporter(config: synthetic).export(fakeRecording()) }
    }

    @Test func cleansPlayerAuthoredStrings() throws {
        let config = try loadConfig()
        let archive = try DemoExporter(config: config).export(fakeRecording())
        let fittings = try #require(archive.entries.first { $0.operationID == "GetCharactersCharacterIdFittings" }?.body?.array)
        #expect(fittings.map { $0["fitting_id"] } == [.int(2), .int(4)])
        #expect(fittings.map { $0["name"] } == [.string("Deimos – Railguns"), .string("Machariel – Autocannons")])
        #expect(fittings.allSatisfy { $0["description"] == .string("") && $0["items"]?.array?.count == 1 })
        #expect(fittings.count <= config.fittings.maxCount)
        #expect(archive.assetNames.values.allSatisfy { $0.hasPrefix("Demo Pilot's ") })
        #expect(archive.assetNames["1040000000009"] == nil)
    }
}
