import DemoFixtures
import DemoKit
import ESIKit
import Foundation
import OpenAPIRuntime
import os

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
    static let publicClient = Client(esi: ESI(configuration: configuration, errorLimiter: errorLimiter,
                                              additionalMiddlewares: additionalMiddlewares))

    /// A client that signs requests as the character behind `tokenProvider`, refreshing the
    /// token and retrying on `401`.
    static func client(tokenProvider: some ESITokenProvider) -> Client {
        Client(esi: ESI(
            configuration: configuration,
            tokenProvider: tokenProvider,
            errorLimiter: errorLimiter,
            additionalMiddlewares: additionalMiddlewares
        ))
    }

    /// A client for the demo pilot: answers from the bundled demo data, sends public requests
    /// upstream without a token, and rejects every write. Dates are rebased to its creation.
    static func demoClient() -> Client {
        let transport = DemoTransport(
            loadArchive: {
                guard let archive = await DemoPilot.archive() else { throw DemoDataUnavailable() }
                return archive
            },
            writeRejectionMessage: String(localized: "The demo pilot can't change anything in EVE. Sign in with your character to do this."),
            onMiss: logMiss
        )
        return Client(esi: ESI(configuration: configuration, transport: transport, errorLimiter: errorLimiter))
    }

    #if DEBUG
    /// Records every response while the app runs with `-NeocomRecordDemo YES`.
    static let demoRecorder: DemoRecorder? = UserDefaults.standard.bool(forKey: "NeocomRecordDemo") ? DemoRecorder() : nil

    private static var additionalMiddlewares: [any ClientMiddleware] {
        demoRecorder.map { [$0] } ?? []
    }

    private static let demoLog = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Neocom", category: "Demo")

    private static let logMiss: (@Sendable (DemoRequestKey, DemoTransport.Miss) -> Void)? = { key, miss in
        guard miss != .forwarded else { return }
        demoLog.notice("Demo fixture miss (\(String(describing: miss), privacy: .public)): \(key.description, privacy: .public)")
    }
    #else
    private static let additionalMiddlewares: [any ClientMiddleware] = []
    private static let logMiss: (@Sendable (DemoRequestKey, DemoTransport.Miss) -> Void)? = nil
    #endif
}

/// The app ships without readable demo data.
private struct DemoDataUnavailable: Error {}
