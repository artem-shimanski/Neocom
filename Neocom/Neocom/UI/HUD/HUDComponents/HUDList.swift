import SwiftUI

/// A scrolling HUD screen built on a standard List: sections are cards — surface blocks bordered
/// in `hudLine`, their rows composing one panel each (see `hudRow`, `HUDListSection`) — stacked
/// `sectionSpacing` apart on the bg colour, inset from the edges by the screen gutter, 8pt under
/// the navigation bar and 24pt clear of the bottom.
///
/// The gaps come from the List itself, so they hold only if a screen keeps to its structure:
///
/// - **Every block is its own `Section`** — a titled card, an untitled card, a bare panel, an
///   empty state. `sectionSpacing` is the gap *between sections*; rows put straight into the
///   List, or two blocks put into one Section, stack with no gap at all and read as one card.
/// - A card is a `HUDListSection` (or a `Section` whose rows are `hudRow`s, placed by hand);
///   its header and footnote go in the section's own `header:` / `footer:` slots —
///   `HUDListSection` places them, a bare `Section` takes `.hudListHeader()` /
///   `.hudListFooter()` on them. Never a header or a footnote as a row: it would get no
///   spacing to its card and would be cut as a card row.
/// - A block that is not a card — a `HUDPanel`, `HUDEmptyPanel`, a tile grid — is the one row
///   of a plain `Section`, marked `hudBareRow()`.
/// - A `Button` / `NavigationLink` row keeps `hudRow` in its label and takes `hudRowButton()`
///   (not `.buttonStyle(.hudRow)`) on itself: the List reads the card cell only off the row's
///   outermost view. The system disclosure indicator is hidden here, once, for every link.
///
/// Spacing is exact because of three settings below: the default vertical section margins are
/// left alone (zeroing them with `listSectionMargins(.vertical, 0)` also zeroes
/// `listSectionSpacing`, collapsing the gaps to ~2pt), the minimum header height is zero (the
/// grouped style's default pads a 24pt header out by ~1.5pt on each side), and the top and
/// bottom insets are content margins rather than spacer rows.
struct HUDList<Content: View>: View {
    /// Leave the list's own background clear, for a list that sits on a system material (a sheet)
    /// and must not paint over it. The ink and tint still apply.
    var isTransparent = false
    /// Let the cards take the whole width on Mac instead of stopping at
    /// `HUDMetrics.maxReadableWidth`: for a working surface laid out next to other columns (the
    /// fit editor beside its stats), where the width is the point rather than a long line to read.
    var fillsWidth = false
    @ViewBuilder var content: Content

    init(isTransparent: Bool = false, fillsWidth: Bool = false, @ViewBuilder content: () -> Content) {
        self.isTransparent = isTransparent
        self.fillsWidth = fillsWidth
        self.content = content()
    }

    #if targetEnvironment(macCatalyst)
    /// The list's own width, for the side margins below.
    @State private var width: CGFloat = 0
    #endif

    var body: some View {
        List {
            content
                .listSectionMargins(.horizontal, horizontalMargin)
                .modifier(HUDListSectionSeparators())
                .navigationLinkIndicatorVisibility(.hidden)
        }
        #if targetEnvironment(macCatalyst)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        #endif
        .listStyle(.grouped)
        .listSectionSpacing(HUDMetrics.sectionSpacing)
        .contentMargins(.top, 8, for: .scrollContent)
        .contentMargins(.bottom, 24, for: .scrollContent)
        .scrollContentBackground(.hidden)
        .background {
            if !isTransparent { Color.hudBg.ignoresSafeArea() }
        }
        .foregroundStyle(Color.hudInk)
        .tint(Color.hudAccent)
        .environment(\.defaultMinListRowHeight, 10)
        .environment(\.defaultMinListHeaderHeight, 0)
        .environment(\.hudListIsTransparent, isTransparent)
    }

