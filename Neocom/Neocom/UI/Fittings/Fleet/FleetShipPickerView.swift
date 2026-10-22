import DogmaKit
import LiteRow
import LiteRowUI
import SDEKit
import SwiftData
import SwiftUI

/// The sheet that adds ships to a fleet: a checklist of My Fits, an `Empty Hull…` row and a
/// confirm button.
///
/// Every ship is a My Fits record. Fits already in the fleet are checked and locked, and no more
/// can be checked than `Fit.Pilots.maxCount` leaves room for. Has its own `NavigationStack` and
/// `SDESectionView`, since a sheet gets no `liteDatabase`.
struct FleetShipPickerView: View {
    let fleetFittingIDs: [UUID]
    /// Called once with the picked records in check order, right before the sheet closes; not
    /// called on `Cancel`.
    let onConfirm: ([UUID]) -> Void

    @Environment(FittingStore.self) private var fittings
    @Environment(\.dismiss) private var dismiss

    @State private var selection: [UUID] = []
    @State private var isShowingShipPicker = false
    /// What `Empty Hull…` closed on, held until its sheet is gone (see `FittingsView`).
    @State private var pickedShip: PickedShip?

    private var capacity: Int { max(Fit.Pilots.maxCount - fleetFittingIDs.count, 0) }

    var body: some View {
        NavigationStack {
            SDESectionView { _ in
                FleetShipPickerList(fits: fittings.fits,
                                    fleetFittingIDs: Set(fleetFittingIDs),
                                    selection: $selection,
                                    capacity: capacity,
                                    onEmptyHull: { isShowingShipPicker = true })
            }
            .hudScreen()
            .navigationTitle("Add Ships")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark", role: .cancel) { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    onConfirm(selection)
                    dismiss()
                } label: {
                    confirmTitle
                        .frame(maxWidth: .infinity)
                }
                .hudProminentButton()
                .disabled(selection.isEmpty)
                .padding(.horizontal, HUDMetrics.gutter)
                .padding(.bottom, 8)
            }
        }
        .sheet(isPresented: $isShowingShipPicker, onDismiss: createPickedHull) {
            ShipPickerView(includesStructures: false) { shipTypeID, shipName in
                pickedShip = PickedShip(typeID: shipTypeID, name: shipName)
            }
        }
    }

    private var confirmTitle: Text {
        Text("Add \(selection.count) Ships")
    }

    /// Creates the record and checks it if there is room; the record stays in My Fits regardless.
    private func createPickedHull() {
        guard let picked = pickedShip else { return }
        pickedShip = nil
        let fittingID = fittings.createFit(for: picked)
        if selection.count < capacity {
            selection.append(fittingID)
        }
    }
}

/// The checklist, split out so `@LiteQuery` can name the ships with one query built in `init`.
private struct FleetShipPickerList: View {
    let fits: [FittingSummary]
    let fleetFittingIDs: Set<UUID>
    @Binding var selection: [UUID]
    let capacity: Int
    let onEmptyHull: () -> Void

    @LiteQuery private var ships: [ShipRow]

    init(fits: [FittingSummary], fleetFittingIDs: Set<UUID>, selection: Binding<[UUID]>,
         capacity: Int, onEmptyHull: @escaping () -> Void) {
        self.fits = fits
        self.fleetFittingIDs = fleetFittingIDs
        _selection = selection
        self.capacity = capacity
        self.onEmptyHull = onEmptyHull
        _ships = LiteQuery(FittingBrowser.ships(Array(Set(fits.map(\.shipTypeID)))))
    }

    var body: some View {
        let shipByID = Dictionary(ships.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let isFull = selection.count >= capacity
        // A fit on a structure is not offered; one already in the fleet stays listed.
        let candidates = fits.filter { fit in
            fleetFittingIDs.contains(fit.id) || shipByID[fit.shipTypeID]?.categoryID != .structure
        }
        HUDList {
            HUDListSection {
                ForEach(candidates) { fit in
                    let isInFleet = fleetFittingIDs.contains(fit.id)
                    let isOn = isInFleet || selection.contains(fit.id)
                    let isEnabled = !isInFleet && (isOn || !isFull)
                    FleetShipPickerRow(fit: fit, ship: shipByID[fit.shipTypeID],
                                       isOn: isOn, isEnabled: isEnabled) {
                        toggle(fit.id)
                    }
                }
                HUDAddRow(title: "Empty Hull…", action: onEmptyHull)
                    .disabled(isFull)
            } header: {
                HUDSectionHeader(Text("Ships from My Fits")) {
                    Text("\(selection.count) selected · \(fleetFittingIDs.count + selection.count)/\(Fit.Pilots.maxCount)")
                        .foregroundStyle(isFull ? Color.hudWarn : Color.hudAccent)
                }
            } footer: {
                HUDFootnote("Each ship is the fit itself, not a copy: editing it in the fleet changes it in My Fits. Every ship keeps its own pilot skills. A fleet holds at most \(Fit.Pilots.maxCount) ships.")
            }
        }
    }

    private func toggle(_ id: UUID) {
        if let index = selection.firstIndex(of: id) {
            selection.remove(at: index)
        } else if selection.count < capacity {
            selection.append(id)
        }
    }
}

private struct FleetShipPickerRow: View {
    let fit: FittingSummary
    let ship: ShipRow?
    let isOn: Bool
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                HUDCheckCircle(isOn: isOn, isEnabled: isEnabled)
                HUDItemIcon(typeID: fit.shipTypeID, size: 40)
                HUDRowTitle(title: Text(verbatim: fit.name), subtitle: subtitle)
                Spacer(minLength: 4)
            }
            .opacity(isEnabled || isOn ? 1 : 0.55)
            .hudRow(FittingRow.rowStyle)
        }
        .hudRowButton(FittingRow.rowStyle)
        .disabled(!isEnabled)
        .accessibilityAddTraits(.isToggle)
        .accessibilityValue(isOn ? Text("On") : Text("Off"))
    }

    private var subtitle: Text? {
        guard let ship else { return nil }
        return Text(verbatim: "\(ship.name) · \(ship.groupName)")
    }
}

#Preview {
    let container = try! ModelContainer(for: Fitting.self, configurations: .init(isStoredInMemoryOnly: true))
    let store = FittingStore(context: container.mainContext)
    let first = store.createFit(for: PickedShip(typeID: TypeID(rawValue: 626), name: "Vexor"))
    _ = store.createFit(for: PickedShip(typeID: TypeID(rawValue: 634), name: "Exequror"))
    return Color.clear
        .sheet(isPresented: .constant(true)) {
            FleetShipPickerView(fleetFittingIDs: [first]) { _ in }
        }
        .environment(store)
        .environment(SDEStore())
        .modelContainer(container)
}
