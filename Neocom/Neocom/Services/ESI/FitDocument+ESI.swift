import DogmaKit
import Foundation

/// A parsed ESI fitting flag: which rack, and which position in it.
///
/// An item's role is determined by flag and type category together: a charge shares the flag
/// of the module it is loaded into. `init(_:)` parses a flag, `rawFlag` formats one.
enum FittingFlag: Equatable {
    case slot(Entity.Module.Slot, index: Int)
    case droneBay
    case fighterBay
    case cargo
    case unknown(String)

    /// One rack as ESI flags it.
    struct Rack: Sendable {
        var slot: Entity.Module.Slot
        var prefix: String
        /// The socket numbers ESI has flags for; e.g. `HiSlot8` does not exist.
        var sockets: ClosedRange<Int>
    }

    /// The racks ESI has flags for, shared by parsing and formatting. `.mode` (tactical
    /// destroyer mode) has no ESI flag.
    static let racks: [Rack] = [
        Rack(slot: .hi, prefix: "HiSlot", sockets: 0...7),
        Rack(slot: .med, prefix: "MedSlot", sockets: 0...7),
        Rack(slot: .low, prefix: "LoSlot", sockets: 0...7),
        Rack(slot: .rig, prefix: "RigSlot", sockets: 0...2),
        Rack(slot: .service, prefix: "ServiceSlot", sockets: 0...7),
        Rack(slot: .subsystem, prefix: "SubSystemSlot", sockets: 0...3),
    ]

    init(_ raw: String) {
        switch raw {
        case "DroneBay":
            self = .droneBay
        case "FighterBay":
            self = .fighterBay
        case "Cargo":
            self = .cargo
        default:
            for rack in Self.racks where raw.hasPrefix(rack.prefix) {
                // Parsing does not check `sockets`, so overfitted fits still import.
                guard let index = Int(raw.dropFirst(rack.prefix.count)) else { continue }
                self = .slot(rack.slot, index: index)
                return
            }
            // Covers the documented `"Invalid"` flag and any future flags.
            self = .unknown(raw)
        }
    }

    /// The ESI flag string for this location, or `nil` when ESI has none: the `.mode` rack or a
    /// socket past the end of its rack. Callers report both as losses (see `ESIUpload`).
    var rawFlag: String? {
        switch self {
        case let .slot(slot, index):
            guard let rack = Self.racks.first(where: { $0.slot == slot }),
                  rack.sockets.contains(index) else { return nil }
            return "\(rack.prefix)\(index)"
        case .droneBay:
            return "DroneBay"
        case .fighterBay:
            return "FighterBay"
        case .cargo:
            return "Cargo"
        case let .unknown(raw):
            return raw
        }
    }
}

extension FitDocument {
    /// The skill level assumed for every skill of fits created or imported by the app.
    /// `ESIUpload` does not report it as a loss.
    static let assumedSkillLevel: UInt8 = 5

