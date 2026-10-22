import DemoFixtures
import ESIKit
import Foundation
import HTTPTypes
import OpenAPIRuntime
import Synchronization

/// A middleware that records ESI responses for the demo fixtures.
///
/// Keeps the operation, method, path, query, request body, status, `X-Pages`,
/// `Last-Modified` and response body of every request; never request headers. A repeated
/// request replaces the earlier record.
public final class DemoRecorder: ClientMiddleware, Sendable {

    private struct State {
        var order: [DemoRequestKey] = []
        var entries: [DemoRequestKey: DemoArchive.Entry] = [:]
    }

    private let state = Mutex(State())
    private let compatibilityDate: String
    private let limit: Int

    /// - Parameters:
    ///   - compatibilityDate: The `X-Compatibility-Date` the client sends.
    ///   - limit: The largest body kept, in bytes.
    public init(compatibilityDate: String = ESIConfiguration.defaultCompatibilityDate, limit: Int = 32 << 20) {
        self.compatibilityDate = compatibilityDate
        self.limit = limit
    }

    public var entryCount: Int {
        state.withLock { $0.entries.count }
    }

    public func intercept(_ request: HTTPRequest, body: HTTPBody?, baseURL: URL, operationID: String,
                          next: @Sendable (HTTPRequest, HTTPBody?, URL) async throws -> (HTTPResponse, HTTPBody?))
        async throws -> (HTTPResponse, HTTPBody?) {
        let requestData: Data? = if let body { try await Data(collecting: body, upTo: limit) } else { nil }
        let (response, responseBody) = try await next(request, requestData.map { HTTPBody($0) }, baseURL)
        let responseData: Data? = if let responseBody { try await Data(collecting: responseBody, upTo: limit) } else { nil }

        let target = request.path ?? "/"
        let key = DemoRequestKey(method: request.method.rawValue, operationID: operationID, target: target,
                                 body: requestData)
        let entry = DemoArchive.Entry(
            operationID: operationID,
            method: key.method,
            path: key.path,
            query: key.query,
            bodyDigest: key.bodyDigest,
            status: response.status.code,
            headers: DemoArchive.Headers(
                xPages: response.headerFields[HTTPField.Name("X-Pages")!].flatMap { Int($0) },
                lastModified: response.headerFields[.lastModified]
            ),
            body: responseData.flatMap { $0.isEmpty ? nil : try? DemoJSON(data: $0) },
            requestBody: requestData.flatMap { try? DemoJSON(data: $0) }
        )
        state.withLock { state in
            if state.entries.updateValue(entry, forKey: key) == nil {
                state.order.append(key)
            }
        }
        return (response, responseData.map { HTTPBody($0) })
    }

    /// Everything recorded so far.
    /// - Parameters:
    ///   - pilotID: The character the authenticated requests were made as.
    ///   - ownerHash: Its SSO owner hash, for the exporter's leak check.
    public func recording(pilotID: Int64, ownerHash: String? = nil, recordedAt: Date = .now) -> DemoRecording {
        let entries = state.withLock { state in state.order.compactMap { state.entries[$0] } }
        return DemoRecording(recordedAt: Date(timeIntervalSince1970: recordedAt.timeIntervalSince1970.rounded(.down)),
                             compatibilityDate: compatibilityDate, pilotID: pilotID, ownerHash: ownerHash,
                             entries: entries)
    }

    /// Writes `recording(pilotID:ownerHash:)` to `url`, creating the directory.
    public func write(to url: URL, pilotID: Int64, ownerHash: String? = nil) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try recording(pilotID: pilotID, ownerHash: ownerHash).encoded().write(to: url, options: .atomic)
    }
}