    /// The gutter, and on Mac — where a window can be as wide as the display — whatever more it
    /// takes to keep the cards `HUDMetrics.maxReadableWidth` wide, centred in the column.
    private var horizontalMargin: CGFloat {
        #if targetEnvironment(macCatalyst)
        fillsWidth ? HUDMetrics.gutter : max(HUDMetrics.gutter, (width - HUDMetrics.maxReadableWidth) / 2)
        #else
        HUDMetrics.gutter
        #endif
    }
}

/// The background of a section header or footer of a `HUDList`.
///
/// On Mac the list can give its headers and footers a system grey backing that
/// `scrollContentBackground(.hidden)` does not remove. They get the screen's own background
/// instead (clear on a transparent list, which sits on a material); iOS is unchanged.
private struct HUDListHeaderFooterBackground: ViewModifier {
    @Environment(\.hudListIsTransparent) private var isTransparent

    func body(content: Content) -> some View {
        #if targetEnvironment(macCatalyst)
        content
            .listRowBackground(isTransparent ? Color.clear : Color.hudBg)
            .listRowSeparator(.hidden)
        #else
        content
        #endif
    }
}

/// The system's own section separators, hidden on Mac.
///
/// The Mac list keeps a full-width separator (the system separator colour, not `hudLine`) at
/// the edges of a section once its sections change after the first layout. The cards draw their
/// own borders and the headers their own rule, so the separators are hidden; iOS draws none.
private struct HUDListSectionSeparators: ViewModifier {
    func body(content: Content) -> some View {
        #if targetEnvironment(macCatalyst)
        content.listSectionSeparator(.hidden)
        #else
        content
        #endif
    }
}

extension EnvironmentValues {
    /// Whether the `HUDList` around a view leaves its background clear (`isTransparent`).
    @Entry var hudListIsTransparent = false
}

/// One card of a `HUDList`: a `Section` whose rows (`hudRow`) are told where they sit in it, so
/// the first rounds and borders the card's top, the last its bottom, and every row but the first
/// draws the divider above it. A `HUDSectionHeader` goes above the card, a footnote below it.
///
/// The `@ViewBuilder` form resolves its rows with `Group(subviews:)`: a `ForEach` among them is
/// flattened into one subview per element, and a row that resolves to nothing (`if false`,
/// `EmptyView`) takes no position. For a section of thousands of rows use the data form, which
/// works the position out per element without resolving the rows up front.
///
/// A block that heads the card but is not one of its rows — the panel of the skill in training
/// over the rest of the queue, a segmented picker over the rows it filters — goes first among
/// the rows as a `hudLeadingBlock()`. It takes no position (the card still starts at the row
/// after it, rounded and with no divider) and stands `headerSpacing` above the card, so the
/// header, the block and the card read as one titled section rather than two sections
/// `sectionSpacing` apart. Only at the start: a bare row between two card rows would split the
/// card without cutting it.
struct HUDListSection<Content: View, Header: View, Footer: View>: View {
    private let content: Content
    private let header: Header
    private let footer: Footer

    var body: some View {
        Section {
            content
        } header: {
            if Header.self != EmptyView.self {
                header.hudListHeader()
            }
        } footer: {
            if Footer.self != EmptyView.self {
                footer.hudListFooter()
            }
        }
    }
}

extension HUDListSection {
    init<Rows: View>(
        @ViewBuilder content: () -> Rows,
        @ViewBuilder header: () -> Header,
        @ViewBuilder footer: () -> Footer
    ) where Content == HUDPositionedRows<Rows> {
        self.content = HUDPositionedRows(rows: content())
        self.header = header()
        self.footer = footer()
    }

    init<Rows: View>(
        @ViewBuilder content: () -> Rows,
        @ViewBuilder header: () -> Header
    ) where Content == HUDPositionedRows<Rows>, Footer == EmptyView {
        self.init(content: content, header: header, footer: { EmptyView() })
    }

