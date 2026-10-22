import Foundation

/// Tranquility's status from `/status`, as stored in `ESICache`.
nonisolated struct ServerStatus: Codable, Sendable, Hashable {
    var players: Int
    var vip: Bool
    var serverVersion: String
    var startTime: Date
}

/// Tranquility's state, derived from the last `/status` answer, the latest failure and the time.
///
/// `/status` fails while the server is down; a failure inside the daily downtime window is read
/// as the downtime, any other as an outage.
nonisolated enum ServerState: Hashable, Sendable {
    /// Up and open; the number of pilots online.
    case online(players: Int)
    /// Up, but open to CCP only.
    case vip
    /// Down inside the daily downtime window; expected back about `backAbout`.
    case downtime(backAbout: Date)
    /// Down outside the downtime window.
    case offline

    /// The daily downtime window, in minutes after 00:00 UTC.
    static let downtimeWindow = (10 * 60 + 58)..<(11 * 60 + 30)
    /// Usual end of the daily downtime, in minutes after 00:00 UTC.
    static let usualDowntimeEnd = 11 * 60 + 15

    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        return calendar
    }()

    /// The server state, or `nil` with no answer yet or when the device itself is offline.
    ///
    /// - Parameters:
    ///   - status: the last successful answer, possibly from the disk cache.
    ///   - failure: the error of the latest request, if it failed.
    static func classify(status: ServerStatus?, failure: (any Error)?, now: Date) -> ServerState? {
        if let failure {
            if isCancellation(failure) {
                return status.map(state(of:))
            }
            if isDeviceOffline(failure) {
                return nil
            }
            return isInDowntimeWindow(now) ? .downtime(backAbout: downtimeEnd(now: now)) : .offline
        }
        return status.map(state(of:))
    }

    private static func state(of status: ServerStatus) -> ServerState {
        status.vip ? .vip : .online(players: status.players)
    }

    static func isInDowntimeWindow(_ date: Date) -> Bool {
        downtimeWindow.contains(minuteOfDay(date))
    }

    /// The expected end of the downtime: 11:15 UTC, or the next five-minute mark once that has
    /// passed.
    static func downtimeEnd(now: Date) -> Date {
        let startOfDay = calendar.startOfDay(for: now)
        let usual = startOfDay.addingTimeInterval(TimeInterval(usualDowntimeEnd * 60))
        guard now >= usual else { return usual }
        let minutes = Int(now.timeIntervalSince(startOfDay) / 60) / 5 * 5 + 5
        return startOfDay.addingTimeInterval(TimeInterval(minutes * 60))
    }

    private static func minuteOfDay(_ date: Date) -> Int {
        let components = calendar.dateComponents([.hour, .minute], from: date)
        return (components.hour ?? 0) * 60 + (components.minute ?? 0)
    }

    static func isCancellation(_ error: any Error) -> Bool {
        if error is CancellationError { return true }
        return urlError(in: error)?.code == .cancelled
    }

    /// The request failed for lack of network on the device.
    static func isDeviceOffline(_ error: any Error) -> Bool {
        guard let code = urlError(in: error)?.code else { return false }
        return [.notConnectedToInternet, .networkConnectionLost, .dataNotAllowed,
                .internationalRoamingOff, .callIsActive].contains(code)
    }

    /// The underlying `URLError`. The generated client wraps transport errors in its own type
    /// with an `underlyingError` property, read through reflection to avoid depending on the
    /// OpenAPI runtime.
    private static func urlError(in error: any Error, depth: Int = 0) -> URLError? {
        if let urlError = error as? URLError { return urlError }
        guard depth < 4 else { return nil }
        for child in Mirror(reflecting: error).children where child.label == "underlyingError" {
            if let underlying = child.value as? any Error {
                return urlError(in: underlying, depth: depth + 1)
            }
        }
        return nil
    }
}
