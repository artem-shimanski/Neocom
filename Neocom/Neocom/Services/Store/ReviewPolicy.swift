import Foundation

/// The persisted part of the review decision: usage counters and past requests, with the rules
/// that read them. Plain data; the clock and the calendar come in with every call.
nonisolated struct ReviewPolicy: Codable, Equatable, Sendable {
    static let minimumDaysSinceFirstLaunch = 7
    static let minimumActiveDays = 5
    static let minimumSuccesses = 3
    static let minimumSuccessDays = 2
    static let minimumDaysBetweenRequests = 120

    private(set) var firstLaunch: Date?
    /// Distinct calendar days the app was active on.
    private(set) var activeDays = 0
    private(set) var lastActiveDay: Date?
    private(set) var successes = 0
    /// Distinct calendar days with at least one success.
    private(set) var successDays = 0
    private(set) var lastSuccessDay: Date?
    private(set) var lastRequestVersion: String?
    private(set) var lastRequestDate: Date?
    /// The version the player opened the App Store review page from inside the app for.
    private(set) var manualReviewVersion: String?

    mutating func recordActivation(now: Date, calendar: Calendar) {
        if firstLaunch == nil { firstLaunch = now }
        if let lastActiveDay, calendar.isDate(lastActiveDay, inSameDayAs: now) { return }
        activeDays += 1
        lastActiveDay = calendar.startOfDay(for: now)
    }

    mutating func recordSuccess(now: Date, calendar: Calendar) {
        successes += 1
        if let lastSuccessDay, calendar.isDate(lastSuccessDay, inSameDayAs: now) { return }
        successDays += 1
        lastSuccessDay = calendar.startOfDay(for: now)
    }

    mutating func recordRequest(now: Date, version: String) {
        lastRequestVersion = version
        lastRequestDate = now
    }

    mutating func recordManualReview(version: String) {
        manualReviewVersion = version
    }

    /// Whether the usage so far allows a request for `version`.
    ///
    /// - Parameter hasWidget: an installed widget counts as one more active day.
    func allowsRequest(now: Date, version: String, hasWidget: Bool, calendar: Calendar) -> Bool {
        guard let firstLaunch,
              Self.days(from: firstLaunch, to: now, calendar: calendar) >= Self.minimumDaysSinceFirstLaunch,
              activeDays + (hasWidget ? 1 : 0) >= Self.minimumActiveDays,
              successes >= Self.minimumSuccesses,
              successDays >= Self.minimumSuccessDays,
              lastRequestVersion != version,
              manualReviewVersion != version
        else { return false }
        if let lastRequestDate,
           Self.days(from: lastRequestDate, to: now, calendar: calendar) < Self.minimumDaysBetweenRequests {
            return false
        }
        return true
    }

    private static func days(from start: Date, to end: Date, calendar: Calendar) -> Int {
        calendar.dateComponents([.day], from: start, to: end).day ?? 0
    }
}
