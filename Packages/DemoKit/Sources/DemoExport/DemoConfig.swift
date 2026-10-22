import DemoFixtures
import Foundation

/// The demo identity and the synthetic content the exporter adds (`DemoConfig.json`).
public struct DemoConfig: Codable, Sendable {
    public var pilot: Pilot
    /// Upper bound of the encoded archive, in bytes.
    public var sizeBudget: Int
    /// Names given to third parties the exporter replaces (contract partners and the like).
    public var syntheticCharacterNames: [String]
    public var syntheticCorporationNames: [String]
    public var mail: Mail
    public var contacts: [Contact]
    public var plan: [DemoArchive.PlanItem]

    public struct Pilot: Codable, Sendable {
        public var name: String
        public var corporationID: Int64
        public var corporationName: String
        /// Replaces every Upwell structure the real pilot used.
        public var homeStationID: Int64
        public var homeStationName: String
        public var homeSolarSystemID: Int64
    }

    public struct Mail: Codable, Sendable {
        public var labels: [Label]
        public var mailingLists: [MailingList]
        public var senders: [Sender]
        public var messages: [Message]
    }

    public struct Label: Codable, Sendable {
        public var labelID: Int64
        public var name: String
        /// One of ESI's label colours, e.g. `#ffffff`.
        public var color: String
    }

    public struct MailingList: Codable, Sendable {
        public var mailingListID: Int64
        public var name: String
    }

    public struct Sender: Codable, Sendable {
        public var id: Int64
        public var name: String
    }

    public struct Message: Codable, Sendable {
        public var mailID: Int64
        public var from: Int64
        public var subject: String
        public var body: String
        /// How long before the recording the mail arrived.
        public var hoursAgo: Double
        public var labels: [Int64]
        public var isRead: Bool
        /// Defaults to the demo pilot.
        public var recipients: [Recipient]?
    }

    public struct Recipient: Codable, Sendable {
        public var id: Int64
        /// `character`, `corporation`, `alliance` or `mailing_list`.
        public var type: String
    }

    public struct Contact: Codable, Sendable {
        public var id: Int64
        public var standing: Double
    }

    public static func decode(from data: Data) throws -> DemoConfig {
        try JSONDecoder().decode(DemoConfig.self, from: data)
    }
}
