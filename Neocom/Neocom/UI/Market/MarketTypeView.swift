import LiteRowUI
import MarketKit
import SDEKit
import SwiftUI

/// The market of one type in the app's market region: the summary, the price history, and
/// the order book with a quantity calculator. Reached from the item screen's price card.
///
/// Everything comes through `MarketTypeModel`; another region or pilot is another model (`id`).
struct MarketTypeView: View {
    let typeID: TypeID

    @Environment(MarketSheet.self) private var market
    @Environment(AccountStore.self) private var accounts
    @Environment(SDEStore.self) private var sde
    @LiteQuery private var summary: TypeSummary?
    @State private var isShowingRegions = false
    /// A region the screen was opened in rather than the preference; dropped once a region is picked
    /// in the sheet.
    @State private var regionOverride: Int64?

    init(typeID: TypeID, regionID: Int64? = nil) {
        self.typeID = typeID
        _regionOverride = State(initialValue: regionID)
        _summary = LiteQuery(SDEBrowser.summary(of: typeID))
    }

    private struct ModelKey: Hashable {
        var regionID: Int64
        var characterSheet: ObjectIdentifier?
    }

    var body: some View {
        let regionID = regionOverride ?? market.regions.regionID
        let characterSheet = accounts.currentSheet
        MarketTypeScreen(market: market, typeID: typeID, regionID: regionID,
                         characterSheet: characterSheet, database: sde.database,
                         onChangeRegion: { isShowingRegions = true })
            .id(ModelKey(regionID: regionID, characterSheet: characterSheet.map(ObjectIdentifier.init)))
            .hudScreen()
            .navigationTitle(summary?.name ?? "")
            .navigationSubtitle(Text("Market"))
            .navigationBarTitleDisplayMode(.inline)
            .onChange(of: market.regions.regionID) { regionOverride = nil }
            .sheet(isPresented: $isShowingRegions) {
                MarketRegionSheet()
            }
    }
}

private struct MarketTypeScreen: View {
    let database: SDEDatabase?
    let onChangeRegion: () -> Void
    @State private var model: MarketTypeModel
    @Environment(MarketSheet.self) private var market

    init(market: MarketSheet, typeID: TypeID, regionID: Int64, characterSheet: CharacterSheet?,
         database: SDEDatabase?, onChangeRegion: @escaping () -> Void) {
        self.database = database
        self.onChangeRegion = onChangeRegion
        _model = State(initialValue: MarketTypeModel(sheet: market, typeID: Int64(typeID.rawValue),
                                                     regionID: regionID, characterSheet: characterSheet))
    }

    var body: some View {
        MarketRegionName(regionID: model.regionID,
                         hubSystemID: market.regions.hubSystemID(forRegion: model.regionID)) { region, hub in
            HUDList {
                Section {
                    MarketRegionChip(region: region, hub: hub?.name, action: onChangeRegion)
                        .hudBareRow()
                }

                if model.orders.value == nil, case let .failed(error) = model.orders.state {
                    Section {
                        HUDEmptyPanel(title: Text("Market Unavailable"), message: Text(error.localizedDescription)) {
                            Button("Retry") {
                                Task { await model.refresh(database: database) }
                            }
                            .hudProminentButton()
                        }
                        .hudBareRow()
                    }
                } else {
                    MarketSummarySection(model: model)
                    if let failure {
                        Section {
                            HUDStatusChip(text: Text("Not updated · \(failure.localizedDescription)"),
                                          color: .hudDanger, mark: .symbol("exclamationmark.triangle.fill"))
                                .lineLimit(2)
                                .padding(.horizontal, HUDMetrics.headerFaceInset)
                                .hudBareRow()
                        }
                    }
                    MarketHistorySection(model: model)
                    MarketOrdersSection(model: model, regionName: region, pilotSystemID: model.pilotSystemID)
                }

                Section {
                    HUDFootnote("Orders refresh every 5 minutes, history once a day.")
                        .hudBareRow()
                }
            }
        }
        .task { await model.load(database: database) }
        .refreshableCommand { await model.refresh(database: database) }
    }

    private var failure: (any Error)? {
        if model.orders.value != nil, case let .failed(error) = model.orders.state { return error }
        if model.history.value != nil, case let .failed(error) = model.history.state { return error }
        return nil
    }
}

/// The region the screen is for, as a button that opens the region sheet: `Heimatar · Rens`.
private struct MarketRegionChip: View {
    let region: String?
    let hub: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: "globe")
                    .font(.system(size: 14, weight: .semibold))
                Text(verbatim: region ?? "—")
                    .fontWeight(.semibold)
                if let hub {
                    Text(verbatim: "· \(hub)")
                        .foregroundStyle(Color.hudInkMuted)
                }
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.hudInkMuted)
            }
            .font(.subheadline)
            .foregroundStyle(Color.hudInk)
        }
        .buttonStyle(.glass)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityLabel(Text("Region: \(region ?? "")"))
        .accessibilityHint(Text("Change region"))
    }
}

// MARK: - Summary

/// Best prices, spread and volume, then the comparison with CCP's average and the nearest
/// seller to the pilot.
private struct MarketSummarySection: View {
    let model: MarketTypeModel

    var body: some View {
        let summary = model.summary
        HUDListSection {
            HUDStatStrip(items: [
                .init(id: 0, label: Text("Best Sell"), value: Text(verbatim: summary.bestSell.map(ISK.compact) ?? "—")),
                .init(id: 1, label: Text("Best Buy"), value: Text(verbatim: summary.bestBuy.map(ISK.compact) ?? "—")),
                .init(id: 2, label: Text("Spread"), value: Text(verbatim: summary.spread.map(MarketFormat.percent) ?? "—")),
                .init(id: 3, label: Text("Vol / Day"),
                      value: Text(verbatim: summary.averageDailyVolume.map(MarketFormat.volumePerDay) ?? "—")),
            ])
            .hudRow(HUDRowStyle(horizontalPadding: 0, minHeight: 0, verticalPadding: 0))

            HUDReadoutRow("EVE Average", value: summary.ccpAverage.map(ISK.price) ?? "—")
            HUDReadoutRow("Best Sell vs Average") {
                Text(verbatim: summary.versusCCP.map(MarketFormat.signedPercent) ?? "—")
                    .foregroundStyle(Color.hudInkBodyMuted)
            }
            if model.pilotSystemID != nil {
                HUDReadoutRow("Nearest Seller", value: nearestSeller)
            }
        }
    }

    /// `RENS · 2 J · 9.25M`.
    private var nearestSeller: String {
        guard let row = model.nearestSell, let jumps = row.jumps else { return "—" }
        let system = row.systemName?.uppercased() ?? "—"
        return "\(system) · \(MarketFormat.jumps(jumps).uppercased()) · \(ISK.compact(row.order.price))"
    }
}
