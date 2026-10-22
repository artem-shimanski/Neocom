import Foundation

/// OAuth 2.0 token pair issued by EVE SSO, as it is persisted in the keychain.
///
/// `expiresAt` is passed to ESIKit as an `ESIAccessToken` (see `AccountSession`); `ESITokenStore`
/// decides when the token is stale.
nonisolated struct SSOToken: Codable, Hashable, Sendable {
    var accessToken: String
    var refreshToken: String
    var expiresAt: Date
}

/// Claims carried by the SSO access token (a JWT).
nonisolated struct SSOClaims: Hashable, Sendable {
    var characterID: Int64
    var characterName: String
    /// Changes when the character is transferred to another account; a mismatch means the stored
    /// token must be dropped.
    var ownerHash: String
    var scopes: [String]

    /// Decodes the payload of a JWT.
    ///
    /// - Note: the signature is not verified; tokens are received directly from
    ///   `login.eveonline.com` over TLS.
    init(accessToken: String) throws {
        let parts = accessToken.split(separator: ".")
        guard parts.count == 3,
              let payload = Data(base64URLEncoded: String(parts[1])),
              let json = try JSONSerialization.jsonObject(with: payload) as? [String: Any],
              let subject = json["sub"] as? String,
              let characterID = Int64(subject.split(separator: ":").last.map(String.init) ?? ""),
              let name = json["name"] as? String
        else { throw SSOError.invalidToken }

        self.characterID = characterID
        characterName = name
        ownerHash = json["owner"] as? String ?? ""
        switch json["scp"] {
        case let list as [String]: scopes = list
        case let single as String: scopes = [single]
        default: scopes = []
        }
    }
}
