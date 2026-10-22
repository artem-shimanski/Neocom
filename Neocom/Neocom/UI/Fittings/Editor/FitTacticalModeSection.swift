import DogmaKit
import SwiftUI

/// The hull's tactical mode as a switch under the header: one tile per mode, then a card of what
/// the chosen one changes and the way to its info.
///
/// The mode is a module in the engine's `.mode` rack but is not drawn as one: the hull always
/// flies exactly one (see `Entity.Module.Slot.displayOrder`). Drawn only when the engine gives
/// the hull a mode rack and the SDE names its modes.
struct FitTacticalModeSection: View {
    let modes: [TacticalMode]
    /// The mode module the snapshot holds, if any.
    let current: FitSnapshot.Module?
    let onSelect: (TypeID) -> Void
    let onShowInfo: (FitInfoRoute) -> Void

    var body: some View {
        let selected = modes.first { $0.id == current?.typeID }
        HUDListSection {
            tiles
                .hudLeadingBlock(hasCardBelow: selected != nil)
            if let selected {
                ForEach(selected.bonuses) { bonus in
                    HUDReadoutRow(Text(verbatim: bonus.label), value: bonus.value)
                }
                if let current {
                    Button {
                        onShowInfo(FitInfoRoute(typeID: current.typeID, target: .module(current.id)))
                    } label: {
                        HUDLinkRowLabel(systemImage: nil, title: Text(verbatim: selected.name))
                    }
                    .hudRowButton()
                }
            }
        } header: {
            HUDSectionHeader(Text("Tactical Mode"))
        }
    }

    /// Three across, each as wide as the others.
    private var tiles: some View {
        HStack(spacing: HUDMetrics.headerSpacing) {
            ForEach(modes) { mode in
                let isSelected = mode.id == current?.typeID
                Button {
                    if !isSelected { onSelect(mode.id) }
                } label: {
                    HUDChoiceTile(systemImage: mode.systemImage,
                                  title: Text(verbatim: mode.title),
                                  value: Text(verbatim: mode.headline?.headline ?? ""),
                                  isSelected: isSelected,
                                  isCompact: true)
                }
                .buttonStyle(.hudTile)
                .frame(maxWidth: .infinity)
            }
        }
    }
}
