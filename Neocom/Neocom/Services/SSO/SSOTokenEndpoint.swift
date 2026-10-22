import Foundation

/// The EVE SSO token endpoint: exchanges an authorization code or a refresh token for a token pair.
///
/// Not actor-isolated: ESIKit's middleware triggers refreshes on arbitrary executors.
nonisolated struct SSOTokenEndpoint: Sendable {
    static let shared = SSOTokenEndpoint()

    var session: URLSession = .shared

    /// Redeems the authorization code returned by the browser flow.
    func redeem(code: String, verifier: String) async throws -> SSOToken {
        try await requestToken([
            "grant_type": "authorization_code",
            "code": code,
            "client_id": SSOConfiguration.clientID,
            "code_verifier": verifier,
        ])
    }

    /// Exchanges a refresh token for a fresh pair. EVE SSO rotates refresh tokens, so the result
    /// replaces the stored one.
    func refresh(_ refreshToken: String) async throws -> SSOToken {
        try await requestToken([
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": SSOConfiguration.clientID,
        ])
    }

    private func requestToken(_ form: [String: String]) async throws -> SSOToken {
        guard SSOConfiguration.isConfigured else { throw SSOError.notConfigured }

        var request = URLRequest(url: SSOConfiguration.tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("login.eveonline.com", forHTTPHeaderField: "Host")
        request.setValue(ESIService.userAgent, forHTTPHeaderField: "User-Agent")

        // Not URLComponents: it leaves "+" unescaped, which form decoding reads as a space and
        // corrupts base64 refresh tokens.
        request.httpBody = form
            .map { "\(Self.formEscape($0.key))=\(Self.formEscape($0.value))" }
            .joined(separator: "&")
            .data(using: .utf8)

        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        guard (200..<300).contains(status) else {
            let payload = try? JSONDecoder().decode(ErrorPayload.self, from: data)
            throw SSOError.server(status: status, message: payload?.errorDescription ?? payload?.error)
        }
        guard let payload = try? JSONDecoder().decode(TokenPayload.self, from: data) else {
            throw SSOError.invalidToken
        }
        return SSOToken(
            accessToken: payload.access_token,
            refreshToken: payload.refresh_token,
            expiresAt: Date().addingTimeInterval(TimeInterval(payload.expires_in))
        )
    }

    /// RFC 3986 unreserved characters only (ASCII; `CharacterSet.alphanumerics` is wider).
    private static let formAllowed = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"
    )

    private static func formEscape(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: formAllowed) ?? value
    }

    private struct TokenPayload: Decodable {
        let access_token: String
        let refresh_token: String
        let expires_in: Int
    }

    private struct ErrorPayload: Decodable {
        let error: String?
        let errorDescription: String?

        enum CodingKeys: String, CodingKey {
            case error
            case errorDescription = "error_description"
        }
    }
}
