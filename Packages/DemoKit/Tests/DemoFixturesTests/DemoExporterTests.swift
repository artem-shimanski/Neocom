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
              body: .array([object(["item_id": .int(ship), "name": .string("Real Capsuleer's Rifter")])]),
              request: .array([.int(ship)])),
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
        ]), request: .array([.int(realID), .int(realCorp), .int(95_000_001), .int(30_000_142)])),
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
        entry("GetCharactersCharacterIdFittings", me + "/fittings", status: 404, body: object(["error": .string("x")])),
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

        let assets = try #require(body("GetCharactersCharacterIdAssets", demo + "/assets")?.array)
        #expect(assets[0]["location_id"] == .int(60_004_420))
        #expect(assets[0]["location_type"] == .string("station"))
        #expect(assets[0]["item_id"] == .int(ship))
        #expect(assets[1]["location_id"] == .int(60_003_760))
        let inner = try #require(body("GetCharactersCharacterIdAssets", demo + "/assets", query: "page=2")?.array)
        #expect(inner[0]["location_id"] == .int(container))
        #expect(inner[0]["location_type"] == .string("item"))
        #expect(archive.assetNames == [String(ship): "Demo Pilot's Rifter"])

        let clones = try #require(body("GetCharactersCharacterIdClones", demo + "/clones"))
        #expect(clones["home_location"] == .object(["location_id": .int(60_004_420), "location_type": .string("station")]))
        let location = try #require(body("GetCharactersCharacterIdLocation", demo + "/location"))
        #expect(location == .object(["solar_system_id": .int(30_001_407), "station_id": .int(60_004_420)]))

        let contract = try #require(body("GetCharactersCharacterIdContracts", demo + "/contracts")?.array?.first)
        #expect(contract["issuer_id"] == .int(DemoIDs.characterID))
        #expect(contract["issuer_corporation_id"] == .int(1_000_044))
        #expect(contract["acceptor_id"] == .int(0))
        let partner = try #require(contract["assignee_id"]?.int)
        #expect(DemoIDs.contains(partner))
        #expect(archive.names[String(partner)] == DemoArchive.Name(name: "Aldren Vask", category: "character"))

        let killmail = try #require(body("GetCharactersCharacterIdKillmailsRecent", demo + "/killmails/recent")?.array?.first)
        let killmailID = try #require(killmail["killmail_id"]?.int)
        let hash = try #require(killmail["killmail_hash"]?.string)
        #expect(DemoIDs.contains(killmailID))
        #expect(hash.count == 40 && hash != "0123456789abcdef0123456789abcdef01234567")
        let detail = try #require(body("GetKillmailsKillmailIdKillmailHash", "/killmails/\(killmailID)/\(hash)"))
        #expect(detail["killmail_id"] == .int(killmailID))
        #expect(detail["victim"] == .object(["character_id": .int(DemoIDs.characterID),
                                             "corporation_id": .int(1_000_044), "ship_type_id": .int(587)]))
        #expect(detail["attackers"]?.array?.first?["character_id"]?.int.map(DemoIDs.contains) == true)

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
}
