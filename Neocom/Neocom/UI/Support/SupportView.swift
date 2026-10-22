import StoreKit
import SwiftUI

/// Support Neocom: what tipping is for, the tips themselves, and the two free ways to help, a
/// review and a share.
///
/// The tips come from `TipJar`; the confirmation is the system StoreKit sheet. After a tip the
/// tiles give way to the thank-you card for as long as the screen is open.
struct SupportView: View {
    @Environment(TipJar.self) private var tipJar
    @Environment(\.purchase) private var purchase
    @Environment(\.openURL) private var openURL

    /// The chosen tip's product id, from the tiles or the More menu.
    @State private var selectedID: String?
    @State private var isThanked = false
    /// The quiet line under the Tip button after the last attempt, if it has one to say.
    @State private var note: Note?

    private enum Note {
        case failed
        case pending
    }

    var body: some View {
        HUDList {
            Section {
                intro.hudBareRow()
            }

            Section {
                tipBlock.hudBareRow()
            } header: {
                HUDSectionHeader("Tip · App Store").hudListHeader()
            }

            HUDListSection {
                Button {
                    openURL(TipConfiguration.reviewURL)
                } label: {
                    HUDLinkRowLabel(systemImage: "star", title: Text("Rate on the App Store"))
                }
                .hudRowButton()
                ShareLink(item: TipConfiguration.shareURL) {
                    HUDLinkRowLabel(systemImage: "square.and.arrow.up", title: Text("Share Neocom"))
                }
                .hudRowButton()
            }

            Section {
                HUDFootnote("Neocom stays free. Nothing is unlocked by tipping.", alignment: .center)
                    .hudBareRow()
            }
        }
        .navigationTitle(MainMenuSection.support.title)
        .navigationBarTitleDisplayMode(.inline)
        .task { await tipJar.loadIfNeeded() }
    }

    // MARK: Intro

