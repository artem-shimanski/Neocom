import DemoFixtures
import ESIKit
import Foundation
import HTTPTypes
import OpenAPIRuntime
import Synchronization

/// A `ClientTransport` that answers the demo pilot's requests from a `DemoArchive`.
///
/// Resolution order:
/// 1. a recorded response with the same `DemoRequestKey`, dates rebased to now;
/// 2. built-in handlers: `/universe/names` and asset names from the archive tables, the CSPA
///    charge, and the write policy (mail updates succeed, every other write fails with
///    `writeRejectionMessage`);
/// 3. `404` for any other request about a demo id, `403` for public routes that need a token;
/// 4. everything else goes to `upstream`, through `upstreamMiddlewares`. Requests about demo ids
///    never reach it.
///
/// Answers given here never pass `upstreamMiddlewares`: a local answer does not wait on ESI's error
/// budget, and spends none of it.
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

    /// Routes that answer only with a token. Sent without one they fail and spend ESI's error
    /// budget, which the app's clients share, so they are answered `403` here.
    public static let tokenOnlyOperations: Set<String> = [
        "GetUniverseStructuresStructureId",
    ]

    /// `URLSessionTransport`, the transport ESIKit uses by default.
    public static var defaultUpstream: any ClientTransport {
        ESI(configuration: ESIConfiguration(userAgent: "Neocom")).transport
    }

    private let store: Task<Store, any Error>
    private let upstream: any ClientTransport
    private let upstreamMiddlewares: [any ClientMiddleware]
    private let writeRejectionMessage: String
    private let publicReadOnlyOperations: Set<String>
    private let onMiss: (@Sendable (DemoRequestKey, Miss) -> Void)?

    /// - Parameters:
    ///   - archive: The demo data.
    ///   - writeRejectionMessage: Sent as `{"error": …}` with the `400` that answers a write.
    ///   - upstream: Receives requests that are not about the demo pilot.
    ///   - upstreamMiddlewares: Run around every request sent to `upstream`, outermost first.
    ///   - publicReadOnlyOperations: Non-`GET` operations that are not writes.
    ///   - now: The moment dates are rebased to, read once: every response of one transport
    ///     shifts by the same amount.
    ///   - onMiss: Called for every request without a recorded response.
    public init(archive: DemoArchive,
                writeRejectionMessage: String,
                upstream: any ClientTransport = DemoTransport.defaultUpstream,
                upstreamMiddlewares: [any ClientMiddleware] = [],
                publicReadOnlyOperations: Set<String> = DemoTransport.publicReadOnlyOperations,
                now: @escaping @Sendable () -> Date = { .now },
                onMiss: (@Sendable (DemoRequestKey, Miss) -> Void)? = nil) {
        self.init(loadArchive: { archive }, writeRejectionMessage: writeRejectionMessage, upstream: upstream,
                  upstreamMiddlewares: upstreamMiddlewares, publicReadOnlyOperations: publicReadOnlyOperations,
                  now: now, onMiss: onMiss)
    }

    /// Starts `loadArchive` in the background right away; requests wait for it.
    public init(loadArchive: @escaping @Sendable () async throws -> DemoArchive,
                writeRejectionMessage: String,
                upstream: any ClientTransport = DemoTransport.defaultUpstream,
                upstreamMiddlewares: [any ClientMiddleware] = [],
                publicReadOnlyOperations: Set<String> = DemoTransport.publicReadOnlyOperations,
                now: @escaping @Sendable () -> Date = { .now },
                onMiss: (@Sendable (DemoRequestKey, Miss) -> Void)? = nil) {
        let startedAt = now()
        self.store = Task.detached(priority: .userInitiated) {
            let archive = try await loadArchive()
            return Store(archive: archive, rebaser: DemoRebaser(recordedAt: archive.recordedAt, now: startedAt))
        }
        self.writeRejectionMessage = writeRejectionMessage
        self.upstream = upstream
        self.upstreamMiddlewares = upstreamMiddlewares
        self.publicReadOnlyOperations = publicReadOnlyOperations
        self.onMiss = onMiss
    }

    public func send(_ request: HTTPRequest, body: HTTPBody?, baseURL: URL,
                     operationID: String) async throws -> (HTTPResponse, HTTPBody?) {
        let requestData: Data? = if let body { try await Data(collecting: body, upTo: 16 << 20) } else { nil }
        let target = request.path ?? "/"
        let key = DemoRequestKey(method: request.method.rawValue, operationID: operationID,
                                 target: target, body: requestData)
        let store = try await self.store.value

        if let entry = store.entries[key] {
            return response(for: entry, store: store)
        }

        let isDemo = DemoIDs.contains(path: key.path)
        switch (request.method, operationID) {
        case (.post, "PostUniverseNames"):
            return try await universeNames(request, body: requestData, baseURL: baseURL, operationID: operationID,
                                           store: store)
        case (.post, "PostCharactersCharacterIdAssetsNames") where isDemo:
            return assetNames(body: requestData, store: store)
        case (.post, "PostCharactersCharacterIdCspa") where isDemo:
            return json(status: 201, .double(0))
        case (.put, "PutCharactersCharacterIdMailMailId") where isDemo:
            if let mailID = key.path.split(separator: "/").last.flatMap({ Int64($0) }),
               let update = requestData.flatMap({ try? DemoJSON(data: $0) }) {
                store.updateMail(mailID, read: update["read"]?.bool, labels: update["labels"]?.array?.compactMap(\.int))
            }
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
        if Self.tokenOnlyOperations.contains(operationID) {
            onMiss?(key, .notFound)
            return json(status: 403, .object(["error": .string("Forbidden")]))
        }
        onMiss?(key, .forwarded)
        return try await forward(request, body: requestData.map { HTTPBody($0) }, baseURL: baseURL,
                                 operationID: operationID)
    }

    private func forward(_ request: HTTPRequest, body: HTTPBody?, baseURL: URL,
                         operationID: String) async throws -> (HTTPResponse, HTTPBody?) {
        var next: @Sendable (HTTPRequest, HTTPBody?, URL) async throws -> (HTTPResponse, HTTPBody?) = {
            [upstream] request, body, baseURL in
            try await upstream.send(request, body: body, baseURL: baseURL, operationID: operationID)
        }
        for middleware in upstreamMiddlewares.reversed() {
            let inner = next
            next = { request, body, baseURL in
                try await middleware.intercept(request, body: body, baseURL: baseURL, operationID: operationID,
                                               next: inner)
            }
        }
        return try await next(request, body, baseURL)
    }

    /// `Last-Modified` is passed on as recorded: it only tells whether pages belong together.
    private func response(for entry: DemoArchive.Entry, store: Store) -> (HTTPResponse, HTTPBody?) {
        var response = HTTPResponse(status: .init(code: entry.status))
        if let pages = entry.headers.xPages {
            response.headerFields[.xPages] = String(pages)
        }
        if let lastModified = entry.headers.lastModified {
            response.headerFields[.lastModified] = lastModified
        }
        guard let body = store.body(of: entry), let data = try? store.rebaser.rebase(body).data() else {
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

    private func universeNames(_ request: HTTPRequest, body: Data?, baseURL: URL, operationID: String,
                               store: Store) async throws -> (HTTPResponse, HTTPBody?) {
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
            if let (response, responseBody) = try? await forward(request, body: HTTPBody(payload),
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

    private func assetNames(body: Data?, store: Store) -> (HTTPResponse, HTTPBody?) {
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
        struct MailUpdate: Sendable {
            var read: Bool?
            var labels: [Int64]?
        }

        static let mailOperation = "GetCharactersCharacterIdMail"
        static let mailBodyOperation = "GetCharactersCharacterIdMailMailId"
        static let mailLabelsOperation = "GetCharactersCharacterIdMailLabels"

        let archive: DemoArchive
        let entries: [DemoRequestKey: DemoArchive.Entry]
        let rebaser: DemoRebaser
        /// Read flags and labels set by `PUT /characters/{id}/mail/{mail_id}`, by mail id. They
        /// live as long as the transport, so they outlast the cache of the mail routes.
        private let mailUpdates = Mutex<[Int64: MailUpdate]>([:])

        init(archive: DemoArchive, rebaser: DemoRebaser) {
            self.archive = archive
            self.rebaser = rebaser
            self.entries = Dictionary(archive.entries.map { ($0.key, $0) }, uniquingKeysWith: { _, last in last })
        }

        func updateMail(_ mailID: Int64, read: Bool?, labels: [Int64]?) {
            mailUpdates.withLock { updates in
                var update = updates[mailID] ?? MailUpdate()
                if let read { update.read = read }
                if let labels { update.labels = labels }
                updates[mailID] = update
            }
        }

        /// The recorded body with the mail updates applied.
        func body(of entry: DemoArchive.Entry) -> DemoJSON? {
            guard let body = entry.body else { return nil }
            let updates = mailUpdates.withLock { $0 }
            guard !updates.isEmpty else { return body }
            switch entry.operationID {
            case Self.mailOperation:
                guard let filter = Self.labelFilter(entry.query), let inbox = allMail(of: entry, updates: updates) else {
                    return .array((body.array ?? []).map { Self.apply(updates, to: $0, readKey: "is_read") })
                }
                return .array(inbox.filter { mail in
                    (mail["labels"]?.array ?? []).contains { $0.int.map(filter.contains) == true }
                })
            case Self.mailBodyOperation:
                let mailID = entry.path.split(separator: "/").last.flatMap { Int64($0) }
                return Self.apply(updates, to: body, mailID: mailID, readKey: "read")
            case Self.mailLabelsOperation:
                guard let inbox = allMail(of: entry, updates: updates) else { return body }
                let unread = inbox.filter { $0["is_read"] != .bool(true) }
                var result = body
                result["labels"] = body["labels"]?.array.map { labels in
                    .array(labels.map { label in
                        var label = label
                        let id = label["label_id"]?.int
                        label["unread_count"] = .int(Int64(unread.filter {
                            ($0["labels"]?.array ?? []).contains { $0.int == id }
                        }.count))
                        return label
                    })
                }
                result["total_unread_count"] = .int(Int64(unread.count))
                return result
            default:
                return body
            }
        }

        /// The unfiltered mail list next to `entry`, updates applied.
        private func allMail(of entry: DemoArchive.Entry, updates: [Int64: MailUpdate]) -> [DemoJSON]? {
            let path = entry.operationID == Self.mailLabelsOperation
                ? String(entry.path.dropLast("/labels".count)) : entry.path
            let key = DemoRequestKey(method: "GET", operationID: Self.mailOperation, path: path, query: "", bodyDigest: nil)
            return entries[key]?.body?.array?.map { Self.apply(updates, to: $0, readKey: "is_read") }
        }

        /// The label ids of a `labels=…` query that has nothing else.
        private static func labelFilter(_ query: String) -> Set<Int64>? {
            guard query.hasPrefix("labels="), !query.contains("&") else { return nil }
            return Set(query.dropFirst("labels=".count).split(separator: ",").compactMap { Int64($0) })
        }

        private static func apply(_ updates: [Int64: MailUpdate], to mail: DemoJSON, mailID: Int64? = nil,
                                  readKey: String) -> DemoJSON {
            guard let id = mailID ?? mail["mail_id"]?.int, let update = updates[id] else { return mail }
            var mail = mail
            if let read = update.read { mail[readKey] = .bool(read) }
            if let labels = update.labels { mail["labels"] = .array(labels.map(DemoJSON.int)) }
            return mail
        }
    }
}

extension HTTPField.Name {
    static let xPages = HTTPField.Name("X-Pages")!
}
