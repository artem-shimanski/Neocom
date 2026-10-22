import SwiftUI

/// The app's shared stores and the training context, handed by hand to a sheet or push built
/// outside the root's environment.
///
/// A presentation built in a context menu's own host has none of the root's environment, and
/// reading `@Environment(AccountStore.self)` there crashes. A presenting view keeps one of these
/// and applies it to every sheet and destination it builds.
struct CarriedEnvironment: DynamicProperty {
    @Environment(AccountStore.self) private var accounts
    @Environment(FittingStore.self) private var fittings
    @Environment(SDEStore.self) private var sde
    @Environment(MarketSheet.self) private var market
    @Environment(\.trainingContext) private var trainingContext

    func apply<Content: View>(to content: Content) -> some View {
        content
            .environment(accounts)
            .environment(fittings)
            .environment(sde)
            .environment(market)
            .environment(\.trainingContext, trainingContext)
    }
}

extension View {
    /// Puts back the environment a presenting view read with `CarriedEnvironment`.
    func carryingEnvironment(_ environment: CarriedEnvironment) -> some View {
        environment.apply(to: self)
    }
}
