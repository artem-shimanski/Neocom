import SDEKit
import SwiftUI

/// A row of tiles to switch between, scrolling sideways when they do not fit: an item icon, a
/// title and a mono caption each, the selected one washed in `accent`. It can end in a dashed
/// `+` tile that adds one more.
///
/// Content, not chrome. Speaks as a tab bar: each tile says whether it is selected, and the strip
/// carries the caller's label.
struct HUDTabStrip<ID: Hashable>: View {
    struct Item: Identifiable {
        var id: ID
        var typeID: TypeID
        var title: Text
        var caption: Text?
    }

    let items: [Item]
    let selection: ID?
    /// What the strip is, for VoiceOver ("Ships"). Not drawn.
    let label: Text
    let onSelect: (ID) -> Void
    /// The trailing `+` tile; `nil` draws none.
    var onAdd: (() -> Void)?
    /// What the `+` tile adds, for VoiceOver ("Add Ship").
    var addLabel: Text = Text("Add")
    var canAdd = true

    static var tileHeight: CGFloat { 54 }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(items) { item in
                        tile(item)
                            .id(item.id)
                    }
                    if let onAdd {
                        addTile(onAdd)
                    }
                }
                .padding(.horizontal, HUDMetrics.gutter)
            }
            .scrollIndicators(.hidden)
            .onChange(of: selection) { _, selection in
                guard let selection else { return }
                withAnimation { proxy.scrollTo(selection, anchor: .center) }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(label)
    }

    private func tile(_ item: Item) -> some View {
        let isSelected = item.id == selection
        let shape = RoundedRectangle(cornerRadius: HUDMetrics.tileRadius, style: .continuous)
        return Button {
            onSelect(item.id)
        } label: {
            HStack(spacing: 9) {
                HUDItemIcon(typeID: item.typeID, size: 36)
                VStack(alignment: .leading, spacing: 2) {
                    item.title
                        .font(HUDFont.display(14, weight: .semibold, relativeTo: .subheadline))
                        .tracking(0.5)
                        .foregroundStyle(Color.hudInk)
                        .lineLimit(1)
                    if let caption = item.caption {
                        caption
                            .font(.hudMicro)
                            .tracking(1)
                            .textCase(.uppercase)
                            .foregroundStyle(isSelected ? Color.hudAccent : Color.hudInkMuted)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: 160, alignment: .leading)
            }
            .padding(.leading, 8)
            .padding(.trailing, 14)
            .frame(height: Self.tileHeight)
            .background(isSelected ? Color.hudAccent.opacity(0.10) : Color.hudSurface, in: shape)
            .overlay {
                shape.strokeBorder(isSelected ? Color.hudAccent.opacity(0.35) : Color.hudLine, lineWidth: 1)
            }
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }

    private func addTile(_ action: @escaping () -> Void) -> some View {
        let shape = RoundedRectangle(cornerRadius: HUDMetrics.tileRadius, style: .continuous)
        return Button(action: action) {
            Image(systemName: "plus")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(canAdd ? Color.hudAccent : Color.hudInkFaint)
                .frame(width: Self.tileHeight, height: Self.tileHeight)
                .overlay {
                    shape.strokeBorder(Color.hudLine, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                }
                .contentShape(shape)
        }
        .buttonStyle(.plain)
        .disabled(!canAdd)
        .accessibilityLabel(addLabel)
    }
}

#Preview("Tab strip") {
    @Previewable @State var selection = 1
    VStack(spacing: 24) {
        HUDTabStrip(
            items: [
                .init(id: 0, typeID: TypeID(rawValue: 626), title: Text(verbatim: "Vexor — drone ratting"),
                      caption: Text(verbatim: "Vexor")),
                .init(id: 1, typeID: TypeID(rawValue: 634), title: Text(verbatim: "Exequror — armor logi"),
                      caption: Text(verbatim: "Exequror")),
                .init(id: 2, typeID: TypeID(rawValue: 627), title: Text(verbatim: "Thorax — blaster brawl"),
                      caption: Text(verbatim: "Thorax")),
            ],
            selection: selection,
            label: Text(verbatim: "Ships"),
            onSelect: { selection = $0 },
            onAdd: {},
            addLabel: Text(verbatim: "Add Ship")
        )
        HUDTabStrip(
            items: [.init(id: 0, typeID: TypeID(rawValue: 626), title: Text(verbatim: "Vexor"), caption: nil)],
            selection: 0,
            label: Text(verbatim: "Ships"),
            onSelect: { _ in },
            onAdd: {},
            canAdd: false
        )
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color.hudBg.ignoresSafeArea())
}
