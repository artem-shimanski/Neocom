import DogmaKit
import Foundation

/// Errors raised when a document cannot be loaded into the engine.
nonisolated enum FittingEngineError: LocalizedError {
    /// The document has no pilot, or the pilot is in a capsule.
    case noShip

    var errorDescription: String? {
        switch self {
        case .noShip:
            String(localized: "This fit has no ship.")
        }
    }
}

/// One-shot layout of a stored document: the rack and socket of each module.
///
/// `FitDocument` does not store racks; they are inferred from type effects, which only
/// DogmaKit knows. Used for the ESI upload. A fresh engine is created per call, since
/// `DogmaEngine.load` replaces the whole session; live editing goes through `FitSession`.
actor FittingEngine {
    /// One module, laid out.
    struct Placement: Sendable {
        var typeID: TypeID
        var slot: Entity.Module.Slot
        var socket: Int
        var chargeTypeID: TypeID?
    }

    /// One stack of drones or one squadron of fighters.
    struct DroneStack: Sendable {
        var typeID: TypeID
        var count: Int
        var isFighter: Bool
    }

    struct Layout: Sendable {
        var shipTypeID: TypeID
        var modules: [Placement]
        var drones: [DroneStack]
        /// Load warnings in player-readable form.
        var warnings: [String]
    }

    /// Lays out a document: the rack and socket of each module, and each drone stack.
    ///
    /// Only the first pilot is laid out.
    func layout(of document: FitDocument) async throws -> Layout {
        guard document.pilots.first?.ship != nil else { throw FittingEngineError.noShip }

        let engine = DogmaEngine()
        let importWarnings = try await engine.load(document, strict: false)

        // Read through `edit` rather than `evaluate`: the layout does not depend on the dogma
        // calculation, which `evaluate` would run.
        guard var layout = await engine.edit({ fit -> Layout? in
            guard let pilotID = fit.pilots.allIDs.first(where: { _ in true }) else { return nil }
            let hull = fit[pilotID.hull]

            var modules: [Placement] = []
            // Sorted by rack and socket: entity ids are not allocated in socket order.
            for slot in Entity.Module.Slot.allCases {
                var placements: [Placement] = []
                hull.modules.forEach(in: slot) { module in
                    placements.append(Placement(typeID: module.typeID,
                                                slot: slot,
                                                socket: module.socket,
                                                chargeTypeID: module.charge?.typeID))
                }
                modules.append(contentsOf: placements.sorted { $0.socket < $1.socket })
            }

            var drones: [DroneStack] = []
            hull.drones.forEach { drone in
                drones.append(DroneStack(typeID: drone.typeID,
                                       count: Int(drone.count),
                                       isFighter: drone.categoryID == .fighter))
            }

            return Layout(shipTypeID: hull.typeID, modules: modules, drones: drones, warnings: [])
        }) else {
            // The engine kept no pilot; the reason is already in `importWarnings`.
            throw FittingEngineError.noShip
        }

        layout.warnings = importWarnings.map { String(localized: "Part of this fit could not be loaded: \(String(describing: $0)).") }
        return layout
    }
}
