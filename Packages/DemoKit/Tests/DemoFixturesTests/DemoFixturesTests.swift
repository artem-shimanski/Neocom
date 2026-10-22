import DemoFixtures
import Foundation
import Testing

@Suite struct ArchiveTests {
    @Test func decodesTheSchema() throws {
        let json = """
            {
              "version": 1,
              "recordedAt": "2026-10-20T12:00:00Z",
              "compatibilityDate": "2026-07-21",
              "pilot": { "id": 8000000000000001, "name": "Demo Pilot", "corporationID": 1000044 },
              "entries": [
                {
                  "operationID": "GetCharactersCharacterIdAssets",
                  "method": "GET",
                  "path": "/characters/8000000000000001/assets",
                  "query": "page=2",
                  "status": 200,
                  "headers": { "xPages": 2, "lastModified": "Tue, 20 Oct 2026 11:58:00 GMT" },
                  "body": [ { "item_id": 1043000000001, "is_singleton": true, "quantity": 1, "price": 1.5 } ]
                },
                {
                  "operationID": "PostCharactersCharacterIdCspa",
                  "method": "POST",
                  "path": "/characters/8000000000000001/cspa",
                  "query": "",
                  "bodyDigest": "abc",
                  "status": 201,
                  "headers": {},
                  "body": 0
                }
              ],
              "names": { "1000044": { "name": "School of Applied Knowledge", "category": "corporation" } },
              "assetNames": { "1043000000001": "Shuttle" },
              "plan": [ { "skillID": 3426, "level": 4 } ]
            }
            """
        let archive = try DemoArchive.decode(from: Data(json.utf8))
        #expect(archive.recordedAt == Date(timeIntervalSince1970: 1_792_497_600))
        #expect(archive.pilot.id == DemoIDs.characterID)
        #expect(archive.entries.count == 2)
        let assets = archive.entries[0]
        #expect(assets.page == 2)
        #expect(assets.headers.xPages == 2)
        #expect(assets.body?.array?.first?["item_id"] == .int(1_043_000_000_001))
        #expect(assets.body?.array?.first?["is_singleton"] == .bool(true))
        #expect(assets.body?.array?.first?["price"] == .double(1.5))
        #expect(archive.entries[1].body == .int(0))
        #expect(archive.entries[1].key.bodyDigest == "abc")
        #expect(archive.names["1000044"]?.category == "corporation")
        #expect(archive.plan == [DemoArchive.PlanItem(skillID: 3426, level: 4)])

        let reencoded = try DemoArchive.decode(from: archive.encoded())
        #expect(reencoded == archive)
    }

    @Test func keepsLargeIdsExact() throws {
        let value = try DemoJSON(data: Data("[8000000000000001, 9007199254740993]".utf8))
        #expect(value == .array([.int(8_000_000_000_000_001), .int(9_007_199_254_740_993)]))
        #expect(String(decoding: try value.data(), as: UTF8.self) == "[8000000000000001,9007199254740993]")
    }
}

@Suite struct RequestKeyTests {
    @Test func normalisesTheQuery() {
        #expect(DemoRequestKey.normalizedQuery("type_id=34&order_type=all&page=1") == "order_type=all&type_id=34")
        #expect(DemoRequestKey.normalizedQuery("page=1") == "")
        #expect(DemoRequestKey.normalizedQuery(nil) == "")
        #expect(DemoRequestKey.normalizedQuery("page=3&labels=4&labels=1") == "labels=1&labels=4&page=3")
        #expect(DemoRequestKey.normalizedQuery("search=Demo%20Pilot&strict=false") == "search=Demo Pilot&strict=false")
    }

    @Test func pageOneEqualsNoPage() {
        let explicit = DemoRequestKey(method: "get", operationID: "Op", target: "/characters/1/assets?page=1", body: nil)
        let implicit = DemoRequestKey(method: "GET", operationID: "Op", target: "/characters/1/assets", body: nil)
        #expect(explicit == implicit)
        #expect(explicit.path == "/characters/1/assets")
        let second = DemoRequestKey(method: "GET", operationID: "Op", target: "/characters/1/assets?page=2", body: nil)
        #expect(second != implicit)
    }

