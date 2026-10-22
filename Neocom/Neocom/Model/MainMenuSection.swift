import SwiftUI

/// Top-level sections of the app. A section with a `group` appears as a main menu tile; its screen
/// is wired in `SectionDetailView`. Sections without a group are placed by the menu separately.
enum MainMenuSection: String, CaseIterable, Identifiable, Hashable {
    case characterSheet
    case skills
    case trainingQueue
    case certificates
    case assets
    case mail
    case killmails
    case marketOrders
    case industry
    case contracts
    case planetaryInteraction
    case database
    case fittingTool
    case zKillboard
    /// The tip jar, shown as a full-width row under the tiles.
    case support
    /// Shown as a toolbar button on the home screen.
    case settings

    var id: Self { self }

    var title: LocalizedStringKey {
        switch self {
        case .characterSheet: "Character Sheet"
        case .skills: "Skills"
        case .trainingQueue: "Training Queue"
        case .certificates: "Certificates"
        case .planetaryInteraction: "Planetary Interaction"
        case .assets: "Assets"
        case .mail: "Mail"
        case .killmails: "Killmails"
        case .marketOrders: "Market Orders"
        case .industry: "Industry"
        case .contracts: "Contracts"
        case .database: "Database"
        case .fittingTool: "Fitting Tool"
        case .zKillboard: "zKillboard"
        case .support: "Support Neocom"
        case .settings: "Settings"
        }
    }

    var systemImage: String {
        switch self {
        case .characterSheet: "person.crop.circle"
        case .skills: "book.closed"
        case .trainingQueue: "clock.arrow.trianglehead.counterclockwise.rotate.90"
        case .certificates: "rosette"
        case .planetaryInteraction: "globe.europe.africa"
        case .assets: "shippingbox"
        case .mail: "envelope"
        case .killmails: "scope"
        case .marketOrders: "tag"
        case .industry: "hammer"
        case .contracts: "doc.text"
        case .database: "square.stack.3d.up"
        case .fittingTool: "wrench.and.screwdriver"
        case .zKillboard: "magnifyingglass"
        case .support: "heart"
        case .settings: "gearshape"
        }
    }

    var tint: Color {
        switch self {
        case .characterSheet: .blue
        case .skills: .cyan
        case .trainingQueue: .indigo
        case .certificates: .teal
        case .planetaryInteraction: .green
        case .assets: .brown
        case .mail: .gray
        case .killmails: .red
        case .marketOrders: .mint
        case .industry: .yellow
        case .contracts: .purple
        case .database: .orange
        case .fittingTool: .pink
        case .zKillboard: .red
        case .support: .red
        case .settings: .gray
        }
    }

    /// Whether the section needs an authorized character.
    var requiresAccount: Bool {
        switch self {
        case .characterSheet, .skills, .trainingQueue, .certificates, .planetaryInteraction, .assets, .mail: true
        case .killmails: true
        case .marketOrders, .industry, .contracts: true
        case .database, .fittingTool, .support, .settings: false
        case .zKillboard: false
        }
    }

    /// The tile group of the section; `nil` if it is not a tile.
    var group: Group? {
        switch self {
        case .characterSheet, .skills, .trainingQueue, .certificates, .assets, .mail, .killmails: .character
        case .marketOrders, .industry, .contracts, .planetaryInteraction: .business
        case .database, .fittingTool: .tools
        case .zKillboard: .tools
        case .support, .settings: nil
        }
    }

    enum Group: String, CaseIterable, Identifiable {
        case character
        case business
        case tools

        var id: Self { self }

        var title: LocalizedStringKey {
            switch self {
            case .character: "Character"
            case .business: "Business"
            case .tools: "Tools"
            }
        }

        var sections: [MainMenuSection] {
            MainMenuSection.allCases.filter { $0.group == self }
        }
    }
}