    /// Converts a game fitting, appending to `warnings` everything the document cannot hold.
    init(_ fitting: ESIFitting, catalog: TypeCatalog, warnings: inout [String]) {
        /// A placed module; mutable so the second pass can attach its charge.
        struct Placed {
            var slot: Entity.Module.Slot
            var index: Int
            var module: FitDocument.Module
        }

        let items = fitting.items.map { item in (item: item, flag: FittingFlag(item.flag)) }

        var placed: [Placed] = []
        // ESI stores a module and its charge under the same flag; the second pass uses this to
        // find a charge's module.
        var placedIndicesByFlag: [String: [Int]] = [:]
        var drones: [FitDocument.Drone] = []
        var cargoCount = 0
        var unknownFlagOrder: [String] = []
        var unknownCounts: [String: Int] = [:]

        // First pass: modules and drones.
        for (item, flag) in items {
            let typeID = TypeID(rawValue: UInt32(clamping: item.typeID))

            switch flag {
            case .slot(let slot, let index):
                // Charges are handled in the second pass.
                guard catalog.categoryID(of: typeID) != .charge else { continue }

                let count = max(Int(clamping: item.quantity), 0)
                guard count > 0 else {
                    warnings.append(String(localized: "An item with no quantity was skipped: type \(item.typeID)."))
                    continue
                }
                for position in 0..<count {
                    // `quantity > 1` means identical modules: the first takes the flag's socket,
                    // the rest the next free one. Subsystems always take the next free socket:
                    // the engine numbers them in insertion order, so `SubSystemSlotN` is not a
                    // socket number.
                    let socket = (slot == .subsystem || position > 0) ? nil : index
                    let module = FitDocument.Module(type: typeID, socket: socket)
                    placedIndicesByFlag[item.flag, default: []].append(placed.count)
                    placed.append(Placed(slot: slot, index: index, module: module))
                }

            case .fighterBay:
                // One item can stand for several squadrons (27 fighters = three of nine); it is
                // split by the type's squadron size. Types without a size, or quantities beyond
                // 16 squadrons, stay a single stack.
                let quantity = max(Int(clamping: item.quantity), 1)
                let size = Int(catalog.attribute(.fighterSquadronMaxSize, of: typeID) ?? 0)
                guard size > 0, quantity > size, quantity <= size * 16 else {
                    drones.append(FitDocument.Drone(type: typeID, count: UInt8(clamping: quantity)))
                    continue
                }
                var left = quantity
                while left > 0 {
                    let count = min(left, size)
                    drones.append(FitDocument.Drone(type: typeID, count: UInt8(clamping: count)))
                    left -= count
                }

            case .droneBay:
                let count = UInt8(clamping: max(item.quantity, 1))
                if item.quantity > Int64(UInt8.max) {
                    // `FitDocument.Drone.count` is a `UInt8`.
                    warnings.append(String(localized: "A drone stack of \(item.quantity) was reduced to \(count): type \(item.typeID)."))
                }
                // Imported inactive: ESI does not distinguish the bay from space.
                drones.append(FitDocument.Drone(type: typeID, count: count))

            case .cargo:
                cargoCount += 1

            case .unknown(let raw):
                if unknownCounts[raw] == nil { unknownFlagOrder.append(raw) }
                unknownCounts[raw, default: 0] += 1
            }
        }

        // Second pass: charges, attached to the modules placed under the same flag.
        for (item, flag) in items {
            guard case .slot = flag else { continue }
            let chargeTypeID = TypeID(rawValue: UInt32(clamping: item.typeID))
            guard catalog.categoryID(of: chargeTypeID) == .charge else { continue }

            guard let indices = placedIndicesByFlag[item.flag], !indices.isEmpty else {
                warnings.append(String(localized: "A charge has no module in its slot: type \(item.typeID)."))
                continue
            }
            let moduleTypeID = placed[indices[0]].module.type
            guard catalog.canLoad(chargeTypeID, into: moduleTypeID) else {
                warnings.append(String(localized: "A charge does not fit its module: type \(item.typeID)."))
                continue
            }
            // Charge quantity is ignored: `FitDocument` stores only which charge is loaded.
            for index in indices {
                placed[index].module.charge = FitDocument.Item(chargeTypeID)
            }
        }

        if cargoCount > 0 {
            warnings.append(String(localized: "Cargo is not part of a fit: \(cargoCount) items skipped."))
        }
        for raw in unknownFlagOrder {
            let count = unknownCounts[raw] ?? 0
            warnings.append(String(localized: "Unknown flag \"\(raw)\": \(count) items skipped."))
        }

        // Sorted by rack and slot number for deterministic output.
        let rackOrder = Dictionary(uniqueKeysWithValues: Entity.Module.Slot.allCases.enumerated().map { ($1, $0) })
        let modules = placed
            .sorted { lhs, rhs in
                (rackOrder[lhs.slot] ?? .max, lhs.index) < (rackOrder[rhs.slot] ?? .max, rhs.index)
            }
            .map(\.module)

        let ship = FitDocument.Ship(type: TypeID(rawValue: UInt32(clamping: fitting.shipTypeID)),
                                     modules: modules,
                                     drones: drones)
        // The format carries no skills; the pilot gets the assumed level.
        let pilot = FitDocument.Pilot(skills: .init(default: FitDocument.assumedSkillLevel), ship: ship)
        // `fittingDescription` becomes the `Fitting`'s notes, set by the caller.
        self.init(name: fitting.name, pilots: [pilot])
    }
}