    /// A card under a plain titled header, with a footnote under it.
    init<Rows: View>(
        _ title: Text,
        @ViewBuilder content: () -> Rows,
        @ViewBuilder footer: () -> Footer
    ) where Content == HUDPositionedRows<Rows>, Header == HUDSectionHeader<EmptyView> {
        self.init(content: content, header: { HUDSectionHeader(title) }, footer: footer)
    }

    init<Rows: View>(
        _ title: LocalizedStringKey,
        @ViewBuilder content: () -> Rows,
        @ViewBuilder footer: () -> Footer
    ) where Content == HUDPositionedRows<Rows>, Header == HUDSectionHeader<EmptyView> {
        self.init(Text(title), content: content, footer: footer)
    }
}

extension HUDListSection where Footer == EmptyView {
    init<Rows: View>(
        _ title: Text,
        @ViewBuilder content: () -> Rows
    ) where Content == HUDPositionedRows<Rows>, Header == HUDSectionHeader<EmptyView> {
        self.init(title, content: content, footer: { EmptyView() })
    }

    init<Rows: View>(
        _ title: LocalizedStringKey,
        @ViewBuilder content: () -> Rows
    ) where Content == HUDPositionedRows<Rows>, Header == HUDSectionHeader<EmptyView> {
        self.init(Text(title), content: content)
    }
}

extension HUDListSection where Header == EmptyView {
    init<Rows: View>(
        @ViewBuilder content: () -> Rows,
        @ViewBuilder footer: () -> Footer
    ) where Content == HUDPositionedRows<Rows> {
        self.init(content: content, header: { EmptyView() }, footer: footer)
    }
}

extension HUDListSection where Header == EmptyView, Footer == EmptyView {
    /// An untitled card.
    init<Rows: View>(@ViewBuilder content: () -> Rows) where Content == HUDPositionedRows<Rows> {
        self.init(content: content, header: { EmptyView() }, footer: { EmptyView() })
    }
}

// MARK: - Data-driven

extension HUDListSection {
    /// A card of one row per element, for sections thousands of rows long: the position comes
    /// from comparing each element's id with the first and last one's, so the rows stay as lazy
    /// as a plain `ForEach` in a List. `row` returns the row itself, `hudRow` applied.
    init<Data: RandomAccessCollection, ID: Hashable, Row: View>(
        _ data: Data,
        id: KeyPath<Data.Element, ID>,
        @ViewBuilder row: @escaping (Data.Element) -> Row,
        @ViewBuilder header: () -> Header,
        @ViewBuilder footer: () -> Footer
    ) where Content == HUDDataRows<Data, ID, Row> {
        self.content = HUDDataRows(data: data, id: id, row: row)
        self.header = header()
        self.footer = footer()
    }

    init<Data: RandomAccessCollection, Row: View>(
        _ data: Data,
        @ViewBuilder row: @escaping (Data.Element) -> Row,
        @ViewBuilder header: () -> Header,
        @ViewBuilder footer: () -> Footer
    ) where Data.Element: Identifiable, Content == HUDDataRows<Data, Data.Element.ID, Row> {
        self.init(data, id: \.id, row: row, header: header, footer: footer)
    }
}

extension HUDListSection where Footer == EmptyView {
    init<Data: RandomAccessCollection, ID: Hashable, Row: View>(
        _ data: Data,
        id: KeyPath<Data.Element, ID>,
        @ViewBuilder row: @escaping (Data.Element) -> Row,
        @ViewBuilder header: () -> Header
    ) where Content == HUDDataRows<Data, ID, Row> {
        self.init(data, id: id, row: row, header: header, footer: { EmptyView() })
    }

    init<Data: RandomAccessCollection, Row: View>(
        _ data: Data,
        @ViewBuilder row: @escaping (Data.Element) -> Row,
        @ViewBuilder header: () -> Header
    ) where Data.Element: Identifiable, Content == HUDDataRows<Data, Data.Element.ID, Row> {
        self.init(data, id: \.id, row: row, header: header, footer: { EmptyView() })
    }
}

