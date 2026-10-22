import ESIKit
import Foundation

/// An authenticated ESI client for one character and the token state behind it.
///
/// `ESITokenStore` caches the access token and coalesces concurrent refreshes; this type
/// redeems the refresh token and reports each rotated pair for persistence.
@MainActor
final class AccountSession {
    /// Signs every request as this character; on a `401` refreshes the token and retries once.
    let client: Client

    /// - Parameters:
    ///   - account: the character, with the token pair last read from the keychain.
    ///   - endpoint: the EVE SSO token endpoint used to refresh.
    ///   - didRefresh: called with every rotated pair, which must be persisted: EVE SSO
    ///     invalidates the previous refresh token.
    init(
        account: Account,
        endpoint: SSOTokenEndpoint = .shared,
        didRefresh: @escaping @Sendable (SSOToken) async -> Void
    ) {
        let rotation = RefreshTokenRotation(token: account.token, endpoint: endpoint, didRefresh: didRefresh)
        let tokens = ESITokenStore(
            initialToken: ESIAccessToken(value: account.token.accessToken, expiresAt: account.token.expiresAt)
        ) {
            try await rotation.redeem()
        }
        client = ESIService.client(tokenProvider: tokens)
    }
}

/// Holds one character's refresh token, which changes on every use; the actor serializes
/// redemptions.
private actor RefreshTokenRotation {
    private var refreshToken: String
    private let endpoint: SSOTokenEndpoint
    private let didRefresh: @Sendable (SSOToken) async -> Void

    init(token: SSOToken, endpoint: SSOTokenEndpoint, didRefresh: @escaping @Sendable (SSOToken) async -> Void) {
        refreshToken = token.refreshToken
        self.endpoint = endpoint
        self.didRefresh = didRefresh
    }

    func redeem() async throws -> ESIAccessToken {
        let token = try await endpoint.refresh(refreshToken)
        refreshToken = token.refreshToken
        await didRefresh(token)
        return ESIAccessToken(value: token.accessToken, expiresAt: token.expiresAt)
    }
}
