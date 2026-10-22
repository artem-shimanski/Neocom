import DogmaKit
import SwiftUI

/// One module in a slot section: the state control, the type icon and name (with its charge
/// underneath when it carries one), and a warning when the engine could not honor the requested
/// state.
///
/// A tap on the icon and the name opens the module's sheet (`FitItemSheet`); removal is a swipe
/// (`HUDSwipeRow`, wrapped around the row by the section). The row has no menu and no chevron.
/// The reachable states are not worked out here: the snapshot carries
/// `Entity.Module.Flags.maxAllowedState`.
struct FitModuleRow: View {
    let module: FitSnapshot.Module
    let typeName: String
    let chargeName: String?
    /// Fires with the state the tap asks for. The caller closes over the module's id and the editor
    /// model.
    let onSetState: (Entity.Module.State) -> Void
    /// A tap on the icon and the name: the caller opens this module's sheet.
    let onSelect: () -> Void
    /// The ship of the fleet the module is aimed at, by its record's name; `nil` for none. The row
    /// only marks it (`HUDTargetMark`).
    var targetName: String?
    /// `Mutated · Gravid` for a mutated module: the subtitle when there is no charge to name.
    var mutationLabel: String?

    /// Taller than a plain `hudRow` for the 40 pt icon; the button and the row both need it.
    private static let height: CGFloat = 58

    var body: some View {
        HStack(spacing: 10) {
            // A rig, a subsystem or a tactical mode tops out at `.offline`: no control is drawn,
            // but its column is kept (`FitStateColumn`) so the icons line up.
            if module.maxAllowedState > .offline {
                stateControl
            } else {
                FitStateColumn()
            }
            // The state control stays outside this button: it is a tap target of its own.
            Button(action: onSelect) {
                HStack(spacing: 10) {
                    HUDItemIcon(typeID: module.typeID, size: 40)
                    HUDRowTitle(title: Text(verbatim: typeName),
                                subtitle: (chargeName ?? mutationLabel).map { Text(verbatim: $0) })
                    Spacer(minLength: 4)
                    if let targetName {
                        HUDTargetMark(shipName: targetName)
                    }
                }
                // An offline module is dimmed. Applied to what the button shows, not the row, so
                // the swipe remove does not show through; the state control stays at full strength.
                // A rig or a subsystem is `.offline` for good and is not dimmed.
                .opacity(module.maxAllowedState > .offline && module.state == .offline ? 0.55 : 1)
                // Padding and height sit inside the button: `.hudRow` puts both on the whole row,
                // while the button style draws its pressed highlight on the label. The horizontal
                // gutter stays outside.
                .padding(.vertical, 8)
                .frame(minHeight: Self.height)
                .contentShape(Rectangle())
            }
            .buttonStyle(.hudRow)
            .accessibilityHint("Shows what this module does in the fit, and what can be done to it")
            // Shown when the engine settled for `effectiveState` instead of `state`. The cause is a
            // gate (`maxGroupOnline`/`maxGroupActive`, an activation the hull blocks, a type
            // ceiling), not a budget, so the marker does not name one.
            if module.effectiveState < module.state {
                FitWarningMark()
                    .accessibilityLabel("Limited")
                    // Says what the player can act on: this fit will not hold the module that high.
                    .accessibilityHint("This fit cannot hold the module in the state you asked for")
            }
        }
        .padding(.leading, Self.leadingPadding)
        .padding(.trailing, Self.trailingPadding)
        .hudRow(HUDRowStyle(horizontalPadding: 0, minHeight: Self.height, verticalPadding: 0))
    }

    /// The editor's rows sit closer to the card's edges than a plain `hudRow`: the state control
    /// 12 pt in, the trailing mark 14 pt. `HUDAddRow` starts its plus at the same 12 pt.
    static let leadingPadding: CGFloat = 12
    static let trailingPadding: CGFloat = 14

