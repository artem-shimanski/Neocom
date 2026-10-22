import AssetsKit
import LiteRowUI
import SDEKit
import SwiftUI

/// The Assets section: everything the character owns, by region and location, with a search
/// across every hangar, ship and container. Every pushed screen reads the same `AssetsModel`
/// through `AssetsRoute`.
struct AssetsView: View {
    var body: some View {
        SDESectionView { database in
            AssetsBody(database: database)
        }
        .hudScreen()
        .navigationTitle("Assets")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct AssetsBody: View {
    let database: SDEDatabase

    @Environment(AccountStore.self) private var accounts

    var body: some View {
        if let sheet = accounts.currentAssets {
            AssetsScreen(sheet: sheet, database: database, characterSheet: accounts.currentSheet)
                // Another character gets its own model.
                .id(ObjectIdentifier(sheet))
        }
    }
}

enum AssetsRoute: Hashable {
    /// A root location: a station, a structure, a system, or a place nobody could name.
    case location(Int64)
    /// A ship or a container, by item id.
    case item(Int64)

    @ViewBuilder
    func destination(model: AssetsModel, database: SDEDatabase) -> some View {
        switch self {
        case let .location(id):
            AssetsLocationView(model: model, locationID: id)
        case let .item(id):
            AssetsItemView(model: model, database: database, itemID: id)
        }
    }
}

extension View {
    /// What every screen of the section takes: fetch if stale, rebuild the index on snapshot change
    /// (each screen runs its own tasks, as a covered screen has them cancelled), pull to refresh.
    func assetsRefresh(_ model: AssetsModel) -> some View {
        self
            .task { await model.ensureFresh() }
            .task(id: model.revision) { await model.rebuildIfNeeded() }
            .refreshableCommand { await model.refresh() }
    }
}

private struct AssetsScreen: View {
    let database: SDEDatabase
    @State private var model: AssetsModel
    @State private var query = ""

    init(sheet: AssetsSheet, database: SDEDatabase, characterSheet: CharacterSheet?) {
        self.database = database
        _model = State(initialValue: AssetsModel(sheet: sheet, database: database, characterSheet: characterSheet))
    }

    var body: some View {
        AssetsIndexContent(model: model) { index in
            let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                AssetsRootList(model: model, index: index)
            } else {
                AssetsSearchView(model: model, index: index, query: trimmed)
            }
        }
        .assetsRefresh(model)
        .searchable(text: $query, prompt: Text("Item, station or system"))
        .navigationDestination(for: AssetsRoute.self) { route in
            route.destination(model: model, database: database)
                .liteDatabase(database.database)
        }
    }
}

/// The index when there is one; otherwise the fetch's progress, the failure with a retry, or a
/// spinner while the index builds. Once an index exists it stays through every refresh.
struct AssetsIndexContent<Content: View>: View {
    let model: AssetsModel
    @ViewBuilder var content: (AssetIndex) -> Content

    var body: some View {
        if let index = model.index {
            content(index)
        } else {
            HUDList {
                Section {
                    placeholder.hudBareRow()
                }
            }
        }
    }

    @ViewBuilder private var placeholder: some View {
        if let error = model.buildError {
            HUDEmptyPanel(title: Text("Assets Unavailable"), message: Text(error.localizedDescription)) {
                Button("Retry") {
                    Task { await model.refresh() }
                }
                .hudProminentButton()
            }
        } else if model.sheet.value == nil, case let .failed(error) = model.state {
            HUDEmptyPanel(title: Text("Assets Unavailable"), message: Text(error.localizedDescription)) {
                Button("Retry") {
                    Task { await model.refresh() }
                }
                .hudProminentButton()
            }
        } else {
            AssetsLoadingPanel(isFetching: model.sheet.value == nil, progress: model.progress)
        }
    }
}

/// Progress of the first, paged fetch of the assets; once the records are in, the index is being
/// built.
private struct AssetsLoadingPanel: View {
    let isFetching: Bool
    let progress: AssetsLoadProgress?

    var body: some View {
        HUDPanel {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Text(title)
                        .font(.hudLabel)
                        .tracking(2)
                        .textCase(.uppercase)
                        .foregroundStyle(Color.hudInkMuted)
                    Spacer(minLength: 8)
                    if let detail {
                        Text(detail)
                            .font(.hudLabel)
                            .tracking(1)
                            .textCase(.uppercase)
                            .foregroundStyle(Color.hudInkMuted)
                            .monospacedDigit()
                    }
                }
                if isFetching, let progress {
                    ProgressView(value: progress.fraction)
                        .tint(Color.hudAccent)
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                }
                Text("EVE sends the asset list a page at a time. Neocom keeps it, so next time the list opens at once.")
                    .font(.hudCaption)
                    .foregroundStyle(Color.hudInkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(HUDMetrics.gutter)
        }
    }

    private var title: LocalizedStringKey {
        guard isFetching else { return "Sorting assets" }
        switch progress?.phase {
        case .pages, nil: return "Loading assets"
        case .names: return "Reading names"
        case .locations: return "Naming locations"
        }
    }

