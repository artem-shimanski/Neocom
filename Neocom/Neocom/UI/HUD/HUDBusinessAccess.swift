import SwiftUI

/// The empty state of a business screen whose source cannot be read: a missing scope offers
/// `Grant Access`, a corporation route the roles don't allow says so.
struct HUDBusinessAccessPanel: View {
    let access: BusinessAccess
    let title: Text
    let message: Text

    var body: some View {
        if access == .forbidden {
            HUDEmptyPanel(title: Text("No Access"),
                          message: Text("Your corporation roles don't allow reading this."))
        } else {
            HUDGrantAccessPanel(title: title, message: message)
        }
    }
}

extension View {
    /// The corporation's name under the title of a corporation screen; personal screens get none.
    func corporationSubtitle(_ scope: DataScope) -> some View {
        modifier(CorporationSubtitle(scope: scope))
    }
}

private struct CorporationSubtitle: ViewModifier {
    let scope: DataScope

    @Environment(AccountStore.self) private var accounts

    func body(content: Content) -> some View {
        if scope == .corporation {
            content.navigationSubtitle(Text(verbatim: accounts.currentSheet?.profile?.corporationName ?? ""))
        } else {
            content
        }
    }
}

/// The screen shown for a character that is not in a corporation.
struct NoCorporationView: View {
    var body: some View {
        ContentUnavailableView("No Corporation", systemImage: "building.2",
                               description: Text("This character is not in a corporation."))
    }
}