    /// Tapping asks for the next state up, wrapping back to `.offline` past `maxAllowedState`.
    private var stateControl: some View {
        // Both halves are spoken: the module's state, and that a tap moves it to the next one.
        FitStateControl(
            state: module.state,
            label: Text("State: \(module.state.title)"),
            hint: Text("Switches to the next state this module allows")
        ) {
            onSetState(Self.next(after: module.state, upTo: module.maxAllowedState))
        }
    }

    private static func next(after state: Entity.Module.State, upTo ceiling: Entity.Module.State) -> Entity.Module.State {
        // `State` is a `UInt8` ladder (0...3); one past `.overloaded` has no case, which is the
        // wrap to `.offline`.
        guard let candidate = Entity.Module.State(rawValue: state.rawValue &+ 1), candidate <= ceiling else {
            return .offline
        }
        return candidate
    }
}

/// The column the state control lives in. A row without a control holds the same width empty,
/// so every icon and the plus of the "+ Add" row stand in one line.
struct FitStateColumn: View {
    static let width: CGFloat = 32

    var body: some View {
        Color.clear
            .frame(width: Self.width, height: Self.width)
            .accessibilityHidden(true)
    }
}

/// The bare red triangle a row shows when the engine would not hold the requested state; the
/// caller supplies the accessibility label.
struct FitWarningMark: View {
    var body: some View {
        Image(systemName: "exclamationmark.triangle.fill")
            .symbolRenderingMode(.palette)
            // The exclamation is cut out of the triangle.
            .foregroundStyle(Color.hudBg, Color.hudDanger)
            .font(.system(size: 15))
            .frame(width: 18, height: 18)
    }
}

#Preview("State looks") {
    VStack(spacing: 0) {
        ForEach([Entity.Module.State.offline, .online, .active, .overloaded], id: \.rawValue) { state in
            FitModuleRow(
                module: FitSnapshot.Module(
                    id: ModuleID(rawValue: .module(state.rawValue, in: .hi, on: .hull(for: PilotID(0).rawValue))),
                    typeID: .heavyElectronBlasterII, slot: .hi, socket: Int(state.rawValue),
                    state: state, effectiveState: state == .overloaded ? .active : state,
                    maxAllowedState: .overloaded, charge: .antimatterChargeM,
                    chargeGroups: [], chargeSize: nil),
                typeName: "Heavy Electron Blaster II", chargeName: "Antimatter Charge M",
                onSetState: { _ in }, onSelect: {})
        }
        FitModuleRow(
            module: FitSnapshot.Module(
                id: ModuleID(rawValue: .module(0, in: .rig, on: .hull(for: PilotID(0).rawValue))),
                typeID: .mediumHybridBurstAeratorII, slot: .rig, socket: 0,
                state: .offline, effectiveState: .offline, maxAllowedState: .offline,
                charge: nil, chargeGroups: [], chargeSize: nil),
            typeName: "Medium Hybrid Burst Aerator II", chargeName: nil,
            onSetState: { _ in }, onSelect: {})
    }
    .background(Color.hudSurface)
    .padding()
    .background(Color.hudBg)
}

#Preview("Fleet target") {
    VStack(spacing: 0) {
        ForEach([String?.some("Vexor — drone ratting"), nil], id: \.self) { target in
            FitModuleRow(
                module: FitSnapshot.Module(
                    id: ModuleID(rawValue: .module(target == nil ? 1 : 0, in: .hi, on: .hull(for: PilotID(0).rawValue))),
                    typeID: .heavyElectronBlasterII, slot: .hi, socket: 0,
                    state: .active, effectiveState: .active, maxAllowedState: .overloaded,
                    charge: nil, chargeGroups: [], chargeSize: nil, isProjectable: true),
                typeName: "Medium Remote Armor Repairer II", chargeName: nil,
                onSetState: { _ in }, onSelect: {},
                targetName: target)
        }
    }
    .background(Color.hudSurface)
    .padding()
    .background(Color.hudBg)
}
