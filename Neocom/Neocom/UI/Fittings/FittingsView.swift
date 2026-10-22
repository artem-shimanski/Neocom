import DogmaKit
import LiteRow
import LiteRowUI
import SDEKit
import SwiftData
import SwiftUI

/// The Fitting Tool section: the player's own fits plus a read-only view of the fittings saved
/// in the game. Wrapped in `SDESectionView`, since rows need the SDE for ship names and icons.
struct FittingsView: View {
    @State private var tab: FittingsTab = .myFits
    @State private var isShowingShipPicker = false
    /// What the picker closed on, held until the sheet is gone. The fit is created from the
    /// sheet's `onDismiss`: a push requested in the same pass as a sheet dismissal is dropped.
    @State private var pickedShip: PickedShip?
    /// Pushes the editor right after `store.create(...)`. The enclosing `NavigationStack`'s path
    /// is not reachable from here, so `navigationDestination(item:)` is used instead of appending.
    @State private var pushedRoute: FittingRoute?

    @Environment(FittingStore.self) private var fittings

    var body: some View {
        SDESectionView { database in
            Group {
                switch tab {
                case .myFits:
                    FittingListView()
                case .inGame:
                    InGameFittingsView()
                }
            }
            // Registered inside `SDESectionView`, where `liteDatabase` is in scope to hand down.
            .navigationDestination(for: FittingRoute.self) { route in
                route.destination
                    .liteDatabase(database.database)
            }
            .navigationDestination(item: $pushedRoute) { route in
                route.destination
                    .liteDatabase(database.database)
            }
            .sheet(isPresented: $isShowingShipPicker, onDismiss: createPickedFit) {
                ShipPickerView { shipTypeID, shipName in
                    pickedShip = PickedShip(typeID: shipTypeID, name: shipName)
                }
            }
        }
        .hudScreen()
        .navigationTitle("Fitting Tool")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("Tab", selection: $tab) {
                    ForEach(FittingsTab.allCases) { tab in
                        Text(tab.title).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
            }
            if tab == .myFits {
                ToolbarItem(placement: .primaryAction) {
                    Button("New Fit", systemImage: "plus") {
                        isShowingShipPicker = true
                    }
                }
            }
        }
    }

    /// Creates a bare-hull fit named after the picked ship and opens it. `onDismiss` also fires
    /// for `Cancel` and a swipe down, so it does nothing without a pick.
    private func createPickedFit() {
        guard let picked = pickedShip else { return }
        pickedShip = nil
        pushedRoute = .editor(fittings.createFit(for: picked))
    }
}

extension FittingStore {
    /// A new record with nothing but the bare hull on it, named after the ship.
    func createFit(for ship: PickedShip) -> UUID {
        let document = FitDocument(pilots: [.init(skills: .init(default: FitDocument.assumedSkillLevel),
                                             ship: .init(type: ship.typeID))])
        return create(shipTypeID: ship.typeID, name: ship.name, document: document)
    }
}

/// The ship the picker handed back: its id and the name shown in the picker.
struct PickedShip {
    var typeID: TypeID
    /// Never empty: ESI accepts fit names of 1...50 characters.
    var name: String

    init(typeID: TypeID, name: String) {
        self.typeID = typeID
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        self.name = trimmed.isEmpty ? String(localized: "New Fit") : trimmed
    }
}

enum FittingsTab: String, CaseIterable, Identifiable {
    case myFits
    case inGame

    var id: Self { self }

    var title: LocalizedStringKey {
        switch self {
        case .myFits: "My Fits"
        case .inGame: "In Game"
        }
    }
}

/// Where a row of "My Fits" leads: the editor on one fit.
enum FittingRoute: Hashable {
    case editor(UUID)

    @ViewBuilder var destination: some View {
        switch self {
        case let .editor(id): FittingEditorView(fittingID: id)
        }
    }
}

#Preview {
    let container = try! ModelContainer(for: Fitting.self, configurations: .init(isStoredInMemoryOnly: true))
    return NavigationStack {
        FittingsView()
    }
    .environment(AccountStore())
    .environment(SDEStore())
    .environment(FittingStore(context: container.mainContext))
}
