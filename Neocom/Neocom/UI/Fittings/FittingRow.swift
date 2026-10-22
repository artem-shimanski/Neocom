import SDEKit
import SwiftUI

/// One row of the "My Fits" list. `ship` is `nil` when the fit's ship is missing from the SDE;
/// the row still draws.
struct FittingRow: View {
    let fit: FittingSummary
    let ship: ShipRow?
    /// The fitting ids ESI returned for the character `fit.esiCharacterID` points at, or `nil` when
    /// that list is not loaded. With a list, the "in game" badge hides for a fit deleted in the game;
    /// without one, the stored link is trusted.
    let knownGameFittingIDs: Set<Int64>?
    var isUploading = false

    private var showsInGameBadge: Bool {
        guard let esiFittingID = fit.esiFittingID else { return false }
        guard let knownGameFittingIDs else { return true }
        return knownGameFittingIDs.contains(esiFittingID)
    }

    var body: some View {
        HStack(spacing: 12) {
            HUDItemIcon(typeID: fit.shipTypeID, size: 44)
            HUDRowTitle(title: Text(fit.name), subtitle: subtitle, font: HUDFont.display(15, weight: .semibold, relativeTo: .body))
            Spacer(minLength: 4)
            if isUploading {
                ProgressView()
            } else if showsInGameBadge {
                Text("In Game")
                    .font(.hudMicro)
                    .tracking(1)
                    .textCase(.uppercase)
                    .foregroundStyle(Color.hudAccent)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .overlay {
                        Capsule().strokeBorder(Color.hudAccent.opacity(0.35), lineWidth: 1)
                    }
            }
            HUDChevron()
        }
        .hudRow(Self.rowStyle)
    }

    /// Taller than a plain row, for the 44 pt hull icon; also applied to the link the row labels.
    static let rowStyle = HUDRowStyle(minHeight: 60)

    private var subtitle: Text {
        let age = Text(fit.updatedAt, format: .relative(presentation: .named))
        if let ship {
            return Text("\(Text(verbatim: ship.name + " · "))\(age)")
        }
        return age
    }
}

#Preview {
    HUDList {
        Section {
            FittingRow(
                fit: FittingSummary(id: UUID(),
                                    name: "Vindicator — blaster brawl",
                                    shipTypeID: 17740,
                                    notes: "",
                                    updatedAt: .now.addingTimeInterval(-3600),
                                    esiFittingID: 1,
                                    esiCharacterID: 1),
                ship: nil,
                knownGameFittingIDs: nil
            )
        }
    }
}