/// Reasons a fit cannot be uploaded; each corresponds to a request ESI would reject.
nonisolated enum ESIUploadError: LocalizedError {
    case noShip
    case noName
    case noItems

    var errorDescription: String? {
        switch self {
        case .noShip:
            String(localized: "This fit has no ship, so there is nothing to save in EVE.")
        case .noName:
            String(localized: "This fit needs a name before it can be saved in EVE.")
        case .noItems:
            String(localized: "EVE cannot save a fitting with no modules.")
        }
    }
}

/// The request body for `POST /fittings`, and what the game will not keep.
///
/// Built from a document and its `FittingEngine` layout, which supplies the rack and socket of
/// each module.
struct ESIUpload: Sendable {
    /// ESI limits on the text fields.
    static let nameLimit = 50
    static let descriptionLimit = 500

    /// Clipped to `nameLimit`.
    var name: String
    /// The fit's notes, ESI's fitting description. Clipped to `descriptionLimit`.
    var description: String
    var shipTypeID: Int64
    var items: [ESIFitting.Item]
    /// Player-readable descriptions of what the game will not store, listed only for data the
    /// fit actually has. Shown before the request is sent; separate from
    /// `FittingEngine.Layout.warnings`, which lists what the engine could not load.
    var losses: [String]
}

