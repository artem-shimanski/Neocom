import SwiftUI

/// An uppercase mono state label with an optional dot or glyph in the state colour.
struct HUDStatusChip: View {
    enum Mark {
        case none
        case dot
        case symbol(String)
    }

    let text: Text
    let color: Color
    var mark: Mark = .none
    /// The mark's own colour, when it says something the text does not: the green dot of a
    /// list that is fresh next to a muted `UPDATED 12 MINUTES AGO`. `nil` takes `color`.
    var markColor: Color?

    var body: some View {
        HStack(spacing: 6) {
            switch mark {
            case .none:
                EmptyView()
            case .dot:
                Circle().fill(markColor ?? color).frame(width: 6, height: 6)
            case let .symbol(name):
                Image(systemName: name)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(markColor ?? color)
            }
            text
                .font(.hudLabel)
                .tracking(1)
                .textCase(.uppercase)
        }
        .foregroundStyle(color)
        .accessibilityElement(children: .combine)
    }
}
