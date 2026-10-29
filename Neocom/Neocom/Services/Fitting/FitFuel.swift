import DogmaKit

/// Fuel consumption of an Upwell structure: fuel blocks per hour per online service module,
/// and the cost of bringing them online.
///
/// `nil` for non-structure hulls. Figures are the engine's modified values (role bonuses
/// applied). Offline modules are omitted. The fuel bay is not modeled: the SDE gives Upwell
/// structures no fuel capacity.
nonisolated struct FitFuel: Sendable {
    nonisolated struct Service: Sendable, Identifiable {
        var id: ModuleID
        var typeID: TypeID
        /// Fuel blocks per hour.
        var perHour: Double
        /// Fuel blocks spent once to bring the module online.
        var toOnline: Double
    }

    /// The online service modules, in socket order.
    var services: [Service]
    /// The engine's totals (`FitStats.Hull.fuelPerHour`, `fuelToOnline`).
    var perHour: Double
    var toOnline: Double

    var perDay: Double { perHour * 24 }
    var perThirtyDays: Double { perHour * 24 * 30 }
}

nonisolated extension FitFuel {
    /// `nil` for anything but a structure.
    init?(_ hull: FitStats.Hull.Snapshot) {
        guard hull.categoryID == .structure else { return nil }
        let services = hull.modules
            // Matches the engine's totals: online or above consumes fuel.
            .filter { $0.slot == .service && $0.effectiveState >= .online }
            .sorted { $0.socket < $1.socket }
            .map { Service(id: $0.id, typeID: $0.typeID, perHour: $0.serviceFuelPerHour, toOnline: $0.serviceFuelToOnline) }
        self.init(services: services, perHour: hull.fuelPerHour, toOnline: hull.fuelToOnline)
    }
}
