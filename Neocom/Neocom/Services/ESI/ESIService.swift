import ESIKit
import Foundation

/// The app's ESI stack, assembled from ESIKit.
///
/// ESIKit handles the server URL, compatibility date, retries, error budget and the
/// `Authorization` header.
nonisolated enum ESIService {
    /// CCP expects a descriptive User-Agent with contact information; requests with a vague
    /// agent are throttled first.
    static let userAgent: String = {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        return "Neocom/\(version) (support@getneocom.com; +https://github.com/artem-shimanski/Neocom)"
    }()

    /// Sent with every request as `X-Compatibility-Date`.
    ///
    /// ESI responds per the schema current on that date, and the generated types match exactly
    /// one schema, so this is always ESIKit's generation date.
    static let compatibilityDate = Components.Parameters.CompatibilityDate(
        rawValue: ESIConfiguration.defaultCompatibilityDate
    )!

    private static let configuration = ESIConfiguration(userAgent: userAgent)

    /// ESI tracks the error budget per application, so all clients share one limiter.
    private static let errorLimiter = ESIErrorLimiter(policy: configuration.errorLimit)

    /// A client for routes that need no character.
    static let publicClient = Client(esi: ESI(configuration: configuration, errorLimiter: errorLimiter))

    /// A client that signs requests as the character behind `tokenProvider`, refreshing the
    /// token and retrying on `401`.
    static func client(tokenProvider: some ESITokenProvider) -> Client {
        Client(esi: ESI(
            configuration: configuration,
            tokenProvider: tokenProvider,
            errorLimiter: errorLimiter
        ))
    }
}
