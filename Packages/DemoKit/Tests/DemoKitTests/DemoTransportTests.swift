import DemoExport
import DemoFixtures
import DemoKit
import ESIKit
import Foundation
import HTTPTypes
import OpenAPIRuntime
import Synchronization
import Testing

private let demo = DemoIDs.characterID
private let recordedAt = Date(timeIntervalSince1970: 1_792_497_600) // 2026-10-20 12:00 UTC
private let now = recordedAt.addingTimeInterval(86_400 * 2)
private let baseURL = URL(string: "https://esi.evetech.net")!
private let message = "The demo pilot can't change anything in EVE."

/// Records what reaches it and answers `/universe/names` for the ids it is asked about.
final class StubUpstream: ClientTransport, Sendable {
    let calls = Mutex<[(String, String, Data?)]>([])

    func send(_ request: HTTPRequest, body: HTTPBody?, baseURL: URL,
              operationID: String) async throws -> (HTTPResponse, HTTPBody?) {
        let data: Data? = if let body { try await Data(collecting: body, upTo: 1 << 20) } else { nil }
        calls.withLock { $0.append((operationID, request.path ?? "", data)) }
        var response = HTTPResponse(status: .ok)
        response.headerFields[.contentType] = "application/json"
        if operationID == "PostUniverseNames", let data, let ids = try DemoJSON(data: data).array {
            let names = DemoJSON.array(ids.compactMap(\.int).map {
                .object(["id": .int($0), "name": .string("Live \($0)"), "category": .string("solar_system")])
            })
            return (response, HTTPBody(try names.data()))
        }
        return (response, HTTPBody(Data("[]".utf8)))
    }

    var paths: [String] { calls.withLock { $0.map(\.1) } }
}

private func archive() -> DemoArchive {
    DemoArchive(
        recordedAt: recordedAt,
        compatibilityDate: ESIConfiguration.defaultCompatibilityDate,
        pilot: DemoArchive.Pilot(id: demo, name: "Demo Pilot", corporationID: 1_000_044),
        entries: [
            DemoArchive.Entry(
                operationID: "GetCharactersCharacterIdAssets", method: "GET", path: "/characters/\(demo)/assets",
                headers: DemoArchive.Headers(xPages: 2, lastModified: "Tue, 20 Oct 2026 11:58:00 GMT"),
                body: .array([.object([
                    "item_id": .int(1_040_000_000_001), "location_id": .int(60_004_420),
                    "location_type": .string("station"), "location_flag": .string("Hangar"),
                    "type_id": .int(587), "quantity": .int(1), "is_singleton": .bool(true),
                ])])
            ),
            DemoArchive.Entry(
                operationID: "GetCharactersCharacterIdAssets", method: "GET", path: "/characters/\(demo)/assets",
                query: "page=2", headers: DemoArchive.Headers(xPages: 2), body: .array([])
            ),
            DemoArchive.Entry(
                operationID: "GetCharactersCharacterIdIndustryJobs", method: "GET",
                path: "/characters/\(demo)/industry/jobs", query: "include_completed=true",
                body: .array([.object(["job_id": .int(1), "end_date": .string("2026-10-20T18:00:00Z")])])
            ),
        ],
        names: [
            String(demo): DemoArchive.Name(name: "Demo Pilot", category: "character"),
            "1000044": DemoArchive.Name(name: "School of Applied Knowledge", category: "corporation"),
        ],
        assetNames: ["1040000000001": "Demo Rifter"]
    )
}

private func transport(_ upstream: StubUpstream, onMiss: (@Sendable (DemoRequestKey, DemoTransport.Miss) -> Void)? = nil)
    -> DemoTransport {
    DemoTransport(archive: archive(), writeRejectionMessage: message, upstream: upstream, now: { now }, onMiss: onMiss)
}

private func send(_ transport: DemoTransport, _ method: HTTPRequest.Method, _ path: String, operationID: String,
                  body: String? = nil) async throws -> (HTTPResponse, DemoJSON?) {
    let request = HTTPRequest(method: method, scheme: "https", authority: "esi.evetech.net", path: path)
    let (response, responseBody) = try await transport.send(request, body: body.map { HTTPBody(Data($0.utf8)) },
                                                            baseURL: baseURL, operationID: operationID)
    let data: Data? = if let responseBody { try await Data(collecting: responseBody, upTo: 1 << 20) } else { nil }
    return (response, try data.map { try DemoJSON(data: $0) })
}

