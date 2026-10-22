import Foundation

/// Registration data of the app's EVE SSO application, and the endpoints it talks to.
nonisolated enum SSOConfiguration {
    /// Client ID of the application registered at https://developers.eveonline.com.
    /// Native apps use PKCE, so there is no client secret.
    static let clientID = "c2cc974798d4485d966fba773a8f7ef8"

    static let callbackURL = URL(string: "eveauth-neocom://sso")!

    /// Scopes requested at sign-in. Changing the list requires characters to be re-authorized.
    static let scopes = ["publicData","esi-calendar.respond_calendar_events.v1","esi-calendar.read_calendar_events.v1","esi-location.read_location.v1","esi-location.read_ship_type.v1","esi-mail.organize_mail.v1","esi-mail.read_mail.v1","esi-mail.send_mail.v1","esi-skills.read_skills.v1","esi-skills.read_skillqueue.v1","esi-wallet.read_character_wallet.v1","esi-search.search_structures.v1","esi-clones.read_clones.v1","esi-clones.read_implants.v1","esi-characters.read_contacts.v1","esi-universe.read_structures.v1","esi-killmails.read_killmails.v1","esi-corporations.read_corporation_membership.v1","esi-assets.read_assets.v1","esi-planets.manage_planets.v1","esi-fleets.read_fleet.v1","esi-fleets.write_fleet.v1","esi-ui.open_window.v1","esi-ui.write_waypoint.v1","esi-characters.write_contacts.v1","esi-fittings.read_fittings.v1","esi-fittings.write_fittings.v1","esi-markets.structure_markets.v1","esi-markets.read_character_orders.v1","esi-industry.read_character_jobs.v1","esi-contracts.read_character_contracts.v1"]

    /// Scopes a section checks before requesting its routes. An account signed in before a scope
    /// was added lacks it until re-authorized.
    enum Scope {
        static let marketOrders = "esi-markets.read_character_orders.v1"
        static let industryJobs = "esi-industry.read_character_jobs.v1"
        static let contracts = "esi-contracts.read_character_contracts.v1"
        static let mailRead = "esi-mail.read_mail.v1"
        static let mailOrganize = "esi-mail.organize_mail.v1"
        static let mailSend = "esi-mail.send_mail.v1"
        static let contactsRead = "esi-characters.read_contacts.v1"
        static let search = "esi-search.search_structures.v1"
        static let killmails = "esi-killmails.read_killmails.v1"
    }

    static let authorizeURL = URL(string: "https://login.eveonline.com/v2/oauth/authorize")!
    static let tokenURL = URL(string: "https://login.eveonline.com/v2/oauth/token")!

    static var isConfigured: Bool { !clientID.isEmpty }
}
