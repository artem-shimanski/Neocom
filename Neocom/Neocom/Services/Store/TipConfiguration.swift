import Foundation

/// The tips the Support screen offers and the App Store listing it links to.
///
/// Order here is the order on screen. Name and price of each tip come from StoreKit.
/// Every tip is a consumable In-App Purchase.
nonisolated enum TipConfiguration {
    struct Tier: Hashable, Sendable {
        let productID: String
        /// SF Symbol of the tile; unused for the More menu tiers, which share its tile.
        let systemImage: String
    }

    static let tiles: [Tier] = [
        Tier(productID: "com.shimanski.neocom.tip.coffee", systemImage: "cup.and.saucer"),
        Tier(productID: "com.shimanski.neocom.tip.lunch", systemImage: "bag"),
        Tier(productID: "com.shimanski.neocom.tip.dinner", systemImage: "fork.knife"),
    ]

    /// The larger tips, offered in the menu of the fourth tile.
    static let more: [Tier] = [
        Tier(productID: "com.shimanski.neocom.tip.bigthanks", systemImage: moreSystemImage),
        Tier(productID: "com.shimanski.neocom.tip.feast", systemImage: moreSystemImage),
        Tier(productID: "com.shimanski.neocom.tip.banquet", systemImage: moreSystemImage),
    ]

    static let moreSystemImage = "gift"

    /// The app's App Store ID (the number in its App Store URL).
    static let appStoreID = "1257353838"

    /// The App Store's review sheet for the app.
    static var reviewURL: URL { URL(string: "https://apps.apple.com/app/id\(appStoreID)?action=write-review")! }

    /// The app's App Store page, for sharing.
    static var shareURL: URL { URL(string: "https://apps.apple.com/app/id\(appStoreID)")! }

    static var allProductIDs: [String] { (tiles + more).map(\.productID) }
}
