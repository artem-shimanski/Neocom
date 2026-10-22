import ESIKit
import Foundation
import HTTPTypes
import OpenAPIRuntime

/// Drops ESI's error-limit headers from a response that `URLCache` replayed.
///
/// A cached response keeps the headers of the moment it was fetched, sometimes hours earlier.
/// Fed to the shared `ESIErrorLimiter`, a budget that was low back then parks every request for up
/// to a minute. A response older than one error window says nothing about the current one.
nonisolated struct ESIReplayedLimitMiddleware: ClientMiddleware {
    /// ESI's error window.
    static let maxAge: TimeInterval = 60

    private static let httpDate = Date.ParseStrategy(
        format: "\(weekday: .abbreviated), \(day: .twoDigits) \(month: .abbreviated) \(year: .defaultDigits) \(hour: .twoDigits(clock: .twentyFourHour, hourCycle: .zeroBased)):\(minute: .twoDigits):\(second: .twoDigits) GMT",
        locale: Locale(identifier: "en_US_POSIX"),
        timeZone: .gmt
    )

    func intercept(_ request: HTTPRequest,
                   body: HTTPBody?,
                   baseURL: URL,
                   operationID: String,
                   next: @concurrent @Sendable (HTTPRequest, HTTPBody?, URL) async throws -> (HTTPResponse, HTTPBody?))
        async throws -> (HTTPResponse, HTTPBody?) {
        var (response, responseBody) = try await next(request, body, baseURL)
        if response.headerFields[.esiErrorLimitRemain] != nil, Self.isReplayed(response.headerFields) {
            response.headerFields[.esiErrorLimitRemain] = nil
            response.headerFields[.esiErrorLimitReset] = nil
        }
        return (response, responseBody)
    }

    /// Whether the response's `Date` is older than `maxAge`. A response without one is taken as fresh.
    static func isReplayed(_ fields: HTTPFields, now: Date = .now) -> Bool {
        guard let value = fields[.date], let date = try? httpDate.parse(value) else { return false }
        return now.timeIntervalSince(date) > maxAge
    }
}
