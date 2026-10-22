import SwiftUI

/// The label of a card row that leads somewhere or does one thing: an accent icon, the title
/// with an optional mono subtitle, an optional mono value at the trailing edge, and the mark of
/// where it leads. Carries `hudRow` itself; the `Button`, `ShareLink` or `NavigationLink` around
/// it takes `hudRowButton()`. A row with no mark of its own is `HUDIconRow`.
struct HUDLinkRowLabel: View {
    /// Where the row leads, which decides the mark at its end.
    enum Destination {
        /// A screen of the app: the chevron.
        case screen
        /// A page outside the app: the ↗.
        case external
    }

    let systemImage: String?
    let title: Text
    var subtitle: Text?
    var value: Text?
    var destination: Destination = .screen

    init(systemImage: String?, title: Text, subtitle: Text? = nil, value: Text? = nil,
         destination: Destination = .screen) {
        self.systemImage = systemImage
        self.title = title
        self.subtitle = subtitle
        self.value = value
        self.destination = destination
    }

    var body: some View {
        HUDIconRow(systemImage: systemImage, title: title, subtitle: subtitle) {
            if let value {
                value
                    .font(HUDFont.mono(12, weight: .regular, relativeTo: .caption))
                    .foregroundStyle(Color.hudInkMuted)
                    .lineLimit(1)
            }
            switch destination {
            case .screen: HUDChevron()
            case .external: HUDExternalMark()
            }
        }
    }
}

/// One card row of the settings kind: an optional accent icon, the title with an optional
/// mono subtitle, and whatever the row ends with. Carries `hudRow` itself, taller with a
/// subtitle.
///
/// Not a button: a row that is one wraps `HUDLinkRowLabel`. A control inside keeps a
/// non-default style (`.glass`, a `Toggle`), since a `List` row fires every default-styled
/// button it holds on any tap.
struct HUDIconRow<Trailing: View>: View {
    let systemImage: String?
    let title: Text
    var subtitle: Text?
    @ViewBuilder var trailing: Trailing

    init(systemImage: String?, title: Text, subtitle: Text? = nil, @ViewBuilder trailing: () -> Trailing) {
        self.systemImage = systemImage
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: 12) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 20, weight: .regular))
                    .foregroundStyle(Color.hudAccent)
                    .frame(width: 24)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 2) {
                title
                    .font(.hudTileTitle)
                    .tracking(0.3)
                    .foregroundStyle(Color.hudInk)
                if let subtitle {
                    subtitle
                        .font(HUDFont.mono(11, weight: .regular, relativeTo: .caption))
                        .foregroundStyle(Color.hudInkMuted)
                }
            }
            .multilineTextAlignment(.leading)
            Spacer(minLength: 8)
            trailing
        }
        .hudRow(subtitle == nil ? .default : .subtitled)
    }
}

extension HUDRowStyle {
    /// The extra height of a two-line row.
    static let subtitled = HUDRowStyle(minHeight: 56, verticalPadding: 10)
}

extension HUDIconRow where Trailing == EmptyView {
    init(systemImage: String?, title: Text, subtitle: Text? = nil) {
        self.init(systemImage: systemImage, title: title, subtitle: subtitle) { EmptyView() }
    }
}

#Preview("Link row") {
    HUDList {
        HUDListSection {
            Button {} label: {
                HUDLinkRowLabel(systemImage: "star", title: Text(verbatim: "Rate on the App Store"))
            }
            .hudRowButton()
            Button {} label: {
                HUDLinkRowLabel(systemImage: "square.and.arrow.up", title: Text(verbatim: "Share Neocom"))
            }
            .hudRowButton()
        }

        HUDListSection("Settings") {
            Button {} label: {
                HUDLinkRowLabel(systemImage: "map", title: Text(verbatim: "Price Region"),
                                subtitle: Text(verbatim: "Every item's price comes from it"),
                                value: Text(verbatim: "Heimatar"))
            }
            .hudRowButton()
            Button {} label: {
                HUDLinkRowLabel(systemImage: "chevron.left.forwardslash.chevron.right",
                                title: Text(verbatim: "Source Code"),
                                subtitle: Text(verbatim: "github.com"),
                                destination: .external)
            }
            .hudRowButton()
            HUDIconRow(systemImage: "bell", title: Text(verbatim: "Mail"),
                       subtitle: Text(verbatim: "New mail in the inbox")) {
                Toggle(isOn: .constant(true)) { Text(verbatim: "Mail") }
                    .labelsHidden()
            }
        }
    }
}