extension HUDListSection where Header == EmptyView, Footer == EmptyView {
    init<Data: RandomAccessCollection, ID: Hashable, Row: View>(
        _ data: Data,
        id: KeyPath<Data.Element, ID>,
        @ViewBuilder row: @escaping (Data.Element) -> Row
    ) where Content == HUDDataRows<Data, ID, Row> {
        self.init(data, id: id, row: row, header: { EmptyView() }, footer: { EmptyView() })
    }

    init<Data: RandomAccessCollection, Row: View>(
        _ data: Data,
        @ViewBuilder row: @escaping (Data.Element) -> Row
    ) where Data.Element: Identifiable, Content == HUDDataRows<Data, Data.Element.ID, Row> {
        self.init(data, id: \.id, row: row, header: { EmptyView() }, footer: { EmptyView() })
    }
}

/// The rows of a `@ViewBuilder` `HUDListSection`, each told its position in the card.
///
/// Only the card rows — the subviews that carry a `hudRow` / `hudRowCell` — are counted: a
/// `hudBareRow()` among them takes no position and is passed through as is.
struct HUDPositionedRows<Rows: View>: View {
    var rows: Rows

    var body: some View {
        Group(subviews: rows.environment(\.hudRowPlacementIsDeferred, true)) { subviews in
            let cardRows = subviews.indices.filter { subviews[$0].containerValues.hudRowStyle != nil }
            ForEach(subviews.indices, id: \.self) { index in
                if let rank = cardRows.firstIndex(of: index) {
                    subviews[index].hudRowPosition(HUDRowPosition(index: rank, count: cardRows.count))
                } else {
                    subviews[index]
                }
            }
        }
    }
}

/// The rows of a data-driven `HUDListSection`, each told its position in the card.
struct HUDDataRows<Data: RandomAccessCollection, ID: Hashable, Row: View>: View {
    var data: Data
    var id: KeyPath<Data.Element, ID>
    var row: (Data.Element) -> Row

    var body: some View {
        let firstID = data.first?[keyPath: id]
        let lastID = data.last?[keyPath: id]
        ForEach(data, id: id) { element in
            let elementID = element[keyPath: id]
            row(element)
                .environment(\.hudRowPosition,
                             HUDRowPosition(isFirst: elementID == firstID, isLast: elementID == lastID))
        }
    }
}

extension View {
    /// A row that is not part of a panel card — an empty state, a tile, a block with its own
    /// frame: the screen's bg shows through, no divider above or below, and no row insets, so it
    /// lines up with the cards around it.
    func hudBareRow() -> some View {
        self
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
    }

    /// A bare row that leads a `HUDListSection`'s card, `headerSpacing` above its first row:
    /// see `HUDListSection`. Pass `hasCardBelow: false` when the card under it has no rows, so
    /// the gap does not hang under the block on its own.
    func hudLeadingBlock(hasCardBelow: Bool = true) -> some View {
        self
            .padding(.bottom, hasCardBelow ? HUDMetrics.headerSpacing : 0)
            .hudBareRow()
    }

    /// Places a `HUDSectionHeader` in a `Section`'s native `header:` slot: `headerSpacing` above
    /// the card. The header's own 4pt face inset is all the horizontal offset it needs — the list
    /// lays headers out on the section margins, the same edge as the card. `HUDListSection` applies
    /// this itself.
    func hudListHeader() -> some View {
        self
            .padding(.bottom, HUDMetrics.headerSpacing)
            .listRowInsets(EdgeInsets())
            .modifier(HUDListHeaderFooterBackground())
    }

    /// Places a footnote (`HUDFootnote`, which carries its own 4pt face inset) in a `Section`'s
    /// native `footer:` slot: `headerSpacing` below the card, on the card's edge.
    /// `HUDListSection` applies this itself.
    func hudListFooter() -> some View {
        self
            .padding(.top, HUDMetrics.headerSpacing)
            .listRowInsets(EdgeInsets())
            .modifier(HUDListHeaderFooterBackground())
    }

