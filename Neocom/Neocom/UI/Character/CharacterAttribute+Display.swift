import SDEKit
import SwiftUI

extension CharacterAttribute {
    /// The game's order, which is not the alphabetical order `allCases` would give.
    static let displayOrder: [CharacterAttribute] = [.perception, .memory, .willpower, .intelligence, .charisma]

    var title: LocalizedStringKey {
        switch self {
        case .perception: "Perception"
        case .memory: "Memory"
        case .willpower: "Willpower"
        case .intelligence: "Intelligence"
        case .charisma: "Charisma"
        }
    }
}