    private var intro: some View {
        HUDPanel {
            VStack(alignment: .leading, spacing: 12) {
                Image(systemName: "heart")
                    .font(.system(size: 24))
                    .foregroundStyle(Color.hudAccent)
                    .accessibilityHidden(true)
                Text("Neocom is free, with no ads and nothing to buy. If it is useful to you, you can leave a tip. It is entirely optional, and nothing in the app changes either way.")
                    .font(.hudBody)
                    .foregroundStyle(Color.hudInk)
                Text("Tips pay for development time and for keeping the item database current with each game update.")
                    .font(.hudBody)
                    .foregroundStyle(Color.hudInkBodyMuted)
            }
            .lineSpacing(2)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.vertical, 18)
            .padding(.horizontal, HUDMetrics.gutter)
        }
    }

    // MARK: Tips

    @ViewBuilder private var tipBlock: some View {
        if isThanked {
            thanks
        } else if tipJar.availability == .unavailable {
            HUDEmptyPanel(title: Text("Tips Unavailable"),
                          message: Text("The App Store can't be reached right now. Everything in Neocom works without it.")) {
                Button {
                    Task { await tipJar.load() }
                } label: {
                    Label("Try Again", systemImage: "arrow.clockwise")
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.hudAccent)
                }
                .buttonStyle(.glass)
            }
        } else {
            VStack(spacing: HUDMetrics.headerSpacing) {
                tiles
                tipButton
                switch note {
                case .failed:
                    HUDFootnote("The purchase didn't go through. You weren't charged.", alignment: .center)
                case .pending:
                    HUDFootnote("Your tip is waiting for approval. It goes through once it's approved.", alignment: .center)
                case nil:
                    EmptyView()
                }
            }
        }
    }

    private var isLoading: Bool { tipJar.availability == .loading }

    private var selectedTip: TipJar.Tip? {
        guard let selectedID else { return nil }
        return (tipJar.tiles + tipJar.more).first { $0.id == selectedID }
    }

    /// One cell of the tile grid.
    private enum TileCell: Identifiable {
        case tip(TipJar.Tip)
        case more
        case placeholder(TipConfiguration.Tier)
        case placeholderMore

        var id: String {
            switch self {
            case let .tip(tip): tip.id
            case .more: "more"
            case let .placeholder(tier): "placeholder-\(tier.productID)"
            case .placeholderMore: "placeholder-more"
            }
        }
    }

    private var tileCells: [TileCell] {
        if isLoading {
            return TipConfiguration.tiles.map { .placeholder($0) } + [.placeholderMore]
        }
        return tipJar.tiles.map { .tip($0) } + (tipJar.more.isEmpty ? [] : [.more])
    }

    /// A plain `Grid`, not a lazy one: a lazy grid inside a list row does not refresh its children
    /// when the store's state changes.
    private var tiles: some View {
        let cells = tileCells
        let rows = stride(from: 0, to: cells.count, by: 2).map { Array(cells[$0..<min($0 + 2, cells.count)]) }
        return Grid(horizontalSpacing: HUDMetrics.headerSpacing, verticalSpacing: HUDMetrics.headerSpacing) {
            ForEach(rows, id: \.first?.id) { row in
                GridRow {
                    ForEach(row) { cell in
                        tileView(cell)
                            .frame(maxWidth: .infinity)
                    }
                    if row.count == 1 {
                        Color.clear.frame(maxWidth: .infinity).gridCellUnsizedAxes(.vertical)
                    }
                }
            }
        }
        .disabled(isLoading || tipJar.isPurchasing)
    }

    @ViewBuilder private func tileView(_ cell: TileCell) -> some View {
        switch cell {
        case let .placeholder(tier):
            // Names and prices are StoreKit's; until they arrive the tiles hold their place.
            HUDChoiceTile(systemImage: tier.systemImage, title: Text("Tip"),
                          value: Text("Loading…"), isPlaceholder: true)
        case .placeholderMore:
            HUDChoiceTile(systemImage: TipConfiguration.moreSystemImage, title: Text("More"),
                          value: Text("Loading…"), isPlaceholder: true, showsMenuIndicator: true)
        case let .tip(tip):
            Button {
                select(tip.id)
            } label: {
                HUDChoiceTile(systemImage: tip.tier.systemImage,
                              title: Text(verbatim: tip.product.displayName),
                              value: Text(verbatim: tip.product.displayPrice),
                              isSelected: tip.id == selectedID)
            }
            .buttonStyle(.hudTile)
        case .more:
            moreTile
        }
    }

    /// The fourth tile: a system menu of the larger tips, `from` the lowest of them until one
    /// is chosen, then that one.
    private var moreTile: some View {
        let chosen = tipJar.more.first { $0.id == selectedID }
        let lowest = tipJar.more.min { $0.product.price < $1.product.price }
        return Menu {
            Section("More amounts") {
                ForEach(tipJar.more) { tip in
                    // A toggle, for the system check mark on the chosen one.
                    Toggle(isOn: Binding(get: { tip.id == selectedID },
                                         set: { if $0 { select(tip.id) } })) {
                        Text(verbatim: tip.product.displayName)
                        Text(verbatim: tip.product.displayPrice)
                    }
                }
            }
        } label: {
            HUDChoiceTile(systemImage: TipConfiguration.moreSystemImage,
                          title: chosen.map { Text(verbatim: $0.product.displayName) } ?? Text("More"),
                          value: chosen.map { Text(verbatim: $0.product.displayPrice) }
                              ?? Text("from \(lowest?.product.displayPrice ?? "")"),
                          isSelected: chosen != nil,
                          showsMenuIndicator: true)
        }
        .menuStyle(.button)
        .buttonStyle(.hudTile)
        .accessibilityLabel(chosen.map { Text(verbatim: $0.product.displayName) } ?? Text("More amounts"))
    }

    private var tipButton: some View {
        let isBusy = tipJar.isPurchasing
        return Button {
            guard let tip = selectedTip else { return }
            Task { await buy(tip) }
        } label: {
            HStack(spacing: 10) {
                if isBusy {
                    ProgressView()
                        .tint(Color.hudOnAccentFill)
                }
                tipButtonTitle
            }
            .frame(maxWidth: .infinity)
        }
        .hudProminentButton()
        .disabled(selectedTip == nil || isLoading)
        // Busy keeps the button's colour, dimmed, rather than greying it out as disabled would.
        .allowsHitTesting(!isBusy)
        .opacity(isBusy ? 0.75 : 1)
    }

    private var tipButtonTitle: Text {
        if isLoading { return Text("Loading Tips…") }
        guard let tip = selectedTip else { return Text("Choose a Tip") }
        return Text("Tip \(tip.product.displayPrice)")
    }

    private var thanks: some View {
        HUDPanel {
            VStack(spacing: 10) {
                Image(systemName: "heart.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(Color.hudAccent)
                    .accessibilityHidden(true)
                Text("Thank You")
                    .font(HUDFont.display(22, weight: .bold, relativeTo: .title2))
                    .tracking(0.5)
                    .textCase(.uppercase)
                Text("Your tip went through. Nothing changes in the app — it was all yours already.")
                    .font(.hudBody)
                    .foregroundStyle(Color.hudInkBodyMuted)
                    .frame(maxWidth: 280)
            }
            .multilineTextAlignment(.center)
            .padding(.vertical, 28)
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: Actions

    private func select(_ id: String) {
        selectedID = id
        note = nil
    }

    private func buy(_ tip: TipJar.Tip) async {
        note = nil
        switch await tipJar.purchase(tip, using: { try await purchase($0) }) {
        case .thanked:
            selectedID = nil
            isThanked = true
        case .cancelled:
            break
        case .pending:
            note = .pending
        case .failed:
            note = .failed
        }
    }
}

#Preview {
    NavigationStack {
        SupportView()
    }
    .environment(TipJar())
}
