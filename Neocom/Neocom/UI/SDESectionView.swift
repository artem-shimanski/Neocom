import LiteRow
import LiteRowUI
import SDEKit
import SwiftUI

/// The shell the browsing sections sit in: opens the static data export, shows progress, and hands
/// the open database to the screen below.
///
/// `content` is built only once the database is open.
struct SDESectionView<Content: View>: View {
    @Environment(SDEStore.self) private var sde

    @ViewBuilder var content: (SDEDatabase) -> Content

    var body: some View {
        Group {
            switch sde.state {
            case .idle, .loading:
                ProgressView()
                    .controlSize(.large)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case let .failed(error):
                ContentUnavailableView {
                    Label("Database Unavailable", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(error.localizedDescription)
                }
            case let .ready(database):
                content(database)
                    // Every screen here reads through `@LiteQuery` from this database. Pushed
                    // screens get it inside the destination builder rather than inheriting it: the
                    // navigation stack is `MainMenuView`'s detail stack, created before the
                    // database is opened.
                    //
                    // `DatabaseRoute` is registered for every section, since an item is the same
                    // screen wherever it is reached from.
                    .navigationDestination(for: DatabaseRoute.self) { route in
                        route.destination
                            .liteDatabase(database.database)
                    }
                    .liteDatabase(database.database)
            }
        }
        .task { await sde.load() }
    }
}