@Suite struct DemoTransportTests {
    @Test func servesFixturesRebased() async throws {
        let upstream = StubUpstream()
        let transport = transport(upstream)
        let (response, body) = try await send(transport, .get, "/characters/\(demo)/assets?page=1",
                                              operationID: "GetCharactersCharacterIdAssets")
        #expect(response.status.code == 200)
        #expect(response.headerFields[HTTPField.Name("X-Pages")!] == "2")
        #expect(response.headerFields[.lastModified] == "Thu, 22 Oct 2026 11:58:00 GMT")
        #expect(body?.array?.first?["item_id"] == .int(1_040_000_000_001))

        let (_, jobs) = try await send(transport, .get, "/characters/\(demo)/industry/jobs?include_completed=true",
                                       operationID: "GetCharactersCharacterIdIndustryJobs")
        #expect(jobs?.array?.first?["end_date"] == .string("2026-10-22T18:00:00Z"))
        #expect(upstream.paths.isEmpty)
    }

    @Test func decodesThroughTheGeneratedClient() async throws {
        let upstream = StubUpstream()
        let client = Client(esi: ESI(configuration: ESIConfiguration(userAgent: "DemoKitTests"),
                                     transport: transport(upstream)))
        let output = try await client.getCharactersCharacterIdAssets(
            path: .init(characterId: demo), query: .init(page: 2),
            headers: .init(xCompatibilityDate: .init(rawValue: ESIConfiguration.defaultCompatibilityDate)!)
        )
        guard case let .ok(ok) = output else { Issue.record("unexpected \(output)"); return }
        #expect(ok.headers.xPages == 2)
        #expect(try ok.body.json.isEmpty)

        let first = try await client.getCharactersCharacterIdAssets(
            path: .init(characterId: demo),
            headers: .init(xCompatibilityDate: .init(rawValue: ESIConfiguration.defaultCompatibilityDate)!)
        )
        guard case let .ok(page) = first else { Issue.record("unexpected \(first)"); return }
        #expect(try page.body.json.first?.locationId == 60_004_420)
        #expect(page.headers.lastModified == "Thu, 22 Oct 2026 11:58:00 GMT")
        #expect(upstream.paths.isEmpty)
    }

    @Test func mergesNamesWithUpstream() async throws {
        let upstream = StubUpstream()
        let (response, body) = try await send(transport(upstream), .post, "/universe/names",
                                              operationID: "PostUniverseNames",
                                              body: "[\(demo), 1000044, 30001407, 8000000000000500]")
        #expect(response.status.code == 200)
        let names = Dictionary(uniqueKeysWithValues: (body?.array ?? []).compactMap { item in
            item["id"]?.int.flatMap { id in item["name"]?.string.map { (id, $0) } }
        })
        #expect(names == [demo: "Demo Pilot", 1_000_044: "School of Applied Knowledge", 30_001_407: "Live 30001407"])
        let calls = upstream.calls.withLock { $0 }
        #expect(calls.count == 1)
        #expect(calls.first?.2.flatMap { try? DemoJSON(data: $0) } == .array([.int(30_001_407)]))
    }

    @Test func answersAssetNames() async throws {
        let upstream = StubUpstream()
        let (_, body) = try await send(transport(upstream), .post, "/characters/\(demo)/assets/names",
                                       operationID: "PostCharactersCharacterIdAssetsNames",
                                       body: "[1040000000001, 1040000000002]")
        #expect(body == .array([
            .object(["item_id": .int(1_040_000_000_001), "name": .string("Demo Rifter")]),
            .object(["item_id": .int(1_040_000_000_002), "name": .string("None")]),
        ]))
        #expect(upstream.paths.isEmpty)
    }

    @Test func appliesTheWritePolicy() async throws {
        let upstream = StubUpstream()
        let misses = Mutex<[DemoTransport.Miss]>([])
        let transport = transport(upstream) { _, miss in misses.withLock { $0.append(miss) } }

        let (put, putBody) = try await send(transport, .put, "/characters/\(demo)/mail/8000000000003001",
                                            operationID: "PutCharactersCharacterIdMailMailId", body: #"{"read":true}"#)
        #expect(put.status.code == 204)
        #expect(putBody == nil)

        let (post, postBody) = try await send(transport, .post, "/characters/\(demo)/mail",
                                              operationID: "PostCharactersCharacterIdMail", body: #"{"subject":"x"}"#)
        #expect(post.status.code == 400)
        #expect(postBody == .object(["error": .string(message)]))

        let (ui, _) = try await send(transport, .post, "/ui/openwindow/information?target_id=1",
                                     operationID: "PostUiOpenwindowInformation")
        #expect(ui.status.code == 400)

        let (delete, _) = try await send(transport, .delete, "/characters/\(demo)/fittings/1",
                                         operationID: "DeleteCharactersCharacterIdFittingsFittingId")
        #expect(delete.status.code == 400)
        #expect(upstream.paths.isEmpty)
        #expect(misses.withLock { $0 } == [.rejected, .rejected, .rejected])
    }

    @Test func missesOnDemoPathsAreNotFound() async throws {
        let upstream = StubUpstream()
        let misses = Mutex<[DemoRequestKey]>([])
        let transport = transport(upstream) { key, _ in misses.withLock { $0.append(key) } }
        let (response, body) = try await send(transport, .get, "/characters/\(demo)/wallet",
                                              operationID: "GetCharactersCharacterIdWallet")
        #expect(response.status.code == 404)
        #expect(body?["error"] != nil)
        let (synthetic, _) = try await send(transport, .get, "/characters/8000000000100002",
                                            operationID: "GetCharactersDetail")
        #expect(synthetic.status.code == 404)
        let (page, _) = try await send(transport, .get, "/characters/\(demo)/assets?page=3",
                                       operationID: "GetCharactersCharacterIdAssets")
        #expect(page.status.code == 404)
        #expect(upstream.paths.isEmpty)
        #expect(misses.withLock { $0.map(\.path) } == ["/characters/\(demo)/wallet", "/characters/8000000000100002",
                                                       "/characters/\(demo)/assets"])
    }

    @Test func forwardsPublicMisses() async throws {
        let upstream = StubUpstream()
        let transport = transport(upstream)
        let (response, _) = try await send(transport, .get, "/markets/prices", operationID: "GetMarketsPrices")
        #expect(response.status.code == 200)
        let (route, _) = try await send(transport, .post, "/route/30000142/30001407", operationID: "PostRoute",
                                        body: #"{"preference":"Shorter"}"#)
        #expect(route.status.code == 200)
        #expect(upstream.paths == ["/markets/prices", "/route/30000142/30001407"])
        #expect(upstream.calls.withLock { $0.last?.2 } == Data(#"{"preference":"Shorter"}"#.utf8))
    }
}

