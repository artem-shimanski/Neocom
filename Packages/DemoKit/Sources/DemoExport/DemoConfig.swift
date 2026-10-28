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
    public var fittings: Fittings
    public var skillQueue: SkillQueue
    public var orders: Orders
    public var industryJobs: [IndustryJob]
    public var contracts: [Contract]
    public var wallet: Wallet
    /// Extra `/universe/names` entries: synthetic parties and the stations the synthetic content uses.
    public var names: [Named]

    public struct Pilot: Codable, Sendable {
        public var name: String
        public var corporationID: Int64
        public var corporationName: String
        /// Replaces every Upwell structure the real pilot used.
        public var homeStationID: Int64
        public var homeStationName: String
        public var homeSolarSystemID: Int64
        /// Replaces the recorded profile fields that identify the real pilot.
        public var birthday: String
        public var securityStatus: Double
        public var gender: String
        public var raceID: Int64
        public var bloodlineID: Int64
        public var walletBalance: Double
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

    /// Which in-game fittings the demo keeps, and under what names.
    public struct Fittings: Codable, Sendable {
        /// Fittings whose name matches one of these (case-insensitive regular expressions) are dropped.
        public var dropPatterns: [String]
        /// Name of the kept fitting per ship type id; fittings of other ships are dropped. The first
        /// remaining fitting of each listed ship is kept.
        public var names: [String: String]
        public var maxCount: Int
    }

    /// The active queue that replaces the recorded one. Entries train back to back from
    /// `startedHoursAgo` before the recording.
    public struct SkillQueue: Codable, Sendable {
        public var startedHoursAgo: Double
        public var entries: [QueuedSkill]
    }

    public struct QueuedSkill: Codable, Sendable {
        public var skillID: Int64
        /// The level the entry finishes.
        public var level: Int
        public var rank: Double
        /// Attribute names as in `/characters/{id}/attributes`.
        public var primary: String
        public var secondary: String
    }

    public struct Orders: Codable, Sendable {
        public var open: [Order]
        /// Added to the recorded history.
        public var history: [Order]
    }

    public struct Order: Codable, Sendable {
        public var orderID: Int64
        public var typeID: Int64
        public var isBuyOrder: Bool
        public var locationID: Int64
        public var regionID: Int64
        public var price: Double
        public var volumeTotal: Int64
        public var volumeRemain: Int64
        public var minVolume: Int64?
        /// ESI order range: `station`, `solarsystem`, `region` or a jump count.
        public var range: String
        /// Days.
        public var duration: Int64
        public var issuedHoursAgo: Double
        /// History only: `expired` or `cancelled`.
        public var state: String?
    }

    public struct IndustryJob: Codable, Sendable {
        public var jobID: Int64
        /// ESI activity id: 1 manufacturing, 3 time research, 4 material research, 5 copying, 8 invention.
        public var activityID: Int64
        /// Item id of the blueprint.
        public var blueprintID: Int64
        public var blueprintTypeID: Int64
        public var productTypeID: Int64?
        public var runs: Int64
        public var licensedRuns: Int64?
        /// `active`, `ready`, `delivered`, …
        public var status: String
        /// An NPC station: facility, blueprint and output location at once.
        public var stationID: Int64
        public var startedHoursAgo: Double
        public var durationHours: Double
        public var cost: Double?
    }

    public struct Contract: Codable, Sendable {
        public var contractID: Int64
        /// `item_exchange`, `courier`, …
        public var type: String
        public var status: String
        public var issuerID: Int64
        public var issuerCorporationID: Int64
        /// 0 for a public contract.
        public var assigneeID: Int64
        public var acceptorID: Int64?
        public var availability: String
        public var title: String
        public var price: Double?
        public var reward: Double?
        public var collateral: Double?
        public var volume: Double
        public var startLocationID: Int64
        public var endLocationID: Int64
        public var daysToComplete: Int64?
        public var issuedHoursAgo: Double
        public var expiresInHours: Double
        public var items: [ContractItem]
    }

    public struct ContractItem: Codable, Sendable {
        public var typeID: Int64
        public var quantity: Int64
        /// `false` for an item the issuer asks for.
        public var isIncluded: Bool
        public var isSingleton: Bool?
    }

    /// The pilot's wallet journal and market transactions. Times are hours before the recording,
    /// at most `DemoExporter.walletWindowHours`; the exporter derives ids, balances and tax entries.
    public struct Wallet: Codable, Sendable {
        /// Share of a sale taken as `transaction_tax`.
        public var salesTax: Double
        /// Share of a bounty taken by the pilot's corporation.
        public var corporationTax: Double
        /// Type names for the entry descriptions, by type id.
        public var types: [String: String]
        public var ratting: [Ratting]
        public var trades: [Trade]
        /// Everything else: fees, job costs, donations, insurance, purchases.
        public var entries: [JournalEntry]
    }

    /// Bounty ticks every 20 minutes from `hoursAgo` on, one per payout.
    public struct Ratting: Codable, Sendable {
        public var hoursAgo: Double
        public var systemID: Int64
        public var systemName: String
        /// Gross bounty of each tick, before the corporation tax.
        public var payouts: [Double]
        /// An `ess_escrow_transfer` a few minutes after the last tick.
        public var essPayout: Double?
    }

    /// A transaction and its `market_transaction` journal entry, for a sale also its `transaction_tax`.
    public struct Trade: Codable, Sendable {
        public var hoursAgo: Double
        public var typeID: Int64
        public var quantity: Int64
        public var unitPrice: Double
        public var isBuy: Bool
        public var clientID: Int64
        public var locationID: Int64
    }

    public struct JournalEntry: Codable, Sendable {
        public var hoursAgo: Double
        /// An ESI `ref_type`.
        public var refType: String
        /// Positive when ISK comes in.
        public var amount: Double
        public var firstPartyID: Int64?
        public var secondPartyID: Int64?
        public var reason: String?
        /// Replaces the description derived from the type.
        public var description: String?
        public var contextID: Int64?
        public var contextIDType: String?
    }

    public struct Named: Codable, Sendable {
        public var id: Int64
        public var name: String
        public var category: String
    }

    public static func decode(from data: Data) throws -> DemoConfig {
        try JSONDecoder().decode(DemoConfig.self, from: data)
    }
}