    private var detail: LocalizedStringKey? {
        guard isFetching, let progress, progress.phase == .pages else { return nil }
        guard let pageCount = progress.pageCount else { return nil }
        return "Page \(progress.pagesLoaded) of \(pageCount)"
    }
}

// MARK: - Root list

/// The list itself: the totals, then the locations by region.
struct AssetsRootList: View {
    let model: AssetsModel
    let index: AssetIndex

    var body: some View {
        HUDList {
            Section {
                HUDPanel {
                    HUDStatStrip(items: [
                        .init(id: 0, label: Text("Locations"), value: Text(verbatim: AssetsFormat.count(index.summary.locations))),
                        .init(id: 1, label: Text("Items"), value: Text(verbatim: AssetsFormat.count(index.summary.items))),
                        .init(id: 2, label: Text("Ships"), value: Text(verbatim: AssetsFormat.quantity(index.summary.ships))),
                        .init(id: 3, label: Text("BPC"), value: Text(verbatim: AssetsFormat.count(index.summary.blueprintCopies))),
                    ])
                }
                .hudBareRow()
            } footer: {
                AssetsStatusLine(model: model)
                    .hudListFooter()
            }

            if index.regions.isEmpty {
                Section {
                    HUDEmptyPanel(title: Text("No Assets"),
                                  message: Text("This character owns nothing EVE lists as an asset."))
                        .hudBareRow()
                }
            }

            ForEach(index.regions) { region in
                HUDListSection(region.locations, row: { location in
                    NavigationLink(value: AssetsRoute.location(location.id)) {
                        AssetsLocationRow(location: location,
                                          isHome: location.id == model.homeLocationID,
                                          isDocked: location.id == model.dockedLocationID)
                    }
                    .hudRowButton(AssetsLocationRow.rowStyle)
                }, header: {
                    HUDSectionHeader(Text(verbatim: "\(region.name ?? String(localized: "Unknown Location")) · \(region.locations.count)"))
                })
            }

            Section {
                HUDFootnote("EVE refreshes the asset list about once an hour. Search finds an item in every hangar, ship and container.")
                    .hudBareRow()
            }
        }
    }
}

/// How fresh the list is, with the state in the dot: fresh, being updated, failed to update.
struct AssetsStatusLine: View {
    let model: AssetsModel

    var body: some View {
        TimelineView(.everyMinute) { context in
            chip(now: context.date)
        }
    }

    @ViewBuilder
    private func chip(now: Date) -> some View {
        Group {
            switch model.state {
            case .loading:
                if let progress = model.progress, progress.phase == .pages, let pageCount = progress.pageCount {
                    HUDStatusChip(text: Text("Updating · page \(progress.pagesLoaded) of \(pageCount)"),
                                  color: .hudInkMuted, mark: .dot, markColor: .hudAccent)
                } else {
                    HUDStatusChip(text: Text("Updating"), color: .hudInkMuted, mark: .dot, markColor: .hudAccent)
                }
            case let .failed(error):
                HUDStatusChip(text: Text(error.localizedDescription), color: .hudDanger,
                              mark: .symbol("exclamationmark.triangle.fill"))
            case .idle:
                if let fetchedAt = model.fetchedAt {
                    let isStale = now.timeIntervalSince(fetchedAt) > 2 * 3600
                    HUDStatusChip(text: Text("Updated \(fetchedAt, format: .relative(presentation: .named))"),
                                  color: .hudInkMuted, mark: .dot, markColor: isStale ? .hudWarn : .hudOk)
                }
            }
        }
        .lineLimit(2)
        .padding(.horizontal, HUDMetrics.headerFaceInset)
    }
}

/// One location of the list: its name, its system and how much is there, and the states worth
/// a glance — docked here, home, ships, no access.
private struct AssetsLocationRow: View {
    static let rowStyle = HUDRowStyle(horizontalPadding: 0, minHeight: 60, verticalPadding: 10)

    let location: AssetLocation
    let isHome: Bool
    let isDocked: Bool

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: location.displayName)
                    .font(.hudBody)
                    .foregroundStyle(Color.hudInk)
                    .multilineTextAlignment(.leading)
                location.listSubtitle
                    .font(HUDFont.mono(11, weight: .regular, relativeTo: .caption))
                    .foregroundStyle(Color.hudInkMuted)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .trailing, spacing: 5) {
                if isDocked {
                    HUDStatusChip(text: Text("Docked"), color: .hudOk, mark: .dot)
                }
                if isHome {
                    Text("Home")
                        .font(.hudMicro)
                        .tracking(1)
                        .textCase(.uppercase)
                        .foregroundStyle(Color.hudInkMuted)
                }
                if location.shipCount > 0 {
                    HUDMetaBadge(text: Text(verbatim: AssetsFormat.ships(location.shipCount)))
                }
                if location.kind == .structureNoAccess {
                    HUDMetaBadge(text: Text("No Access"))
                }
            }
            .fixedSize()
            HUDChevron()
        }
        .padding(.leading, HUDMetrics.gutter)
        .padding(.trailing, 14)
        .hudRow(Self.rowStyle)
    }
}
