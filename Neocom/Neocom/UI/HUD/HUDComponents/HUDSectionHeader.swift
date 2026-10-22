import SwiftUI

/// A mono label followed by a rule, and after the rule whatever the section has to say about
/// itself — figures against a budget, a count. The rule runs to the trailing content or, with
/// none, to the edge.
///
/// It carries its own face inset (`headerFaceInset`, 4pt in from the card's edge) wherever it is
/// used. In a `HUDList` it goes above a card — `HUDListSection` places it, or a bare `Section`'s
/// `header:` behind `.hudListHeader()`, which adds only the spacing to the card.
///
/// The trailing slot is set in the header's own face (mono caps, `ink-muted`, one line); what
/// goes in it colours its own spans, so each figure can turn `danger` on its own.
struct HUDSectionHeader<Trailing: View>: View {
    let title: Text
    @ViewBuilder var trailing: Trailing
    /// `.uppercase` unless the title carries a unit that upper-casing would change — `5 m³` is
    /// not `5 M³` — in which case the caller writes the caps itself and passes `nil`.
    var titleCase: Text.Case? = .uppercase

    init(_ title: Text, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: 10) {
            title
                .font(.hudLabel)
                .tracking(2)
                .textCase(titleCase)
                .foregroundStyle(Color.hudInkMuted)
                .lineLimit(1)
                .accessibilityAddTraits(.isHeader)
            Rectangle()
                .fill(Color.hudLine)
                .frame(height: 1)
                // Last in line for width: a stack hands every flexible child an equal share
                // first, so a rule that asked as much as the title cut a long one short
                // ("USED BY THIS FIT…") with room to spare.
                .layoutPriority(-1)
            trailing
                .font(.hudLabel)
                .tracking(1)
                .textCase(.uppercase)
                .foregroundStyle(Color.hudInkMuted)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .layoutPriority(1)
        }
        .padding(.horizontal, HUDMetrics.headerFaceInset)
    }
}

extension HUDSectionHeader {
    /// The same header with its title's case set, for the one that is not upper-cased.
    func withTitleCase(_ titleCase: Text.Case?) -> Self {
        var copy = self
        copy.titleCase = titleCase
        return copy
    }
}

extension HUDSectionHeader where Trailing == EmptyView {
    init(_ title: Text) { self.init(title, trailing: { EmptyView() }) }
    init(_ title: LocalizedStringKey) { self.init(Text(title)) }
    init(verbatim title: String) { self.init(Text(verbatim: title)) }
}

#Preview("Section header") {
    HUDList {
        Section {
            Text(verbatim: "First row").hudRow()
            Text(verbatim: "Second row").hudRow()
        } header: {
            HUDSectionHeader(Text("High")) {
                HStack(spacing: 6) {
                    Text(verbatim: "4/4")
                    Text(verbatim: "·")
                    Text(verbatim: "Turrets 1/0").foregroundStyle(Color.hudDanger)
                    Text(verbatim: "·")
                    Text(verbatim: "Launchers 1/2")
                }
            }
            .hudListHeader()
        }

        Section {
            Text(verbatim: "A row under a plain header.").hudRow()
        } header: {
            HUDSectionHeader("Rigs").hudListHeader()
        }

        Section {
            Text(verbatim: "A row under an un-cased title.").hudRow()
        } header: {
            HUDSectionHeader(verbatim: "Cargo 5 m³").withTitleCase(nil).hudListHeader()
        }
    }
}
