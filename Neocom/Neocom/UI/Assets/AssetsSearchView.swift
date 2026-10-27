import AssetsKit
import SDEKit
import SwiftUI

/// The search results in place of the list: a card per location with its hits, totals on top.
/// Matching runs off the main actor after a debounce; the previous results stay up meanwhile.
struct AssetsSearchView: View {
    let model: AssetsModel
    let index: AssetIndex
    let query: String

    /// Hits past this are not looked for.
    nonisolated static let limit = 200

    @State private var results: Results?

    struct Results {
        var query: String
        var locations: [AssetSearchResult]

        var hits: [AssetSearchHit] { locations.flatMap(\.hits) }
        var hitCount: Int { locations.reduce(0) { $0 + $1.hits.count } }
    }

    var body: some View {
        HUDList {
            if let results {
                content(results)
            } else {
                Section {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 32)
                        .hudBareRow()
                }
            }
        }
        .task(id: SearchKey(query: query, revision: model.indexRevision)) {
            // A task cancelled by the next keystroke never searches.
            try? await Task.sleep(for: .milliseconds(results == nil ? 0 : 180))
            guard !Task.isCancelled else { return }
            let index = index
            let query = query
            let found = await Self.search(index, query: query)
            guard !Task.isCancelled else { return }
            results = Results(query: query, locations: found)
        }
    }

    private struct SearchKey: Hashable {
        var query: String
        var revision: Int
    }

    @concurrent
    private static func search(_ index: AssetIndex, query: String) async -> [AssetSearchResult] {
        index.search(query, limit: limit)
    }

    @ViewBuilder
    private func content(_ results: Results) -> some View {
        if results.locations.isEmpty {
            Section {
                HUDEmptyPanel(title: Text("No Matches"),
                              message: Text("Nothing in any hangar, ship or container matches “\(results.query)”."))
                    .hudBareRow()
            }
        } else {
            Section {
                HUDPanel {
                    HUDStatStrip(items: summary(results))
                }
                .hudBareRow()
            }

            ForEach(Array(results.locations.enumerated()), id: \.element.id) { offset, result in
                if offset == 0 {
                    HUDListSection {
                        card(result)
                    } header: {
                        HUDSectionHeader(Text(verbatim: locationsTitle(results.locations.count)))
                    }
                } else {
                    HUDListSection {
                        card(result)
                    }
                }
            }

            Section {
                HUDFootnote(results.hitCount >= Self.limit
                            ? "Only the first \(Self.limit) matches are shown. Add a word to narrow the search."
                            : "Search looks inside hangars, ships and containers. An item fitted to a ship or kept in a container is shown with the ship or container it is in.")
                    .hudBareRow()
            }
        }
    }

    @ViewBuilder
    private func card(_ result: AssetSearchResult) -> some View {
        AssetsPlaceRow(location: result.location, isDocked: result.location.id == model.dockedLocationID)
        ForEach(result.hits) { hit in
            AssetsRowLink(row: hit.row, subtitle: subtitle(of: hit))
        }
    }

    /// `HYBRID WEAPON · IN <PILOT>'S THORAX`, the chain outermost first.
    private func subtitle(of hit: AssetSearchHit) -> String {
        guard !hit.parents.isEmpty else { return hit.row.subtitle }
        let chain = hit.parents.map(\.name).joined(separator: " › ")
        return "\(hit.row.subtitle) · \(String(localized: "assets.search.in", defaultValue: "in \(chain)", comment: "Where a found item sits: the containers it is in, outermost first"))"
    }

    private func locationsTitle(_ count: Int) -> String {
        String(localized: "\(count) Locations")
    }

    /// The total found, and how it splits: assembled and packaged when every hit is a ship —
    /// the question a ship search asks — otherwise the stacks and the places they are in.
    private func summary(_ results: Results) -> [HUDStatStrip.Item] {
        let hits = results.hits
        let total = hits.reduce(Int64(0)) { $0 + $1.row.quantity }
        var items: [HUDStatStrip.Item] = [
            .init(id: 0, label: Text("Total"), value: Text(verbatim: AssetsFormat.quantity(total))),
        ]
        if hits.allSatisfy(\.row.isShipType) {
            let assembled = hits.filter(\.row.isAssembled).reduce(Int64(0)) { $0 + $1.row.quantity }
            items.append(.init(id: 1, label: Text("Assembled"), value: Text(verbatim: AssetsFormat.quantity(assembled))))
            items.append(.init(id: 2, label: Text("Packaged"), value: Text(verbatim: AssetsFormat.quantity(total - assembled))))
        } else {
            items.append(.init(id: 1, label: Text("Stacks"), value: Text(verbatim: AssetsFormat.count(hits.count))))
            items.append(.init(id: 2, label: Text("Locations"), value: Text(verbatim: AssetsFormat.count(results.locations.count))))
        }
        return items
    }
}
