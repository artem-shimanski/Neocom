import DogmaKit
import SDEKit
import SwiftUI

/// Target choice for a remote module or drone stack: `No Target`, then every other ship of
/// the fleet with the current one checked. The ship the module is on is never offered. A tap
/// picks and closes.
struct FitTargetSheet: View {
    let itemName: String
    let current: PilotID?
    let candidates: [FleetMember]
    let hullNames: [TypeID: String]
    let onSelect: (PilotID?) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            HUDList(isTransparent: true) {
                HUDListSection {
                    row(isOn: current == nil, action: { pick(nil) }) {
                        Image(systemName: "circle.slash")
                            .font(.system(size: 17))
                            .foregroundStyle(Color.hudInkMuted)
                            .frame(width: 32, height: 32)
                    } title: {
                        HUDRowTitle(title: Text("No Target"), subtitle: Text("Cycles on nothing"))
                    }
                    ForEach(candidates) { ship in
                        row(isOn: current == ship.id, action: { pick(ship.id) }) {
                            HUDItemIcon(typeID: ship.shipTypeID, size: 32)
                        } title: {
                            HUDRowTitle(title: Text(verbatim: ship.name), subtitle: subtitle(of: ship))
                        }
                    }
                } header: {
                    HUDSectionHeader(Text(verbatim: itemName))
                } footer: {
                    HUDFootnote("A ship cannot be its own target. Range and the target's position are not modelled.")
                }
            }
            .navigationTitle("Target")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func pick(_ pilot: PilotID?) {
        if pilot != current { onSelect(pilot) }
        dismiss()
    }

    /// `VEXOR · EHP 14.1K`: the hull, and what the target would have to soak.
    private func subtitle(of ship: FleetMember) -> Text {
        let hitPoints = FitStatFormat.hpCompact(ship.stats.uniformEffectiveHitPoints.sum())
        let hull = hullNames[ship.shipTypeID].map { $0 + " · " } ?? ""
        let figure = "\(hitPoints.figure)\(hitPoints.unit)"
        return Text(verbatim: "\(hull)" + String(localized: "EHP \(figure)", comment: "Effective hit points, label then compact figure"))
    }

    private func row(isOn: Bool,
                     action: @escaping () -> Void,
                     @ViewBuilder icon: () -> some View,
                     @ViewBuilder title: () -> some View) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                icon()
                title()
                Spacer(minLength: 8)
                if isOn {
                    Image(systemName: "checkmark")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Color.hudAccent)
                        .accessibilityHidden(true)
                }
            }
            .hudRow(Self.rowStyle)
        }
        .hudRowButton(Self.rowStyle)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    private static let rowStyle: HUDRowStyle = {
        var style = HUDRowStyle.sheet
        style.minHeight = 54
        return style
    }()
}
