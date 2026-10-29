import DogmaKit
import SDEKit

/// Fighter squadron data the engine does not provide.
///
/// The engine assigns a fighter to a squadron but does not enforce the hull's limits: a slot
/// count per squadron type limits squadrons in the fit, and `fighterTubes` limits squadrons
/// launched at once.
nonisolated extension Entity.Drone.Squadron {
    /// Every fighter squadron type, in editor section order: ship squadrons first, then
    /// structure (standup) ones.
    static let fighterSquadrons: [Entity.Drone.Squadron] = [
        .light, .heavy, .support, .standupLight, .standupHeavy, .standupSupport,
    ]

    /// The type attribute that marks a fighter as belonging to this squadron. `nil` for `.none`.
    var membershipAttribute: AttributeID? {
        switch self {
        case .none: nil
        case .light: .fighterSquadronIsLight
        case .heavy: .fighterSquadronIsHeavy
        case .support: .fighterSquadronIsSupport
        case .standupLight: .fighterSquadronIsStandupLight
        case .standupHeavy: .fighterSquadronIsStandupHeavy
        case .standupSupport: .fighterSquadronIsStandupSupport
        }
    }

    /// The SDE item kind: `.fighter` for ship fighters, `.structureFighter` for structure
    /// fighters, `.drone` for ordinary drones.
    var itemKind: DogmaItemKind {
        switch self {
        case .none: .drone
        case .light, .heavy, .support: .fighter
        case .standupLight, .standupHeavy, .standupSupport: .structureFighter
        }
    }
}
