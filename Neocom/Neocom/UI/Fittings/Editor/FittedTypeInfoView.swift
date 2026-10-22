import DogmaKit
import LiteRow
import LiteRowUI
import SDEKit
import SwiftUI

/// Which fitted thing an info screen is about: two modules of one type have different figures in
/// a fit, and a module and its charge are two entities.
enum FitInfoTarget: Hashable {
    case module(ModuleID)
    case charge(inModule: ModuleID)
    case drone(DroneID)
    /// The hull of one ship of the fit.
    case ship(PilotID)
    /// An implant or a booster of one ship's pilot.
    case implant(ImplantID, of: PilotID)
    case booster(BoosterID, of: PilotID)
}

/// What a row asks the editor to push. Built by the editor's sections, closing over each row's id
/// and type.
struct FitInfoRoute: Hashable {
    var typeID: TypeID
    var target: FitInfoTarget
}

/// `TypeInfoView` for an item standing in the open fit, with the values the engine holds for it.
///
/// The attributes the type declares are read first, then requested from the session in one call.
struct FittedTypeInfoView: View {
    let typeID: TypeID
    let target: FitInfoTarget
    let model: FittingEditorModel
    /// The fit's name, for the caption under the header; handed over by the screen that pushes this
    /// one.
    let fitName: String

    @Environment(\.trainingContext) private var trainingContext
    @Environment(AccountStore.self) private var accounts

    @LiteQuery private var attributes: [TypeAttributeRow]
    /// `nil` while there is nothing to show, never `[:]`: `TypeInfoView` offers its Base / In Fit
    /// switch whenever it is given values at all.
    @State private var fitValues: [AttributeID: Double]?

    init(typeID: TypeID, target: FitInfoTarget, model: FittingEditorModel, fitName: String) {
        self.typeID = typeID
        self.target = target
        self.model = model
        self.fitName = fitName
        _attributes = LiteQuery(SDEBrowser.attributes(of: typeID))
    }

    var body: some View {
        TypeInfoView(typeID: typeID, fitValues: fitValues, fitContext: fitContext)
            // Keyed on the ids: a `@LiteQuery` result is not there in `init`, and a plain `.task`
            // would run on an empty list. The list arrives once, in a fixed order, so the session
            // is asked once.
            .task(id: attributes.map(\.id)) {
                let ids = attributes.map(\.id)
                guard !ids.isEmpty else { return }
                let values = await model.attributes(of: target, ids: ids)
                // An empty answer means the entity is gone from the fit: the screen stays the plain
                // SDE page.
                fitValues = values.isEmpty ? nil : values
            }
    }
}

extension FittedTypeInfoView {
    /// What the caption says about the fit: its name, the skills it is calculated for (worded by
    /// `SetKind`), and the slot, for a module.
    private var fitContext: TypeInfoFitContext {
        let skillsLabel = FitPilotRoster(accounts: accounts, catalog: trainingContext?.catalog)
            .label(of: model.skills)
        let slot: Entity.Module.Slot? = if case let .module(id) = target {
            model.snapshot?.modules.first { $0.id == id }?.slot
        } else {
            nil
        }
        return TypeInfoFitContext(fitName: fitName, skillsLabel: skillsLabel, slotName: slot?.captionName)
    }
}

// Neutron Blaster Cannon II (3186). `damageMultiplier` (64) is 4.41 in the SDE and 9.59 on a
// Vindicator at all skills level 5. Values are written out by hand: the wrapper needs a loaded
// `FittingEditorModel`.
#Preview("In Fit") {
    NavigationStack {
        SDESectionView { _ in
            TypeInfoView(typeID: 3186, fitValues: [64: 9.59],
                         fitContext: TypeInfoFitContext(fitName: "Vindicator — PvP", skillsLabel: "All V",
                                                        slotName: "High slot"))
        }
    }
    .environment(AccountStore())
    .environment(SDEStore())
}

#Preview("From Database") {
    NavigationStack {
        SDESectionView { _ in
            TypeInfoView(typeID: 3186)
        }
    }
    .environment(AccountStore())
    .environment(SDEStore())
}
