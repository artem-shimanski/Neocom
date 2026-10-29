import DogmaKit
import Foundation

/// One ship of the open fleet as the screens draw it: the engine's pilot, the My Fits record it
/// is saved to, the record's name, its hull and its stats line.
struct FleetMember: Identifiable {
    var id: PilotID
    var fittingID: UUID
    var name: String
    var shipTypeID: TypeID
    var stats: FleetSnapshot.Ship.Stats
}

extension FittingEditorModel {
    /// The fleet's ships in fleet order, named after their records in `fits`. A ship queued by
    /// `addShip` but not yet taken in by the engine is omitted until its snapshot arrives.
    func members(named fits: [FittingSummary]) -> [FleetMember] {
        let names = Dictionary(fits.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        let lines = Dictionary(fleet.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return ships.compactMap { ship in
            guard let line = lines[ship.id] else { return nil }
            return FleetMember(id: ship.id,
                               fittingID: ship.fittingID,
                               name: names[ship.fittingID] ?? "",
                               shipTypeID: line.shipTypeID,
                               stats: line.stats)
        }
    }
}

/// One effect between two ships of the fleet in words: who, on whom, through what, how much.
/// Shared by the editor header's incoming block and the fleet overview.
struct FleetEffectLine: Identifiable {
    var id: FitSnapshot.Incoming.Source
    var source: String
    var target: String
    /// The module, or the stack with its count (`5× Hobgoblin II`).
    var detail: String
    /// Signed (`+59.2 HP/s`, `-48 GJ/s`), `Off` for a module or stack that is not working, or
    /// `nil` for an effect the engine puts no figure on (a web, a disruptor).
    var amount: String?
    var tone: HUDEffectTone

    init(_ effect: FitSnapshot.Incoming, shipNames: [PilotID: String], typeNames: [TypeID: String]) {
        id = effect.id
        source = shipNames[effect.pilotID] ?? ""
        target = shipNames[effect.targetID] ?? ""
        let typeName = typeNames[effect.typeID] ?? ""
        detail = effect.count > 1 ? "\(effect.count)× \(typeName)" : typeName

        if !effect.isActive {
            amount = String(localized: "Off")
            tone = .neutral
        } else if let repair = effect.repair, repair.hpPerSecond > 0 {
            amount = "+" + FitStatFormat.hpPerSecond(repair.hpPerSecond)
            tone = .gain
        } else if let capacitor = effect.capacitor, abs(capacitor) >= 0.05 {
            amount = FitStatFormat.energyRate(capacitor)
            tone = capacitor > 0 ? .gain : .loss
        } else {
            amount = nil
            tone = .neutral
        }
    }
}
