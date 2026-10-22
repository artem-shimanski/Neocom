import SwiftUI

extension View {
    /// Trailing row actions for every kind of input: the system swipe on touch, and the same
    /// buttons in a context menu.
    ///
    /// `allowsFullSwipe` is off by default, so the swipe only reveals the buttons. Pass
    /// `inContextMenu: false` for a row whose own `.contextMenu` already carries these actions;
    /// nested context menus do not merge.
    func hudRowActions<Actions: View>(inContextMenu: Bool = true,
                                      allowsFullSwipe: Bool = false,
                                      @ViewBuilder _ actions: () -> Actions) -> some View {
        let actions = actions()
        return self
            .swipeActions(edge: .trailing, allowsFullSwipe: allowsFullSwipe) { actions }
            .modifier(HUDRowContextMenu(enabled: inContextMenu) { actions })
    }
}

private struct HUDRowContextMenu<Actions: View>: ViewModifier {
    let enabled: Bool
    @ViewBuilder var actions: Actions

    func body(content: Content) -> some View {
        if enabled {
            content.contextMenu { actions }
        } else {
            content
        }
    }
}
