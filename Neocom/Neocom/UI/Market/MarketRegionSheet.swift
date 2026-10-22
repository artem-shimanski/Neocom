import LiteRow
import LiteRowUI
import SDEKit
import SwiftUI

/// Picks the region every price in the app is read in: the trade hubs first, then recent picks,
/// then all regions; search matches a region's name or any of its systems. The pick is stored in
/// `MarketRegionPreference` and the sheet closes. Opens the database itself, as a sheet does not
/// reliably inherit `liteDatabase`.
struct MarketRegionSheet: View {
    @Environment(MarketSheet.self) private var market
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""

    var body: some View {
        NavigationStack {
            SDESectionView { database in
                let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty {
                    MarketRegionList(preference: market.regions, onSelect: select)
                } else {
                    MarketRegionSearchResults(pattern: database.pattern(trimmed), searchText: trimmed,
                                              currentRegionID: market.regions.regionID) {
                        select($0, hubSystemID: nil)
                    }
                }
            }
            .navigationTitle("Market Region")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: Text("Region or system"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark", role: .cancel) { dismiss() }
                }
            }
        }
    }

    /// `hubSystemID` when the region was picked through one of the trade hubs.
    private func select(_ regionID: Int64, hubSystemID: Int64?) {
        market.regions.select(regionID, hubSystemID: hubSystemID)
        dismiss()
    }
}

private let sheetRowStyle = HUDRowStyle(background: HUDRowStyle.sheet.background,
                                        border: HUDRowStyle.sheet.border,
                                        divider: HUDRowStyle.sheet.divider,
                                        minHeight: 48, verticalPadding: 8)

private struct MarketRegionList: View {
    let preference: MarketRegionPreference
    let onSelect: (_ regionID: Int64, _ hubSystemID: Int64?) -> Void

    @LiteQuery private var all: [MarketRegionRow]
    @LiteQuery private var hubSystems: [MarketSystemRow]
    @LiteQuery private var recent: [MarketRegionRow]

    init(preference: MarketRegionPreference, onSelect: @escaping (_ regionID: Int64, _ hubSystemID: Int64?) -> Void) {
        self.preference = preference
        self.onSelect = onSelect
        _all = LiteQuery(MarketBrowser.regions())
        let hubIDs = MarketRegionPreference.tradeHubs.map(\.solarSystemID) + preference.userHubSystemIDs
        _hubSystems = LiteQuery(MarketBrowser.systems(hubIDs.map(MarketFormat.systemID)))
        _recent = LiteQuery(preference.recentRegionIDs.isEmpty
            ? nil : MarketBrowser.regions(preference.recentRegionIDs.map(MarketFormat.regionID)))
    }

    var body: some View {
        let current = preference.regionID
        let currentHub = preference.hubSystemID(forRegion: current)
        let systems = Dictionary(hubSystems.map { (Int64($0.id.rawValue), $0) }, uniquingKeysWith: { first, _ in first })
        let names = Dictionary(recent.map { (Int64($0.id.rawValue), $0.name) }, uniquingKeysWith: { first, _ in first })
        let recentIDs = preference.recentRegionIDs.filter { names[$0] != nil }
        // The player's hubs right after the built-in ones; a system the static data lacks is skipped.
        let userHubs = preference.userHubSystemIDs.compactMap { systems[$0] }

        HUDList(isTransparent: true) {
            HUDListSection("Trade Hubs") {
                ForEach(MarketRegionPreference.tradeHubs) { hub in
                    let system = systems[hub.solarSystemID]
                    MarketRegionRowButton(name: system?.regionName ?? "—", system: system,
                                          isCurrent: hub.regionID == current && hub.solarSystemID == currentHub) {
                        onSelect(hub.regionID, hub.solarSystemID)
                    }
                }
                ForEach(userHubs) { system in
                    let regionID = Int64(system.regionID.rawValue)
                    let systemID = Int64(system.id.rawValue)
                    MarketRegionRowButton(name: system.regionName, system: system,
                                          isCurrent: regionID == current && systemID == currentHub) {
                        onSelect(regionID, systemID)
                    }
                }
            }

            if !recentIDs.isEmpty {
                HUDListSection("Recent") {
                    ForEach(recentIDs, id: \.self) { id in
                        MarketRegionRowButton(name: names[id] ?? "—", system: nil, isCurrent: id == current) {
                            onSelect(id, nil)
                        }
                    }
                }
            }

            HUDListSection(all, row: { region in
                let id = Int64(region.id.rawValue)
                MarketRegionRowButton(name: region.name, system: nil, isCurrent: id == current) { onSelect(id, nil) }
            }, header: {
                HUDSectionHeader(Text("All Regions · \(all.count)"))
            })

            Section {
                HUDFootnote("Neocom remembers the region you pick and uses it on every item's price. Search finds a region by any of its systems.")
                    .hudBareRow()
            }
        }
    }
}

