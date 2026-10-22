import DogmaKit
import SwiftUI

/// One drone stack in the drones section: the "in space" control, the type icon, the name with
/// what the stack takes (volume and bandwidth) underneath, and the drone count on the trailing
/// side.
///
/// The control is `FitStateControl` in two looks: `active` for a stack in space, `offline` for
/// one in the bay. A tap on the icon or the name opens the stack's sheet (`FitItemSheet`);
/// removal is the swipe (`HUDSwipeRow`) the section wraps the row in. The row has no menu.
///
/// As in `FitModuleRow`, the row knows neither the drone's id nor the editor model; the caller
/// closes over both.
struct FitDroneRow: View {
    let drone: FitSnapshot.Drone
    let typeName: String
    /// Fires with the new value of "in space": `true` sends the stack to space, `false` back to the
    /// bay.
    let onSetActive: (Bool) -> Void
    /// A tap on the icon or the name: the caller opens this stack's sheet.
    let onSelect: () -> Void
    /// The ship of the fleet the stack is aimed at, by its record's name; `nil` for none.
    var targetName: String?
    /// Whether the control may send the stack to space (`FitSnapshot.canLaunch`): a fighter
    /// squadron with every tube taken may not. Bringing a stack back is never held back.
    var canLaunch = true

    /// The module row's height, so both kinds of row share one rhythm.
    private static let height: CGFloat = 58

    var body: some View {
        HStack(spacing: 10) {
            // Stands in the column of a module's state control, so the icons line up.
            FitStateControl(
                state: drone.isActive ? .active : .offline,
                label: Text("In Space"),
                hint: drone.isFighter
                    ? Text("Launches the squadron, or returns it to the hangar")
                    : Text("Sends the drones to space, or back to the bay"),
                value: drone.isActive ? Text("On") : Text("Off")
            ) {
                onSetActive(!drone.isActive)
            }
            .disabled(!drone.isActive && !canLaunch)
            // The control stays outside this button: it is a tap target of its own.
            Button(action: onSelect) {
                HStack(spacing: 10) {
                    HUDItemIcon(typeID: drone.typeID, size: 40)
                    HUDRowTitle(title: Text(verbatim: typeName),
                                subtitle: Text(verbatim: Self.subtitle(of: drone)),
                                subtitleCase: nil)
                        .lineLimit(2)
                    Spacer(minLength: 4)
                    Text(verbatim: "x\(drone.count)")
                        .font(.hudFigure)
                        .foregroundStyle(Color.hudInk)
                        .accessibilityLabel("Count \(drone.count)")
                    if let targetName {
                        HUDTargetMark(shipName: targetName)
                    }
                }
                // A stack in the bay is dimmed. Applied to what the button shows, not the row, so
                // the swipe remove does not show through; the control stays at full strength.
                .opacity(drone.isActive ? 1 : 0.7)
                // Inside the button: the pressed highlight is drawn on the label.
                .padding(.vertical, 8)
                .frame(minHeight: Self.height)
                .contentShape(Rectangle())
            }
            .buttonStyle(.hudRow)
            .accessibilityHint("Shows what this drone does in the fit, and what can be done to it")
        }
        .padding(.leading, FitModuleRow.leadingPadding)
        .padding(.trailing, FitModuleRow.trailingPadding)
        .hudRow(HUDRowStyle(horizontalPadding: 0, minHeight: Self.height, verticalPadding: 0))
    }

    /// What the whole stack takes: the per-drone figures times the count. Bandwidth is printed
    /// whether or not the stack is in space. A fighter squadron takes no bandwidth; its volume is
    /// in the fighter hangar.
    private static func subtitle(of drone: FitSnapshot.Drone) -> String {
        let volume = (drone.volume * Double(drone.count)).resourceFigure
        if drone.isFighter {
            return String(localized: "\(volume) m³", comment: "Unit: cubic metres, number then unit")
        }
        let bandwidth = (drone.bandwidthUsed * Double(drone.count)).resourceFigure
        return String(localized: "\(volume) m³ · \(bandwidth) Mbit/s", comment: "Drone stack volume and bandwidth")
    }
}

#Preview("Drone stacks") {
    let hull = EntityID.hull(for: PilotID(0).rawValue)
    VStack(spacing: 0) {
        FitDroneRow(
            drone: FitSnapshot.Drone(id: DroneID(rawValue: .drone(0, on: hull)), typeID: .hammerheadII,
                                     count: 5, maxCount: 5, isActive: true, volume: 5, bandwidthUsed: 10),
            typeName: "Hammerhead II", onSetActive: { _ in }, onSelect: {})
        FitDroneRow(
            drone: FitSnapshot.Drone(id: DroneID(rawValue: .drone(1, on: hull)), typeID: .hammerheadII,
                                     count: 3, maxCount: 5, isActive: false, volume: 5, bandwidthUsed: 10),
            typeName: "Hammerhead II", onSetActive: { _ in }, onSelect: {})
    }
    .background(Color.hudSurface)
    .padding()
    .background(Color.hudBg)
}
