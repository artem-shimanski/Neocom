import AuthenticationServices
import CryptoKit
import Foundation
import UIKit

/// Drives the EVE SSO authorization-code flow with PKCE, the only flow allowed for native clients.
///
/// Covers the browser part only; attaching the token, refreshing it and replaying a `401`
/// belong to ESIKit.
@MainActor
final class SSOAuthenticator: NSObject {
    static let shared = SSOAuthenticator()

    private let endpoint: SSOTokenEndpoint
    private var session: ASWebAuthenticationSession?

    /// The window the login sheet is presented from.
    private var anchor: ASPresentationAnchor?

    init(endpoint: SSOTokenEndpoint = .shared) {
        self.endpoint = endpoint
    }

    /// Presents the EVE login page and exchanges the returned code for a token pair.
    func signIn() async throws -> (claims: SSOClaims, token: SSOToken) {
        guard SSOConfiguration.isConfigured else { throw SSOError.notConfigured }

        let pkce = PKCE()
        let state = UUID().uuidString

        var components = URLComponents(url: SSOConfiguration.authorizeURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: SSOConfiguration.callbackURL.absoluteString),
            URLQueryItem(name: "client_id", value: SSOConfiguration.clientID),
            URLQueryItem(name: "scope", value: SSOConfiguration.scopes.joined(separator: " ")),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "code_challenge", value: pkce.challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
        ]

        let callback = try await authenticate(url: components.url!)
        guard let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems else {
            throw SSOError.invalidCallback
        }
        guard items.first(where: { $0.name == "state" })?.value == state else {
            throw SSOError.stateMismatch
        }
        guard let code = items.first(where: { $0.name == "code" })?.value else {
            throw SSOError.invalidCallback
        }

        let token = try await endpoint.redeem(code: code, verifier: pkce.verifier)
        return (try SSOClaims(accessToken: token.accessToken), token)
    }

    // MARK: - Web authentication

    private func authenticate(url: URL) async throws -> URL {
        // Resolved before the session starts: the presentation protocol cannot report a missing window.
        guard let anchor = Self.presentationWindow() else { throw SSOError.noPresentationAnchor }
        self.anchor = anchor

        return try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: url,
                callbackURLScheme: SSOConfiguration.callbackURL.scheme
            ) { callback, error in
                if let callback {
                    continuation.resume(returning: callback)
                } else if let error = error as? ASWebAuthenticationSessionError,
                          error.code == .canceledLogin {
                    continuation.resume(throwing: SSOError.cancelled)
                } else {
                    continuation.resume(throwing: error ?? SSOError.invalidCallback)
                }
            }
            session.presentationContextProvider = self
            // A shared cookie jar persists the user's session, allowing for multiple characters to
            // be added without re-authenticating.
            session.prefersEphemeralWebBrowserSession = false

            self.session = session
            guard session.start() else {
                continuation.resume(throwing: SSOError.invalidCallback)
                return
            }
        }
    }

    /// The key window of the foreground scene, so that the sheet appears over the window sign-in
    /// was started from when there are several scenes.
    private static func presentationWindow() -> UIWindow? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        guard let scene else { return nil }
        return scene.windows.first(where: \.isKeyWindow) ?? scene.windows.first
    }

    /// Proof Key for Code Exchange (RFC 7636).
    private struct PKCE {
        let verifier: String
        var challenge: String { Data(SHA256.hash(data: Data(verifier.utf8))).base64URLEncodedString() }

        init() {
            var bytes = [UInt8](repeating: 0, count: 32)
            _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
            verifier = Data(bytes).base64URLEncodedString()
        }
    }
}

extension SSOAuthenticator: ASWebAuthenticationPresentationContextProviding {
    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        // Only the session started by `authenticate(url:)` asks, after the anchor is set.
        MainActor.assumeIsolated { anchor! }
    }
}
