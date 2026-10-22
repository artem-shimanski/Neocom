import DogmaKit
import Foundation

/// One fit as the old Neocom stored it: the JSON of its `Ship` struct, kept in
/// `ZLOADOUTDATA.ZDATA`. Read-only, and only as far as the import needs it.
///
/// Lenient on purpose: everything but the type IDs may be missing, and `modules` is accepted
/// both as the flat `[slotKey, [Module], slotKey, [Module], …]` array the old encoder wrote
/// and as an object keyed by slot.
public struct LegacyShip: Decodable, Sendable, Equatable {
    public var typeID: Int
    public var name: String?
    /// In the order the old document listed them.
    public var racks: [Rack]
    public var drones: [Drone]
    public var cargo: [Item]
    public var implants: [Int]
    public var boosters: [Int]

    public struct Rack: Sendable, Equatable {
        public var slot: Slot
        public var modules: [Module]
    }

    /// dgmpp's slot enum, by its raw value.
    public enum Slot: Sendable, Equatable {
        case none, hi, med, low, rig, subsystem, mode, service, starbaseStructure
        case unknown(String)

        /// Accepts the old encoder's `Slot(stringValue: "hi", intValue: 1)`, a bare `"hi"`,
        /// or a bare number.
        init(key: String) {
            if let name = Self.capture(#"stringValue:\s*"([^"]*)""#, in: key), let slot = Self(name: name) {
                self = slot
            } else if let raw = Self.capture(#"intValue:\s*(-?\d+)"#, in: key).flatMap(Int.init),
                      let slot = Self(raw: raw) {
                self = slot
            } else if let slot = Self(name: key) ?? Int(key).flatMap(Self.init(raw:)) {
                self = slot
            } else {
                self = .unknown(key)
            }
        }

        init?(name: String) {
            switch name {
            case "none": self = .none
            case "hi": self = .hi
            case "med": self = .med
            case "low": self = .low
            case "rig": self = .rig
            case "subsystem": self = .subsystem
            case "mode": self = .mode
            case "service": self = .service
            case "starbaseStructure": self = .starbaseStructure
            default: return nil
            }
        }

        init?(raw: Int) {
            let all: [Slot] = [.none, .hi, .med, .low, .rig, .subsystem, .mode, .service, .starbaseStructure]
            guard all.indices.contains(raw) else { return nil }
            self = all[raw]
        }

        private static func capture(_ pattern: String, in string: String) -> String? {
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: string, range: NSRange(string.startIndex..., in: string)),
                  let range = Range(match.range(at: 1), in: string) else { return nil }
            return String(string[range])
        }
    }

    public struct Module: Decodable, Sendable, Equatable {
        public var typeID: Int
        public var count: Int
        /// `"active"`, `"online"`, `"offline"`, `"overloaded"` or `"unknown"`.
        public var state: String?
        public var charge: Item?
        /// `-1` is "unspecified".
        public var socket: Int

        enum CodingKeys: String, CodingKey { case typeID, count, state, charge, socket }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            typeID = try c.decode(Int.self, forKey: .typeID)
            count = try c.decodeIfPresent(Int.self, forKey: .count) ?? 1
            state = try c.decodeIfPresent(String.self, forKey: .state)
            charge = try c.decodeIfPresent(Item.self, forKey: .charge)
            socket = try c.decodeIfPresent(Int.self, forKey: .socket) ?? -1
        }
    }

    public struct Drone: Decodable, Sendable, Equatable {
        public var typeID: Int
        public var count: Int
        public var isActive: Bool
        public var isKamikaze: Bool
        /// `-1` is "no squadron".
        public var squadronTag: Int

        enum CodingKeys: String, CodingKey { case typeID, count, isActive, isKamikaze, squadronTag }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            typeID = try c.decode(Int.self, forKey: .typeID)
            count = try c.decodeIfPresent(Int.self, forKey: .count) ?? 1
            isActive = try c.decodeIfPresent(Bool.self, forKey: .isActive) ?? false
            isKamikaze = try c.decodeIfPresent(Bool.self, forKey: .isKamikaze) ?? false
            squadronTag = try c.decodeIfPresent(Int.self, forKey: .squadronTag) ?? -1
        }
    }

    public struct Item: Decodable, Sendable, Equatable {
        public var typeID: Int
        public var count: Int

        enum CodingKeys: String, CodingKey { case typeID, count }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            typeID = try c.decode(Int.self, forKey: .typeID)
            count = try c.decodeIfPresent(Int.self, forKey: .count) ?? 1
        }
    }

    enum CodingKeys: String, CodingKey { case typeID, name, modules, drones, cargo, implants, boosters }

    private struct AnyKey: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }
        init(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        typeID = try c.decode(Int.self, forKey: .typeID)
        name = try c.decodeIfPresent(String.self, forKey: .name)
        drones = try c.decodeIfPresent([Drone].self, forKey: .drones) ?? []
        cargo = try c.decodeIfPresent([Item].self, forKey: .cargo) ?? []
        implants = try c.decodeIfPresent([Int].self, forKey: .implants) ?? []
        boosters = try c.decodeIfPresent([Int].self, forKey: .boosters) ?? []

        racks = []
        guard c.contains(.modules), try !c.decodeNil(forKey: .modules) else { return }
        if var list = try? c.nestedUnkeyedContainer(forKey: .modules) {
            while !list.isAtEnd {
                let key = try list.decode(String.self)
                let modules = try list.decode([Module].self)
                racks.append(Rack(slot: Slot(key: key), modules: modules))
            }
        } else {
            let object = try c.nestedContainer(keyedBy: AnyKey.self, forKey: .modules)
            for key in object.allKeys {
                racks.append(Rack(slot: Slot(key: key.stringValue),
                                  modules: try object.decode([Module].self, forKey: key)))
            }
        }
    }
}

