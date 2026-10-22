import DogmaKit
import LiteRow
import LiteRowUI
import SDEKit
import SwiftUI

/// The stats screen's fuel section, for a structure: the burn over an hour, a day and a month,
/// what onlining the services cost, and a line per online service module.
///
/// A view of its own: the modules are named through `@LiteQuery`, which is built in `init`.
struct FitFuelSection: View {
    let fuel: FitFuel

    @LiteQuery private var typeNames: [TypeNameRow]

    init(fuel: FitFuel) {
        self.fuel = fuel
        // Sorted: the query is `@LiteQuery`'s cache key.
        let ids = Set(fuel.services.map(\.typeID)).sorted { $0.rawValue < $1.rawValue }
        _typeNames = LiteQuery(SDEBrowser.typeNames(of: ids))
    }

    var body: some View {
        let names = Dictionary(typeNames.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        HUDListSection {
            HUDReadoutRow("Per hour", value: blocks(fuel.perHour))
            HUDReadoutRow("Per day", value: blocks(fuel.perDay))
            HUDReadoutRow("Per 30 days", value: blocks(fuel.perThirtyDays))
            HUDReadoutRow("To online", value: blocks(fuel.toOnline))
            if fuel.services.isEmpty {
                Text("No service module is online.")
                    .font(.hudReadout)
                    .foregroundStyle(Color.hudInkFaint)
                    .hudRow(.readout)
            } else {
                ForEach(fuel.services) { service in
                    HUDReadoutRow(Text(verbatim: names[service.typeID] ?? "—"),
                                  value: perHour(service.perHour))
                }
            }
        } header: {
            HUDSectionHeader(Text("Fuel")) {
                Text("Fuel blocks")
            }
        } footer: {
            HUDFootnote("Online service modules only, with the structure's own bonuses. An offline module burns no fuel.")
        }
    }

    private func blocks(_ value: Double) -> String {
        FitStatFormat.plain(value, fraction: 0...1)
    }

    private func perHour(_ value: Double) -> String {
        String(localized: "\(FitStatFormat.plain(value, fraction: 0...1))/h",
               comment: "Rate per hour")
    }
}
