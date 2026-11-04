import Foundation
import Observation
import StoreKit
import SwiftUI
import WidgetKit

/// A moment the player got something done.
nonisolated enum ReviewEvent: Sendable {
    /// The fit editor closed after the fit was changed.
    case fitSaved
    case fitUploaded
    /// Skills were added to a training plan.
    case planExtended
    /// Fits were imported from the old app.
    case legacyImported
    case tipped

    /// Whether the event may be followed by a review request; the others only count.
    var isTrigger: Bool {
        switch self {
        case .fitSaved, .fitUploaded, .planExtended: true
        case .legacyImported, .tipped: false
        }
    }
}

/// The only owner of the App Store review request: counts usage and success moments, decides
/// when a request is due and arms it for `reviewPrompt()` to present.
///
/// Counters live in `UserDefaults` (`ReviewPolicy`); a failure seen while the app is on screen
/// blocks the request until the app next returns from the background.
@Observable
@MainActor
final class ReviewPrompter {
    static let shared = ReviewPrompter()

    /// Set when a request is due; a new value for every trigger, so the presentation restarts its
    /// delay. Cleared once the request is made or the scene leaves the foreground.
    private(set) var pendingRequest: Int?
    /// Screens open that a request must not cover; an armed request waits until none is left.
    private(set) var holds = 0

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let version: String
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let calendar: Calendar
    @ObservationIgnored private var policy: ReviewPolicy
    @ObservationIgnored private var hasFailure = false
    /// Failures in a background launch or refresh are not the player's experience.
    @ObservationIgnored private var isForeground = false
    @ObservationIgnored private var hasCharacter: () -> Bool = { false }
    @ObservationIgnored private var hasWidget = false
    @ObservationIgnored private var didCheckWidgets = false
    @ObservationIgnored private var requestCount = 0

    private static let policyKey = "ReviewPolicy"

    init(defaults: UserDefaults = .standard,
         version: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0",
         calendar: Calendar = .current,
         now: @escaping () -> Date = Date.init) {
        self.defaults = defaults
        self.version = version
        self.calendar = calendar
        self.now = now
        policy = defaults.data(forKey: Self.policyKey)
            .flatMap { try? JSONDecoder().decode(ReviewPolicy.self, from: $0) } ?? ReviewPolicy()
    }

    /// `hasCharacter` tells whether a real character (not the demo pilot) is signed in.
    func attach(hasCharacter: @escaping () -> Bool) {
        self.hasCharacter = hasCharacter
    }

    /// Counts the day as active and checks for an installed widget once per launch.
    func recordActiveDay() {
        isForeground = true
        update { $0.recordActivation(now: now(), calendar: calendar) }
        guard !didCheckWidgets else { return }
        didCheckWidgets = true
        Task {
            let configurations = (try? await WidgetCenter.shared.currentConfigurations()) ?? []
            hasWidget = !configurations.isEmpty
        }
    }

    func record(_ event: ReviewEvent) {
        update { $0.recordSuccess(now: now(), calendar: calendar) }
        guard event.isTrigger, isRequestAllowed else { return }
        requestCount += 1
        pendingRequest = requestCount
    }

    /// Blocks the request for the rest of the foreground session.
    func recordFailure() {
        guard isForeground else { return }
        hasFailure = true
        pendingRequest = nil
    }

    /// Ends the foreground session; the next one starts with a clean failure record.
    func sceneDidEnterBackground() {
        isForeground = false
        hasFailure = false
    }

    /// The player opened the App Store review page from inside the app.
    func recordManualReview() {
        update { $0.recordManualReview(now: now(), version: version) }
        pendingRequest = nil
    }

    /// Keeps an armed request waiting until the matching `release()`.
    func hold() {
        holds += 1
    }

    func release() {
        holds = max(holds - 1, 0)
    }

    /// Drops the armed request; it is not carried over to a later return to the app.
    func cancelPendingRequest() {
        pendingRequest = nil
    }

    func didRequestReview() {
        update { $0.recordRequest(now: now(), version: version) }
        pendingRequest = nil
    }

    private var isRequestAllowed: Bool {
        !hasFailure && hasCharacter()
            && policy.allowsRequest(now: now(), version: version, hasWidget: hasWidget, calendar: calendar)
    }

    private func update(_ change: (inout ReviewPolicy) -> Void) {
        change(&policy)
        defaults.set(try? JSONEncoder().encode(policy), forKey: Self.policyKey)
    }
}

extension View {
    /// Presents the system review request that `ReviewPrompter` armed, about a second after the
    /// trigger or after the last screen holding it closed, while the scene is in the foreground. Applied once, at the root.
    func reviewPrompt() -> some View {
        modifier(ReviewPromptModifier())
    }
}

private struct ReviewPromptModifier: ViewModifier {
    private struct Trigger: Equatable {
        var request: Int?
        var isActive: Bool
        var isHeld: Bool
    }

    /// Lets the sheet or screen the trigger came from finish closing.
    private static let delay: Duration = .seconds(1)

    @Environment(ReviewPrompter.self) private var prompter
    @Environment(\.requestReview) private var requestReview
    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        content
            .task(id: Trigger(request: prompter.pendingRequest, isActive: scenePhase == .active,
                              isHeld: prompter.holds > 0)) {
                guard let request = prompter.pendingRequest, scenePhase == .active, prompter.holds == 0
                else { return }
                try? await Task.sleep(for: Self.delay)
                // Another window may have made the request in the meantime.
                guard !Task.isCancelled, prompter.pendingRequest == request, prompter.holds == 0
                else { return }
                requestReview()
                prompter.didRequestReview()
            }
            .onChange(of: scenePhase) { _, phase in
                if phase != .active { prompter.cancelPendingRequest() }
            }
    }
}