extension ESIUpload {
    /// - Parameters:
    ///   - document: the stored fit.
    ///   - name: the `Fitting`'s name; the document's own copy can be stale.
    ///   - notes: the `Fitting`'s notes, uploaded as the description.
    ///   - layout: the same document, laid out by `FittingEngine`.
    init(document: FitDocument, name: String, notes: String, layout: FittingEngine.Layout) throws {
        // A fitting holds one ship; additional pilots are reported as a loss.
        guard let pilot = document.pilots.first, let ship = pilot.ship else {
            throw ESIUploadError.noShip
        }
        var losses: [String] = []

        if document.pilots.count > 1 {
            let others = document.pilots.count - 1
            losses.append(String(localized: "A fitting in EVE holds one ship: \(others) other pilots not saved."))
        }

        // MARK: Items

        var items: [ESIFitting.Item] = []
        var skippedModes = 0
        var overfitted: [Entity.Module.Slot: Int] = [:]

        for module in layout.modules {
            guard let flag = FittingFlag.slot(module.slot, index: module.socket).rawFlag else {
                // Counted separately: the two causes read as different messages.
                if module.slot == .mode {
                    skippedModes += 1
                } else {
                    overfitted[module.slot, default: 0] += 1
                }
                continue
            }
            items.append(ESIFitting.Item(typeID: Int64(module.typeID.rawValue),
                                         flag: flag,
                                         quantity: 1))
            if let charge = module.chargeTypeID {
                // A charge is a separate item under the module's flag, quantity 1.
                items.append(ESIFitting.Item(typeID: Int64(charge.rawValue),
                                             flag: flag,
                                             quantity: 1))
            }
        }

        if skippedModes > 0 {
            losses.append(String(localized: "A tactical mode is not part of a fitting in EVE: \(skippedModes) modules not saved."))
        }
        // Table order, for deterministic output.
        for rack in FittingFlag.racks {
            guard let count = overfitted[rack.slot], count > 0 else { continue }
            losses.append(Self.overfittedMessage(for: rack.slot, count: count))
        }

        for stack in layout.drones {
            let bay: FittingFlag = stack.isFighter ? .fighterBay : .droneBay
            guard let flag = bay.rawFlag else {
                // Unreachable: both bays have a flag.
                losses.append(String(localized: "A drone could not be saved: type \(stack.typeID.rawValue)."))
                continue
            }
            items.append(ESIFitting.Item(typeID: Int64(stack.typeID.rawValue),
                                         flag: flag,
                                         quantity: Int64(max(stack.count, 1))))
        }

        // ESI accepts 1…512 items. The upper bound cannot be reached: the racks cap modules,
        // and charges and drones cannot add up to 512.
        guard !items.isEmpty else { throw ESIUploadError.noItems }

        // MARK: Losses

        // Only for data the fit actually has. Cargo needs no line: `FitDocument` has none.
        if ship.modules.contains(where: { $0.state != nil }) {
            losses.append(String(localized: "Module states (offline, active, overloaded) are not part of a fitting in EVE."))
        }
        if !pilot.implants.isEmpty {
            losses.append(String(localized: "Implants are not part of a fitting in EVE."))
        }
        if !pilot.boosters.isEmpty {
            losses.append(String(localized: "Boosters are not part of a fitting in EVE."))
        }
        // Reported only for non-default skills: every fit the app creates uses
        // `assumedSkillLevel`, and a warning on every upload would be ignored.
        if let skills = pilot.skills,
           !skills.levels.isEmpty || skills.default != FitDocument.assumedSkillLevel {
            losses.append(String(localized: "Skill levels are not part of a fitting in EVE."))
        }
        if ship.modules.contains(where: { $0.mutation != nil })
            || ship.drones.contains(where: { $0.mutation != nil }) {
            losses.append(String(localized: "An abyssal module keeps its type, but its rolled attributes are not part of a fitting in EVE."))
        }
        if ship.drones.contains(where: { $0.active == true }) {
            losses.append(String(localized: "A fitting in EVE cannot tell drones in space from drones in the bay."))
        }
        if ship.modules.contains(where: { $0.target != nil })
            || ship.drones.contains(where: { $0.target != nil }) {
            losses.append(String(localized: "Targets are not part of a fitting in EVE."))
        }
        if !document.environment.isEmpty {
            losses.append(String(localized: "Simulated environment effects are not part of a fitting in EVE."))
        }

        // MARK: Text

        let clippedName = String(name.prefix(Self.nameLimit))
        if clippedName.count < name.count {
            losses.append(String(localized: "The name was shortened to \(Self.nameLimit) characters, which is all EVE stores."))
        }
        guard !clippedName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ESIUploadError.noName
        }
        let clippedNotes = String(notes.prefix(Self.descriptionLimit))
        if clippedNotes.count < notes.count {
            losses.append(String(localized: "The notes were shortened to \(Self.descriptionLimit) characters, which is all EVE stores."))
        }

        self.init(name: clippedName,
                  description: clippedNotes,
                  // The hull the layout was built on; the engine may have rejected the document's.
                  shipTypeID: Int64(layout.shipTypeID.rawValue),
                  items: items,
                  losses: losses)
    }

    /// One sentence per slot kind, so each translation agrees with its noun.
    private static func overfittedMessage(for slot: Entity.Module.Slot, count: Int) -> String {
        switch slot {
        case .hi: String(localized: "The high slot rack holds more than EVE can store: \(count) modules not saved.")
        case .med: String(localized: "The medium slot rack holds more than EVE can store: \(count) modules not saved.")
        case .low: String(localized: "The low slot rack holds more than EVE can store: \(count) modules not saved.")
        case .rig: String(localized: "The rig rack holds more than EVE can store: \(count) modules not saved.")
        case .subsystem: String(localized: "The subsystem rack holds more than EVE can store: \(count) modules not saved.")
        case .service: String(localized: "The service slot rack holds more than EVE can store: \(count) modules not saved.")
        case .mode: String(localized: "The tactical mode rack holds more than EVE can store: \(count) modules not saved.")
        }
    }
}
