import ESIKit
import Foundation
import Observation

/// The corporation roles of the viewing character, as stored in `ESICache`.
nonisolated struct ESICorporationRoles: Codable, Sendable, Hashable {
    var roles: Set<String>

    /// Whether the character holds `role`; a Director holds all of them.
    func has(_ role: String) -> Bool {
        roles.contains(role) || roles.contains(Self.director)
    }

    static let director = "Director"
    static let accountant = "Accountant"
    static let juniorAccountant = "Junior_Accountant"
    static let trader = "Trader"
    static let factoryManager = "Factory_Manager"
}

/// The names a corporation gave its hangar and wallet divisions (1...7).
nonisolated struct ESICorporationDivisions: Codable, Sendable, Hashable {
    var hangar: [Int: String]
    var wallet: [Int: String]

    func hangarName(_ number: Int) -> String {
        Self.hangarName(number, in: hangar)
    }

    func walletName(_ number: Int) -> String {
        Self.walletName(number, in: wallet)
    }

    static func hangarName(_ number: Int, in names: [Int: String]) -> String {
        names[number] ?? String(localized: "Division \(number)")
    }

    static func walletName(_ number: Int, in names: [Int: String]) -> String {
        names[number] ?? (number == 1 ? String(localized: "Master Wallet") : String(localized: "Division \(number)"))
    }
}

/// Which corporation sections the viewing character may read.
struct CorporationAccess: Sendable, Hashable {
    var assets = false
    var orders = false
    var industry = false
    var contracts = false
    var wallets = false

    var isEmpty: Bool { !(assets || orders || industry || contracts || wallets) }
}

/// The viewing character's corporation: their roles in it and its division names.
///
/// The only owner of `/characters/{id}/roles` and `/corporations/{id}/divisions`. Cached per
/// viewing character, with the corporation id in the kind. Nothing here reaches widgets; the
/// corporation notifications read the roles to pick a viewer.
@Observable
@MainActor
final class CorporationSheet {
    private static let ttl: TimeInterval = 3600

    /// The viewer.
    let characterID: Int64
    let corporationID: Int64
    private let scopes: Set<String>

    private(set) var roles: ESISnapshot<ESICorporationRoles>
    private(set) var divisions: ESISnapshot<ESICorporationDivisions>

    init(characterID: Int64, corporationID: Int64, client: Client, hasScope: (String) -> Bool) {
        self.characterID = characterID
        self.corporationID = corporationID
        scopes = Set(SSOConfiguration.Scope.corporation.filter(hasScope))
        roles = ESISnapshot(kind: Self.rolesCacheKind(corporationID), characterID: characterID, ttl: Self.ttl, cache: ESICache()) {
            let payload = try await client.characterRoles(characterID: characterID)
            return ESICorporationRoles(roles: Set((payload.roles ?? []).map(\.rawValue)))
        }
        divisions = ESISnapshot(kind: "corp-\(corporationID)-divisions", characterID: characterID, ttl: Self.ttl, cache: ESICache()) {
            let payload = try await client.corporationDivisions(corporationID: corporationID)
            return ESICorporationDivisions(hangar: Self.names(payload.hangar?.map { ($0.division, $0.name) }),
                                           wallet: Self.names(payload.wallet?.map { ($0.division, $0.name) }))
        }
        // The roles decide who may see the corporation's jobs.
        roles.didUpdate = { _ in
            NotificationPlanner.shared.reschedule(.corporationIndustry, corporationID: corporationID)
        }
    }

    nonisolated private static func names(_ entries: [(Int64?, String?)]?) -> [Int: String] {
        var names: [Int: String] = [:]
        for case let (division?, name?) in entries ?? [] where !name.isEmpty {
            names[Int(clamping: division)] = name
        }
        return names
    }

    nonisolated static func rolesCacheKind(_ corporationID: Int64) -> String { "corp-\(corporationID)-roles" }

    nonisolated static func isPlayerCorporation(_ id: Int64) -> Bool {
        !(1_000_000..<2_000_000).contains(id)
    }

    func hasScope(_ scope: String) -> Bool { scopes.contains(scope) }

    /// Whether the account was granted every corporation scope.
    var hasAllScopes: Bool { scopes.count == SSOConfiguration.Scope.corporation.count }

    var isDirector: Bool { roles.value?.has(ESICorporationRoles.director) ?? false }

    /// Section availability by scope and role; `false` until the roles are known, except for
    /// contracts, which need no role.
    var access: CorporationAccess {
        Self.access(roles: roles.value, hasScope: hasScope)
    }

    /// Section availability for `roles` (`nil` while unknown) and the account's scopes.
    nonisolated static func access(roles: ESICorporationRoles?, hasScope: (String) -> Bool) -> CorporationAccess {
        func allowed(_ scope: String, _ role: String...) -> Bool {
            hasScope(scope) && (roles.map { value in role.contains { value.has($0) } } ?? false)
        }
        return CorporationAccess(
            assets: allowed(SSOConfiguration.Scope.corporationAssets, ESICorporationRoles.director),
            orders: allowed(SSOConfiguration.Scope.corporationOrders, ESICorporationRoles.accountant, ESICorporationRoles.trader),
            industry: allowed(SSOConfiguration.Scope.corporationIndustryJobs, ESICorporationRoles.factoryManager),
            contracts: hasScope(SSOConfiguration.Scope.corporationContracts),
            wallets: allowed(SSOConfiguration.Scope.corporationWallets, ESICorporationRoles.accountant,
                             ESICorporationRoles.juniorAccountant)
        )
    }

    /// Hangar division name; the default one unless the divisions are known (Director only).
    func hangarName(_ number: Int) -> String {
        ESICorporationDivisions.hangarName(number, in: divisions.value?.hangar ?? [:])
    }

    func walletName(_ number: Int) -> String {
        ESICorporationDivisions.walletName(number, in: divisions.value?.wallet ?? [:])
    }

    /// Refreshes the roles if missing or past the TTL.
    func ensureFresh() async {
        guard hasScope(SSOConfiguration.Scope.corporationRoles) else { return }
        await roles.ensureFresh()
    }

    func refresh() async {
        guard hasScope(SSOConfiguration.Scope.corporationRoles) else { return }
        await roles.refresh()
    }

    /// Refreshes the division names; fetched only for a Director, others keep the defaults.
    func ensureDivisionsFresh() async {
        guard hasScope(SSOConfiguration.Scope.corporationDivisions) else { return }
        await roles.ensureFresh()
        guard isDirector else { return }
        await divisions.ensureFresh()
    }

    /// Stops all disk writes; called by `AccountStore` when it drops the sheet.
    func invalidate() {
        roles.invalidate()
        divisions.invalidate()
    }
}
