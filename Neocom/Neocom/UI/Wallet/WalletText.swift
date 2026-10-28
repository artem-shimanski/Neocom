import BusinessKit
import SwiftUI

/// How the Wallet screens name categories and ref types and write ISK.
enum WalletText {
    /// `+6.88M`, `−2.00M`: compact and always signed, with a true minus.
    static func signed(_ value: Double) -> String {
        let figure = ISK.compact(abs(value))
        if abs(value) < 0.005 { return figure }
        return "\(value < 0 ? "−" : "+")\(figure)"
    }

    /// `+9 250 000.00 ISK`: in full, always signed.
    static func signedFull(_ value: Double) -> String {
        let figure = abs(value).formatted(.number.precision(.fractionLength(2)))
        if abs(value) < 0.005 { return "\(figure) ISK" }
        return "\(value < 0 ? "−" : "+")\(figure) ISK"
    }

    /// Income in `ok`, the rest in the ordinary ink.
    static func color(_ value: Double) -> Color {
        value > 0 ? .hudOk : .hudInk
    }

    static func title(_ category: WalletCategory) -> String {
        switch category {
        case .bounties: String(localized: "Bounties")
        case .missions: String(localized: "Missions")
        case .market: String(localized: "Market")
        case .taxesAndFees: String(localized: "Taxes & Fees")
        case .industry: String(localized: "Industry")
        case .planetary: String(localized: "Planetary")
        case .contracts: String(localized: "Contracts")
        case .transfers: String(localized: "Transfers")
        case .corporateTaxes: String(localized: "Member Taxes")
        case .officeAndUpkeep: String(localized: "Office & Upkeep")
        case .other: String(localized: "Other")
        }
    }

    /// The category of one side of the summary: the market splits into sales and purchases.
    static func title(_ category: WalletCategory, sign: WalletSign) -> String {
        guard category == .market else { return title(category) }
        return sign == .income ? String(localized: "Market Sales") : String(localized: "Market Purchases")
    }

    static func systemImage(_ category: WalletCategory) -> String {
        switch category {
        case .bounties: "scope"
        case .missions: "flag"
        case .market: "tag"
        case .taxesAndFees: "percent"
        case .industry: "hammer"
        case .planetary: "globe.europe.africa"
        case .contracts: "doc.text"
        case .transfers: "arrow.left.arrow.right"
        case .corporateTaxes: "checkmark.shield"
        case .officeAndUpkeep: "building.2"
        case .other: "ellipsis.circle"
        }
    }

    /// What a ref type is called; an unknown one is its raw name made readable.
    static func title(refType: String) -> String {
        switch refType {
        case "bounty_prizes", "bounty_prize": String(localized: "Bounty Prizes")
        case "ess_escrow_transfer": String(localized: "ESS Payout")
        case "agent_mission_reward", "mission_reward": String(localized: "Mission Reward")
        case "agent_mission_time_bonus_reward": String(localized: "Mission Time Bonus")
        case "market_transaction": String(localized: "Market Transaction")
        case "market_escrow": String(localized: "Market Escrow")
        case "transaction_tax": String(localized: "Sales Tax")
        case "brokers_fee": String(localized: "Broker’s Fee")
        case "market_provider_tax": String(localized: "Market Provider Tax")
        case "industry_job_tax": String(localized: "Industry Job Cost")
        case "manufacturing": String(localized: "Manufacturing")
        case "reprocessing_tax": String(localized: "Reprocessing Tax")
        case "planetary_export_tax": String(localized: "Planetary Export Tax")
        case "planetary_import_tax": String(localized: "Planetary Import Tax")
        case "planetary_construction": String(localized: "Planetary Construction")
        case "contract_price": String(localized: "Contract Price")
        case "contract_reward": String(localized: "Contract Reward")
        case "contract_collateral": String(localized: "Contract Collateral")
        case "contract_brokers_fee", "contract_brokers_fee_corp": String(localized: "Contract Broker’s Fee")
        case "contract_sales_tax": String(localized: "Contract Sales Tax")
        case "player_donation": String(localized: "Player Donation")
        case "player_trading": String(localized: "Player Trading")
        case "corporation_account_withdrawal": String(localized: "Corporation Withdrawal")
        case "corporation_payment": String(localized: "Corporation Payment")
        case "corporation_dividend_payment": String(localized: "Dividend Payment")
        case "insurance": String(localized: "Insurance")
        case "jump_clone_activation_fee": String(localized: "Jump Clone Fee")
        case "jump_clone_installation_fee": String(localized: "Jump Clone Installation")
        case "skill_purchase": String(localized: "Skill Purchase")
        case "lp_store": String(localized: "LP Store")
        case "office_rental_fee": String(localized: "Office Rental Fee")
        case "bounty_prize_corporation_tax": String(localized: "Bounty Tax")
        case "agent_mission_reward_corporation_tax": String(localized: "Mission Tax")
        case "agent_mission_time_bonus_reward_corporation_tax": String(localized: "Mission Time Bonus Tax")
        case "daily_goal_payouts": String(localized: "Daily Goal Payout")
        case "daily_goal_payouts_tax": String(localized: "Daily Goal Tax")
        case "corporate_reward_payout": String(localized: "Corporate Reward")
        case "corporate_reward_tax": String(localized: "Corporate Reward Tax")
        case "docking_fee": String(localized: "Docking Fee")
        case "war_fee": String(localized: "War Fee")
        default:
            refType.split(separator: "_").enumerated()
                .map { $0.offset == 0 ? $0.element.capitalized : $0.element.lowercased() }
                .joined(separator: " ")
        }
    }

    static func period(_ period: WalletPeriod) -> String {
        switch period {
        case .day: String(localized: "24H", comment: "Wallet period: the last 24 hours")
        case .week: String(localized: "7D", comment: "Wallet period: the last 7 days")
        case .month: String(localized: "30D", comment: "Wallet period: the last 30 days")
        }
    }

    /// A UTC day for a section header: `2026.10.28 · Today`.
    static func day(_ date: Date, now: Date) -> String {
        let calendar = utc
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date),
                                           to: calendar.startOfDay(for: now)).day ?? 0
        switch days {
        case 0: return "\(EVETime.date(date)) · \(String(localized: "Today"))"
        case 1: return "\(EVETime.date(date)) · \(String(localized: "Yesterday"))"
        default: return EVETime.date(date)
        }
    }

    /// `×1 250 @ 9 250 000`.
    static func trade(quantity: Int64, unitPrice: Double) -> String {
        "×\(MarketFormat.quantity(quantity)) @ \(ISK.priceFigure(unitPrice))"
    }

    static let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        return calendar
    }()
}
