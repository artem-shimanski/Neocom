import SDEKit
import SwiftUI
import TrainingKit

/// Puts the training context into the environment and keeps the character snapshot it is built from
/// up to date.
///
/// Never stands in for its content: a missing context (nobody logged in, or the database not yet
/// opened) is a normal state. Does not call `sde.load()`: the database is opened on demand by the
/// screens that browse it, and the character section must not pull ~23 MB of static data in to name
/// a skill.
struct TrainingContextProvider<Content: View>: View {
    @Environment(AccountStore.self) private var accounts
    @Environment(SDEStore.self) private var sde
    @Environment(\.scenePhase) private var scenePhase

    @ViewBuilder var content: Content

    var body: some View {
        content
            .environment(\.trainingContext, context)
            // Keyed on the selected character: switching accounts brings up another sheet with its
            // own snapshot.
            .task(id: accounts.currentAccountID) {
                await accounts.currentSheet?.ensureFresh()
            }
            // A sign-in replaces the character's sheet, and re-authorizing the selected character
            // does not change `currentAccountID`. The replacement starts from a disk cache written
            // under the replaced client and scopes, so it is reloaded rather than checked against
            // the TTL.
            .onChange(of: accounts.signInGeneration) {
                Task { await accounts.currentSheet?.refresh() }
            }
            // Coming back from the background: the snapshot is likely past its TTL.
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active else { return }
                Task { await accounts.currentSheet?.ensureFresh() }
            }
    }

    @MainActor
    private var context: TrainingContext? {
        // No catalog, no context: without the reference book there is no training math. Both
        // catalogs load in one step (`SDEStore.load()`).
        guard let catalog = sde.skillCatalog, let certificates = sde.certificateCatalog else {
            return nil
        }

        let sheet = accounts.currentSheet
        // `CharacterSheet.pilot(using:)` is non-optional and falls back to a zero snapshot, so
        // emptiness is checked here; the stand-in pilot would show training times for a character
        // that does not exist.
        let pilot = sheet?.snapshot == nil ? nil : sheet?.pilot(using: catalog)

        return TrainingContext(catalog: catalog,
                               certificates: certificates,
                               pilot: pilot,
                               characterID: accounts.currentAccountID,
                               characterImplants: sheet?.snapshot?.implants ?? [],
                               plannedLevels: plannedLevels)
    }

    /// The character's plan, reduced to the highest level it reaches per skill.
    ///
    /// Read here, not by each screen: touching `entries` from this `body` makes a plan edit redraw
    /// the markers everywhere.
    @MainActor
    private var plannedLevels: [TypeID: Int] {
        guard let entries = accounts.currentPlan?.entries else { return [:] }
        return Dictionary(entries.map { ($0.skillID, $0.level) }, uniquingKeysWith: max)
    }
}
