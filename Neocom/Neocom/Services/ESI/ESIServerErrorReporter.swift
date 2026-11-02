import Foundation
import HTTPTypes
import OpenAPIRuntime

/// Reports every `5xx` answer from ESI to `ReviewPrompter` as a failure of the session.
nonisolated struct ESIServerErrorReporter: ClientMiddleware {
    func intercept(_ request: HTTPRequest,
                   body: HTTPBody?,
                   baseURL: URL,
                   operationID: String,
                   next: @concurrent @Sendable (HTTPRequest, HTTPBody?, URL) async throws -> (HTTPResponse, HTTPBody?))
        async throws -> (HTTPResponse, HTTPBody?) {
        let (response, responseBody) = try await next(request, body, baseURL)
        if response.status.kind == .serverError {
            Task { @MainActor in ReviewPrompter.shared.recordFailure() }
        }
        return (response, responseBody)
    }
}
