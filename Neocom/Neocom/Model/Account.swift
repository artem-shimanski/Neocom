import Foundation

/// An authorized EVE character.
struct Account: Identifiable, Hashable, Codable, Sendable {
    var characterID: Int64
    var characterName: String
    var ownerHash: String
    var scopes: [String]
    var token: SSOToken

    var id: Int64 { characterID }

    /// Whether EVE SSO granted `scope` at the last sign-in.
    func hasScope(_ scope: String) -> Bool {
        scopes.contains(scope)
    }

    var portraitURL: URL { EVEImage.portrait(characterID: characterID) }

    init(claims: SSOClaims, token: SSOToken) {
        characterID = claims.characterID
        characterName = claims.characterName
        ownerHash = claims.ownerHash
        scopes = claims.scopes
        self.token = token
    }
}