    @Test func digestsTheBody() {
        let a = DemoRequestKey.digest(of: Data("[3, 1, 2]".utf8))
        let b = DemoRequestKey.digest(of: Data("[1,2,3]".utf8))
        let c = DemoRequestKey.digest(of: Data("[1,2,4]".utf8))
        #expect(a != nil)
        #expect(a == b)
        #expect(a != c)
        #expect(DemoRequestKey.digest(of: Data(#"{"b":1,"a":2}"#.utf8)) == DemoRequestKey.digest(of: Data(#"{"a":2,"b":1}"#.utf8)))
        #expect(DemoRequestKey.digest(of: Data()) == nil)
        #expect(DemoRequestKey.digest(of: nil as Data?) == nil)
        #expect(DemoRequestKey.digest(of: DemoJSON.array([.int(2), .int(1)])) == DemoRequestKey.digest(of: Data("[1,2]".utf8)))
    }
}

@Suite struct RebaserTests {
    let rebaser = DemoRebaser(delta: 86_400 * 3 + 3600 + 0.75)

    @Test func shiftsTimestamps() {
        #expect(rebaser.delta == 262_800)
        #expect(rebaser.rebase(timestamp: "2026-10-20T12:00:00Z") == "2026-10-23T13:00:00Z")
        #expect(rebaser.rebase(timestamp: "2026-12-30T23:30:00Z") == "2027-01-03T00:30:00Z")
        #expect(rebaser.rebase(timestamp: "2028-02-27T00:00:00.123Z") == "2028-03-01T01:00:00.123Z")
        #expect(DemoRebaser(delta: -3600).rebase(timestamp: "2026-01-01T00:30:00Z") == "2025-12-31T23:30:00Z")
    }

    @Test func leavesOtherStringsAlone() {
        #expect(rebaser.rebase(timestamp: "2026-10-20") == nil)
        #expect(rebaser.rebase(timestamp: "2026-10-20T12:00:00") == nil)
        #expect(rebaser.rebase(timestamp: "2026-10-20T12:00:00+01:00") == nil)
        #expect(rebaser.rebase(timestamp: "2026-10-20T12:00:00.Z") == nil)
        #expect(rebaser.rebase(timestamp: "Meet at 2026-10-20T12:00:00Z") == nil)
        #expect(rebaser.rebase(timestamp: "2026-13-20T12:00:00Z") == nil)
    }

    @Test func rebasesBodies() {
        let body = DemoJSON.object([
            "end_date": .string("2026-10-20T12:00:00Z"),
            "date": .string("2026-10-20"),
            "name": .string("Rifter"),
            "jobs": .array([.object(["start_date": .string("2026-10-19T08:15:30.5Z"), "job_id": .int(7)])]),
        ])
        let rebased = rebaser.rebase(body)
        #expect(rebased["end_date"] == .string("2026-10-23T13:00:00Z"))
        #expect(rebased["date"] == .string("2026-10-20"))
        #expect(rebased["name"] == .string("Rifter"))
        #expect(rebased["jobs"]?.array?.first?["start_date"] == .string("2026-10-22T09:15:30.5Z"))
        #expect(rebased["jobs"]?.array?.first?["job_id"] == .int(7))
    }

    @Test func shiftsLastModified() {
        #expect(rebaser.rebase(httpDate: "Tue, 20 Oct 2026 12:00:00 GMT") == "Fri, 23 Oct 2026 13:00:00 GMT")
        #expect(rebaser.rebase(httpDate: "yesterday") == nil)
    }

    @Test func formatsTimestamps() {
        #expect(DemoRebaser.timestamp(Date(timeIntervalSince1970: 1_792_497_600.9)) == "2026-10-20T12:00:00Z")
        #expect(DemoRebaser(recordedAt: Date(timeIntervalSince1970: 0), now: Date(timeIntervalSince1970: 59.9)).delta == 59)
    }
}

@Suite struct IDTests {
    @Test func recognisesDemoIds() {
        #expect(DemoIDs.contains(DemoIDs.characterID))
        #expect(DemoIDs.contains(8_000_000_000_999_999))
        #expect(!DemoIDs.contains(8_000_000_001_000_000))
        #expect(!DemoIDs.contains(2_112_000_000))
        #expect(DemoIDs.contains(path: "/characters/8000000000000001/assets"))
        #expect(DemoIDs.contains(path: "/killmails/8000000000100000/abc"))
        #expect(!DemoIDs.contains(path: "/characters/2112000000/assets?x=8000000000000001"))
        #expect(!DemoIDs.contains(path: "/markets/prices"))
    }
}