private struct MarketRegionSearchResults: View {
    let searchText: String
    let currentRegionID: Int64
    let onSelect: (Int64) -> Void

    @LiteQuery private var regions: [MarketRegionRow]
    @LiteQuery private var systems: [MarketSystemRow]

    init(pattern: FTS5Pattern?, searchText: String, currentRegionID: Int64, onSelect: @escaping (Int64) -> Void) {
        self.searchText = searchText
        self.currentRegionID = currentRegionID
        self.onSelect = onSelect
        _regions = LiteQuery(pattern.map { MarketBrowser.searchRegions($0) })
        _systems = LiteQuery(pattern.map { MarketBrowser.searchSystems($0) })
    }

    var body: some View {
        if regions.isEmpty, systems.isEmpty {
            ContentUnavailableView.search(text: searchText)
        } else {
            HUDList(isTransparent: true) {
                if !regions.isEmpty {
                    HUDListSection(regions, row: { region in
                        let id = Int64(region.id.rawValue)
                        MarketRegionRowButton(name: region.name, system: nil, isCurrent: id == currentRegionID) {
                            onSelect(id)
                        }
                    }, header: {
                        HUDSectionHeader(Text("Regions"))
                    })
                }
                if !systems.isEmpty {
                    HUDListSection(systems, row: { system in
                        let id = Int64(system.regionID.rawValue)
                        MarketRegionRowButton(name: system.regionName, system: system,
                                              isCurrent: id == currentRegionID) { onSelect(id) }
                    }, header: {
                        HUDSectionHeader(Text("Systems"))
                    })
                }
            }
        }
    }
}

/// A region to pick: its name and, under it, the system that brought it up (hub or search hit)
/// with its security. The current region has a checkmark.
private struct MarketRegionRowButton: View {
    let name: String
    let system: MarketSystemRow?
    let isCurrent: Bool
    let action: () -> Void

    var body: some View {
        let style = system == nil ? sheetRowStyle : with(sheetRowStyle) { $0.minHeight = 56 }
        Button(action: action) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: name)
                        .font(HUDFont.display(15, weight: .semibold, relativeTo: .body))
                    if let system {
                        let security = Text(verbatim: SecurityStatus.string(system.securityStatus))
                            .foregroundStyle(SecurityStatus.color(system.securityStatus))
                        Text("\(Text(verbatim: system.name.uppercased())) \(security)")
                            .font(HUDFont.mono(11, weight: .regular, relativeTo: .caption))
                            .foregroundStyle(Color.hudInkMuted)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if isCurrent {
                    Image(systemName: "checkmark")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Color.hudAccent)
                        .accessibilityHidden(true)
                }
            }
            .hudRow(style)
        }
        .hudRowButton(style)
        .accessibilityAddTraits(isCurrent ? .isSelected : [])
    }

    private func with(_ style: HUDRowStyle, _ change: (inout HUDRowStyle) -> Void) -> HUDRowStyle {
        var style = style
        change(&style)
        return style
    }
}
