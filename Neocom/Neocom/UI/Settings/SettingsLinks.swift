import Foundation

/// Every page outside the app that Settings and Legal link to, and the version they print.
nonisolated enum SettingsLinks {
    /// The App Store's review sheet, the same one the Support screen opens.
    static var review: URL { TipConfiguration.reviewURL }

    static let sourceCode = URL(string: "https://github.com/artem-shimanski/Neocom")!

    static let privacyPolicy = URL(string: "https://getneocom.com/privacy.html")!

    /// What Neocom takes from CCP, each with the public page that describes it.
    static let eveOnline = URL(string: "https://www.eveonline.com")!
    static let esi = URL(string: "https://developers.eveonline.com/docs/services/esi/overview/")!
    static let sso = URL(string: "https://developers.eveonline.com/docs/services/sso/")!
    static let staticData = URL(string: "https://developers.eveonline.com/resource")!
    static let imageServer = URL(string: "https://images.evetech.net")!

    static let zKillboard = URL(string: "https://zkillboard.com")!

    /// `1.0 (1)`: the marketing version and the build, from the bundle.
    static var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String ?? "—"
        return "\(short) (\(build))"
    }
}
