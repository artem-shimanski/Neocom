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
    init?(_ hull: borrowing FitStats.Hull) {
        guard hull.categoryID == .structure else { return nil }
        var services: [(socket: Int, service: Service)] = []
        hull.modules.forEach(in: .service) { module in
            // Matches the engine's totals: online or above consumes fuel.
            guard module.effectiveState >= .online else { return }
            services.append((module.socket, Service(id: module.id,
                                                    typeID: module.typeID,
                                                    perHour: module.serviceFuelPerHour,
                                                    toOnline: module.serviceFuelToOnline)))
        }
        self.init(services: services.sorted { $0.socket < $1.socket }.map(\.service),
                  perHour: hull.fuelPerHour,
                  toOnline: hull.fuelToOnline)
    }
}
