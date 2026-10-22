import SDEKit
import SwiftUI

// MARK: - Action

/// One action a sheet offers: its name, the glyph at the trailing edge of its row, and what it does.
///
/// The action carries no destination; a row that leads somewhere sets the host screen's
/// presentation state.
struct HUDAction {
    /// Plain or destructive; the list draws the difference in ink.
    enum Role {
        case normal
        case destructive

        var ink: Color {
            switch self {
            case .normal: .hudInk
            case .destructive: .hudDanger
            }
        }
    }

    var title: Text
    /// An SF Symbol drawn at the end of the row.
    var systemImage: String
    var role: Role = .normal
    var action: () -> Void

    init(title: Text, systemImage: String, role: Role = .normal, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.role = role
        self.action = action
    }

    init(_ title: LocalizedStringKey, systemImage: String, role: Role = .normal,
         action: @escaping () -> Void) {
        self.init(title: Text(title), systemImage: systemImage, role: role, action: action)
    }
}

// MARK: - Sheet

/// Geometry that callers of `HUDActionSheet` depend on, kept outside the generic type.
enum HUDActionSheetMetrics {
    /// The header's icon plate.
    static let iconSize: CGFloat = 44
}

/// The body of a sheet that names one thing in a fit and offers what can be done to it.
///
/// Content, not a sheet: the grabber, the shape and the close button stay system, so the host
/// presents it with `.sheet` and a toolbar action. Only the header stays put; `content` and the
/// action `groups` scroll together.
///
/// `content` goes into the sheet's `HUDList` as is: a card is a `HUDListSection`, a bare block
/// is the one `hudBareRow()` of a plain `Section`.
struct HUDActionSheet<Icon: View, Content: View>: View {
    let title: Text
    /// One mono line under the name, composed by the caller.
    var subtitle: Text?
    var groups: [[HUDAction]]
    /// The subject's picture, a `HUDItemIcon` at `HUDActionSheetMetrics.iconSize`.
    @ViewBuilder var icon: Icon
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) {
            header
            HUDList(isTransparent: true) {
                content
                HUDActionList(groups: groups)
            }
        }
        .foregroundStyle(Color.hudInk)
        .tint(Color.hudAccent)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            icon
            HUDRowTitle(title: title, subtitle: subtitle, font: .hudTileTitle)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, HUDMetrics.gutter)
        .padding(.vertical, HUDMetrics.headerSpacing)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

#Preview("In a sheet") {
    HUDActionSheetPreview()
}

/// The sheet body on its own.
#Preview("Body") {
    NavigationStack {
        HUDActionSheetPreviewBody(close: {})
            .navigationBarTitleDisplayMode(.inline)
    }
}

/// A module's sheet as the host presents it.
private struct HUDActionSheetPreview: View {
    @State private var isPresented = true

    var body: some View {
        HUDList {
            HUDListSection("Behind the sheet") {
                Text(verbatim: "The editor the sheet belongs to").hudRow()
            }
        }
        .sheet(isPresented: $isPresented) {
            NavigationStack {
                HUDActionSheetPreviewBody { isPresented = false }
                    .navigationBarTitleDisplayMode(.inline)
            }
        }
    }
}

/// The sheet of a module: state segment and readouts in the body, three action groups below.
private struct HUDActionSheetPreviewBody: View {
    let close: () -> Void

    @State private var state = 2

    var body: some View {
        HUDActionSheet(
            title: Text(verbatim: "Heavy Electron Blaster II"),
            subtitle: Text(verbatim: "HIGH SLOT · ACTIVE · ANTIMATTER CHARGE M · ALL V"),
            groups: [
                [
                    HUDAction("Ammo…", systemImage: "line.3.horizontal.decrease") {},
                    HUDAction("Ammo Info", systemImage: "info.circle") {},
                    HUDAction("Apply Ammo to All Heavy Electron Blaster II",
                              systemImage: "square.grid.2x2") {},
                    HUDAction("Remove Ammo", systemImage: "minus.circle") {},
                ],
                [
                    HUDAction("Variations…", systemImage: "arrow.left.arrow.right") {},
                    HUDAction("Info", systemImage: "info.circle") {},
                ],
                [HUDAction("Remove", systemImage: "trash", role: .destructive) {}],
            ],
            icon: { HUDItemIcon(typeID: TypeID(rawValue: 3074),
                                size: HUDActionSheetMetrics.iconSize) }
        ) {
            Section {
                Picker("Module state", selection: $state) {
                    Text(verbatim: "Offline").tag(0)
                    Text(verbatim: "Online").tag(1)
                    Text(verbatim: "Active").tag(2)
                    Text(verbatim: "Overheat").tag(3)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .hudBareRow()
            }

            HUDListSection {
                HUDReadoutRow("CPU", value: "26 tf")
                HUDReadoutRow("Powergrid", value: "92 MW")
                HUDReadoutRow("DPS", value: "212.4")
                HUDReadoutRow("Optimal + Falloff", value: "1.2 + 6.0 km")
            }
        }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done", action: close)
            }
        }
    }
}