// MARK: - FitDocument

extension LegacyShip {
    /// Racks in the order a `FitDocument` lists modules; a slot the engine has no rack for
    /// goes last and is left to the engine to place or reject.
    private static func rackOrder(_ slot: Slot) -> Int {
        switch slot {
        case .hi: 0
        case .med: 1
        case .low: 2
        case .rig: 3
        case .subsystem: 4
        case .service: 5
        case .mode: 6
        case .none, .starbaseStructure, .unknown: 7
        }
    }

    /// The same fit as a `FitDocument`, for one pilot at `skillLevel` across the board.
    ///
    /// Type IDs are copied unchecked; loading the document reports types the engine rejects.
    /// Not carried: cargo, charge counts and drone squadron tags (drones sharing a tag become
    /// one stack).
    public func fitDocument(name: String?, skillLevel: UInt8) -> FitDocument {
        var modules: [FitDocument.Module] = []
        let racks = racks.enumerated()
            .sorted { (Self.rackOrder($0.element.slot), $0.offset) < (Self.rackOrder($1.element.slot), $1.offset) }
            .map(\.element)
        for rack in racks {
            var placed: [FitDocument.Module] = []
            for module in rack.modules {
                let state = module.state.flatMap(FitDocument.Module.State.init(rawValue:))
                let charge = module.charge.flatMap { $0.typeID > 0 ? FitDocument.Item(Self.typeID($0.typeID)) : nil }
                // The engine numbers subsystem and mode sockets itself.
                let keepsSocket = module.socket >= 0 && rack.slot != .subsystem && rack.slot != .mode
                for copy in 0..<max(module.count, 1) {
                    placed.append(FitDocument.Module(type: Self.typeID(module.typeID),
                                                     socket: keepsSocket && copy == 0 ? module.socket : nil,
                                                     state: state,
                                                     charge: charge))
                }
            }
            // Explicit sockets first, so an unplaced module cannot take a socket named later.
            placed = placed.enumerated()
                .sorted { ($0.element.socket ?? .max, $0.offset) < ($1.element.socket ?? .max, $1.offset) }
                .map(\.element)
            modules += placed
        }

        let ship = FitDocument.Ship(type: Self.typeID(typeID), modules: modules, drones: fitDrones())
        let pilot = FitDocument.Pilot(skills: .init(default: skillLevel),
                                      implants: implants.filter { $0 > 0 }.map { FitDocument.Item(Self.typeID($0)) },
                                      boosters: boosters.filter { $0 > 0 }.map { FitDocument.Item(Self.typeID($0)) },
                                      ship: ship)
        return FitDocument(name: name, pilots: [pilot])
    }

    /// One stack per old entry, except that entries of one squadron are summed into one stack.
    private func fitDrones() -> [FitDocument.Drone] {
        struct Key: Hashable {
            var typeID: Int, squadronTag: Int, isActive: Bool, isKamikaze: Bool
        }
        var stacks: [(key: Key, count: Int)] = []
        var indexByKey: [Key: Int] = [:]
        for drone in drones {
            let key = Key(typeID: drone.typeID, squadronTag: drone.squadronTag,
                          isActive: drone.isActive, isKamikaze: drone.isKamikaze)
            let count = max(drone.count, 1)
            if drone.squadronTag >= 0, let index = indexByKey[key] {
                stacks[index].count += count
            } else {
                if drone.squadronTag >= 0 { indexByKey[key] = stacks.count }
                stacks.append((key, count))
            }
        }
        return stacks.map { stack in
            FitDocument.Drone(type: Self.typeID(stack.key.typeID),
                              count: UInt8(clamping: stack.count),
                              active: stack.key.isActive ? true : nil,
                              kamikaze: stack.key.isKamikaze ? true : nil)
        }
    }

    private static func typeID(_ value: Int) -> TypeID {
        TypeID(rawValue: UInt32(clamping: value))
    }
}