@Suite struct DemoRecorderTests {
    @Test func recordsResponsesAndPassesThemOn() async throws {
        let recorder = DemoRecorder()
        let request = HTTPRequest(method: .post, scheme: "https", authority: "esi.evetech.net",
                                  path: "/characters/2112345678/assets/names", headerFields: [.authorization: "Bearer eyJsecret"])
        let (response, body) = try await recorder.intercept(
            request, body: HTTPBody(Data("[2, 1]".utf8)), baseURL: baseURL,
            operationID: "PostCharactersCharacterIdAssetsNames"
        ) { request, body, _ in
            let sent = try await Data(collecting: body!, upTo: 1024)
            #expect(sent == Data("[2, 1]".utf8))
            var response = HTTPResponse(status: .ok)
            response.headerFields[HTTPField.Name("X-Pages")!] = "3"
            response.headerFields[.lastModified] = "Tue, 20 Oct 2026 11:58:00 GMT"
            return (response, HTTPBody(Data(#"[{"item_id":1,"name":"Ship"}]"#.utf8)))
        }
        #expect(response.status.code == 200)
        #expect(try await Data(collecting: body!, upTo: 1024) == Data(#"[{"item_id":1,"name":"Ship"}]"#.utf8))

        let recording = recorder.recording(pilotID: 2_112_345_678, ownerHash: "hash", recordedAt: recordedAt)
        #expect(recording.compatibilityDate == ESIConfiguration.defaultCompatibilityDate)
        let entry = try #require(recording.entries.first)
        #expect(entry.path == "/characters/2112345678/assets/names")
        #expect(entry.method == "POST")
        #expect(entry.headers == DemoArchive.Headers(xPages: 3, lastModified: "Tue, 20 Oct 2026 11:58:00 GMT"))
        #expect(entry.requestBody == .array([.int(2), .int(1)]))
        #expect(entry.bodyDigest == DemoRequestKey.digest(of: Data("[1,2]".utf8)))
        #expect(entry.body == .array([.object(["item_id": .int(1), "name": .string("Ship")])]))

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).appendingPathComponent("recording.json")
        try recorder.write(to: url, pilotID: 2_112_345_678)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let text = try String(contentsOf: url, encoding: .utf8)
        #expect(!text.contains("eyJsecret") && !text.contains("Bearer"))
        #expect(try DemoRecording.decode(from: Data(contentsOf: url)).entries.count == 1)
    }

    @Test func exportedArchiveCarriesTheClientCompatibilityDate() async throws {
        let recorder = DemoRecorder()
        let profile = HTTPRequest(method: .get, scheme: "https", authority: "esi.evetech.net", path: "/characters/2112345678")
        _ = try await recorder.intercept(profile, body: nil, baseURL: baseURL, operationID: "GetCharactersDetail") { _, _, _ in
            (HTTPResponse(status: .ok), HTTPBody(Data(#"{"name":"Real Capsuleer","corporation_id":98000001}"#.utf8)))
        }
        let config = try DemoConfig.decode(from: Data(contentsOf: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("DemoConfig.json")))
        let recording = recorder.recording(pilotID: 2_112_345_678)
        let exporter = DemoExporter(config: config)
        let data = try exporter.encode(exporter.export(recording), recording: recording)
        let archive = try DemoArchive.decode(from: data)
        #expect(archive.compatibilityDate == ESIConfiguration.defaultCompatibilityDate)
        #expect(archive.entries.contains { $0.path == "/characters/\(demo)" })
    }
}