    /// The screen background behind everything, with the content layer's ink and tint. For the
    /// screens that are not a `HUDList` — a sheet body, an empty state, a picker of tiles.
    func hudScreen() -> some View {
        self
            .scrollContentBackground(.hidden)
            .background(Color.hudBg.ignoresSafeArea())
            .foregroundStyle(Color.hudInk)
            .tint(Color.hudAccent)
    }
}

private struct PreviewItem: Identifiable {
    let id: Int
    var name: String
}

#Preview("List") {
    let items = (1...5).map { PreviewItem(id: $0, name: "Item \($0)") }
    let showsOptional = false

    HUDList {
        HUDListSection("Overview") {
            Text(verbatim: "First row").hudRow()
            Text(verbatim: "Second row").hudRow()
            if showsOptional {
                Text(verbatim: "A row that resolves to nothing takes no position").hudRow()
            }
            Text(verbatim: "Third row").hudRow()
        }

        HUDListSection {
            Text(verbatim: "An untitled single-row card.").hudRow()
        }

        HUDListSection("ForEach") {
            Text(verbatim: "A fixed row before the ForEach").hudRow()
            ForEach(items) { item in
                Text(verbatim: item.name).hudRow()
            }
        }

        HUDListSection(items, row: { item in
            Text(verbatim: "Data-driven · \(item.name)").hudRow()
        }, header: {
            HUDSectionHeader(Text("Data · \(items.count)"))
        })

        HUDListSection {
            Text(verbatim: "Hull").hudRow()
            Text(verbatim: "Armor").hudRow()
        } header: {
            HUDSectionHeader(Text("High")) {
                HStack(spacing: 6) {
                    Text(verbatim: "4/4")
                    Text(verbatim: "·")
                    Text(verbatim: "Turrets 1/0").foregroundStyle(Color.hudDanger)
                }
            }
        } footer: {
            HUDFootnote("A footnote under the card.")
        }
    }
}

#Preview("Spacing") {
    NavigationStack {
        HUDList {
            HUDListSection("Titled") {
                Text(verbatim: "Titled card").hudRow()
                Text(verbatim: "Second row").hudRow()
            }

            HUDListSection {
                Text(verbatim: "Untitled card").hudRow()
            }

            HUDListSection("With footnote") {
                Text(verbatim: "Card with a footnote").hudRow()
            } footer: {
                HUDFootnote("A footnote, 10pt under its card.")
            }

            Section {
                HUDPanel {
                    Text(verbatim: "A bare panel").hudRow()
                }
                .hudBareRow()
            }

            HUDListSection("Leading block") {
                Picker(selection: .constant(1)) {
                    Text(verbatim: "I").tag(0)
                    Text(verbatim: "II").tag(1)
                } label: {
                    Text(verbatim: "Grade")
                }
                .pickerStyle(.segmented)
                .hudLeadingBlock()
                Text(verbatim: "The card, 10pt under the block").hudRow()
                Text(verbatim: "Second row").hudRow()
            }

            HUDListSection("Links") {
                NavigationLink {
                    Text(verbatim: "Destination")
                } label: {
                    HStack {
                        Text(verbatim: "NavigationLink row")
                        Spacer()
                        HUDChevron()
                    }
                    .hudRow()
                }
                .hudRowButton()
                Button {} label: {
                    HStack {
                        Text(verbatim: "Button row")
                        Spacer()
                        HUDChevron()
                    }
                    .hudRow()
                }
                .hudRowButton()
            }

            HUDListSection("Last") {
                Text(verbatim: "Last card").hudRow()
            }
        }
        .navigationTitle("Spacing")
        .navigationBarTitleDisplayMode(.inline)
    }
}
