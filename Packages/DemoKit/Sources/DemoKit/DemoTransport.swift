import DemoFixtures
import ESIKit
import Foundation
import HTTPTypes
import OpenAPIRuntime

/// A `ClientTransport` that answers the demo pilot's requests from a `DemoArchive`.
///
/// Resolution order:
/// 1. a recorded response with the same `DemoRequestKey`, dates rebased to now;
/// 2. built-in handlers: `/universe/names` and asset names from the archive tables, the CSPA
///    charge, and the write policy (mail updates succeed, every other write fails with
///    `writeRejectionMessage`);
/// 3. `404` for any other request about a demo id;
/// 4. everything else goes to `upstream`. Requests about demo ids never reach it.
public struct DemoTransport: ClientTransport {

    /// How a request without a recorded response was resolved.
    public enum Miss: Sendable, Equatable {
        case notFound
        case rejected
        case forwarded
    }

    /// Public, read-only operations that ESI exposes as `POST`; sent upstream.
    public static let publicReadOnlyOperations: Set<String> = [
        "PostUniverseIds",
        "PostCharactersAffiliation",
        "PostRoute",
    ]

    /// `URLSessionTransport`, the transport ESIKit uses by default.
    public static var defaultUpstream: any ClientTransport {
        ESI(configuration: ESIConfiguration(userAgent: "Neocom")).transport
    }

    private let store: Store
    private let upstream: any ClientTransport
    private let writeRejectionMessage: String
    private let publicReadOnlyOperations: Set<String>
    private let now: @Sendable () -> Date
    private let onMiss: (@Sendable (DemoRequestKey, Miss) -> Void)?

    /// - Parameters:
    ///   - archive: The demo data.
    ///   - writeRejectionMessage: Sent as `{"error": …}` with the `400` that answers a write.
    ///   - upstream: Receives requests that are not about the demo pilot.
    ///   - publicReadOnlyOperations: Non-`GET` operations that are not writes.
    ///   - now: The clock dates are rebased to.
    ///   - onMiss: Called for every request without a recorded response.
    public init(archive: DemoArchive,
                writeRejectionMessage: String,
                upstream: any ClientTransport = DemoTransport.defaultUpstream,
                publicReadOnlyOperations: Set<String> = DemoTransport.publicReadOnlyOperations,
                now: @escaping @Sendable () -> Date = { .now },
                onMiss: (@Sendable (DemoRequestKey, Miss) -> Void)? = nil) {
        self.store = Store(archive: archive)
        self.writeRejectionMessage = writeRejectionMessage
        self.upstream = upstream
        self.publicReadOnlyOperations = publicReadOnlyOperations
        self.now = now
        self.onMiss = onMiss
    }

    public func send(_ request: HTTPRequest, body: HTTPBody?, baseURL: URL,
                     operationID: String) async throws -> (HTTPResponse, HTTPBody?) {
        let requestData: Data? = if let body { try await Data(collecting: body, upTo: 16 << 20) } else { nil }
        let target = request.path ?? "/"
        let key = DemoRequestKey(method: request.method.rawValue, operationID: operationID,
                                 target: target, body: requestData)

        if let entry = store.entries[key] {
            return response(for: entry)
        }

        let isDemo = DemoIDs.contains(path: key.path)
        switch (request.method, operationID) {
        case (.post, "PostUniverseNames"):
            return try await universeNames(request, body: requestData, baseURL: baseURL, operationID: operationID)
        case (.post, "PostCharactersCharacterIdAssetsNames") where isDemo:
            return assetNames(body: requestData)
        case (.post, "PostCharactersCharacterIdCspa") where isDemo:
            return json(status: 201, .double(0))
        case (.put, "PutCharactersCharacterIdMailMailId") where isDemo:
            return (HTTPResponse(status: .noContent), nil)
        default:
            break
        }

        if request.method != .get, request.method != .head,
           isDemo || !publicReadOnlyOperations.contains(operationID) {
            onMiss?(key, .rejected)
            return json(status: 400, .object(["error": .string(writeRejectionMessage)]))
        }
        if isDemo {
            onMiss?(key, .notFound)
            return json(status: 404, .object(["error": .string("Not found")]))
        }
        onMiss?(key, .forwarded)
        return try await upstream.send(request, body: requestData.map { HTTPBody($0) },
                                       baseURL: baseURL, operationID: operationID)
    }

    private func response(for entry: DemoArchive.Entry) -> (HTTPResponse, HTTPBody?) {
        let rebaser = DemoRebaser(recordedAt: store.recordedAt, now: now())
        var response = HTTPResponse(status: .init(code: entry.status))
        if let pages = entry.headers.xPages {
            response.headerFields[.xPages] = String(pages)
        }
        if let lastModified = entry.headers.lastModified {
            response.headerFields[.lastModified] = rebaser.rebase(httpDate: lastModified) ?? lastModified
        }
        guard let body = entry.body, let data = try? rebaser.rebase(body).data() else {
            return (response, nil)
        }
        response.headerFields[.contentType] = "application/json; charset=utf-8"
        return (response, HTTPBody(data))
    }

    private func json(status: Int, _ value: DemoJSON) -> (HTTPResponse, HTTPBody?) {
        var response = HTTPResponse(status: .init(code: status))
        response.headerFields[.contentType] = "application/json; charset=utf-8"
        return (response, HTTPBody((try? value.data()) ?? Data()))
    }

    private func universeNames(_ request: HTTPRequest, body: Data?, baseURL: URL,
                               operationID: String) async throws -> (HTTPResponse, HTTPBody?) {
        let ids = Self.ids(in: body)
        var result: [DemoJSON] = []
        var unknown: [Int64] = []
        for id in ids {
            if let name = store.archive.names[String(id)] {
                result.append(.object(["id": .int(id), "name": .string(name.name), "category": .string(name.category)]))
            } else if !DemoIDs.contains(id) {
                unknown.append(id)
            }
        }
        if !unknown.isEmpty, let payload = try? DemoJSON.array(unknown.map(DemoJSON.int)).data() {
            onMiss?(DemoRequestKey(method: request.method.rawValue, operationID: operationID,
                                   path: request.path ?? "", query: "", bodyDigest: DemoRequestKey.digest(of: payload)),
                    .forwarded)
            if let (response, responseBody) = try? await upstream.send(request, body: HTTPBody(payload),
                                                                       baseURL: baseURL, operationID: operationID),
               response.status.code == 200,
               let responseBody,
               let data = try? await Data(collecting: responseBody, upTo: 16 << 20),
               let names = try? DemoJSON(data: data).array {
                result.append(contentsOf: names)
            }
        }
        return json(status: 200, .array(result))
    }

    private func assetNames(body: Data?) -> (HTTPResponse, HTTPBody?) {
        let names = Self.ids(in: body).map { id in
            DemoJSON.object(["item_id": .int(id), "name": .string(store.archive.assetNames[String(id)] ?? "None")])
        }
        return json(status: 200, .array(names))
    }

    private static func ids(in body: Data?) -> [Int64] {
        guard let body, let values = try? DemoJSON(data: body).array else { return [] }
        return values.compactMap(\.int)
    }

    private final class Store: Sendable {
        let archive: DemoArchive
        let entries: [DemoRequestKey: DemoArchive.Entry]
        let recordedAt: Date

        init(archive: DemoArchive) {
            self.archive = archive
            self.recordedAt = archive.recordedAt
            self.entries = Dictionary(archive.entries.map { ($0.key, $0) }, uniquingKeysWith: { _, last in last })
        }
    }
}

extension HTTPField.Name {
    static let xPages = HTTPField.Name("X-Pages")!
}
