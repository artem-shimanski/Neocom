import Foundation

nonisolated enum SSOError: LocalizedError {
    case notConfigured
    case cancelled
    case invalidCallback
    case noPresentationAnchor
    case stateMismatch
    case invalidToken
    case server(status: Int, message: String?)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            String(localized: "EVE SSO is not configured. Put your application's Client ID into `SSOConfiguration.clientID`.")
        case .cancelled:
            String(localized: "Sign-in was cancelled.")
        case .invalidCallback:
            String(localized: "EVE SSO returned an unexpected callback.")
        case .noPresentationAnchor:
            String(localized: "There is no window to present the EVE sign-in page from.")
        case .stateMismatch:
            String(localized: "EVE SSO returned a mismatched state parameter. The sign-in was aborted.")
        case .invalidToken:
            String(localized: "EVE SSO returned a token that could not be read.")
        case let .server(status, message):
            message ?? String(localized: "EVE SSO request failed with status \(status).")
        }
    }
}
