import SDEKit

/// Character attributes for a pilot or NPC.
public struct CharacterAttributes: Hashable, Sendable, Codable {
    public var charisma: Int
    public var intelligence: Int
    public var memory: Int
    public var perception: Int
    public var willpower: Int

    public init(charisma: Int = 0, intelligence: Int = 0, memory: Int = 0,
                perception: Int = 0, willpower: Int = 0) {
        self.charisma = charisma
        self.intelligence = intelligence
        self.memory = memory
        self.perception = perception
        self.willpower = willpower
    }

    public subscript(attribute: CharacterAttribute) -> Int {
        get {
            switch attribute {
            case .charisma:
                return charisma
            case .intelligence:
                return intelligence
            case .memory:
                return memory
            case .perception:
                return perception
            case .willpower:
                return willpower
            }
        }
        set {
            switch attribute {
            case .charisma:
                charisma = newValue
            case .intelligence:
                intelligence = newValue
            case .memory:
                memory = newValue
            case .perception:
                perception = newValue
            case .willpower:
                willpower = newValue
            }
        }
    }

    public static func + (lhs: Self, rhs: Self) -> Self {
        Self(
            charisma: lhs.charisma + rhs.charisma,
            intelligence: lhs.intelligence + rhs.intelligence,
            memory: lhs.memory + rhs.memory,
            perception: lhs.perception + rhs.perception,
            willpower: lhs.willpower + rhs.willpower
        )
    }

    public static func - (lhs: Self, rhs: Self) -> Self {
        Self(
            charisma: lhs.charisma - rhs.charisma,
            intelligence: lhs.intelligence - rhs.intelligence,
            memory: lhs.memory - rhs.memory,
            perception: lhs.perception - rhs.perception,
            willpower: lhs.willpower - rhs.willpower
        )
    }

    public static let zero = Self()

    /// Placeholder shown before ESI returns the actual attributes.
    public static let starting = Self(charisma: 19, intelligence: 20, memory: 20,
                                      perception: 20, willpower: 20)
}
