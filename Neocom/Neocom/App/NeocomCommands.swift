import SwiftUI

/// Menu bar commands on Mac and hardware-keyboard shortcuts on iPad: Settings (⌘,) and Refresh (⌘R).
///
/// Screens publish what the commands act on as focused scene values; a command without a
/// published value is disabled.
struct NeocomCommands: Commands {
    @FocusedValue(\.openMainMenuSection) private var openSection
    @FocusedValue(\.refreshCommand) private var refresh

    var body: some Commands {
        CommandGroup(replacing: .appSettings) {
            Button("Settings…") {
                openSection?.open(.settings)
            }
            .keyboardShortcut(",")
            .disabled(openSection == nil)
        }
        CommandGroup(before: .toolbar) {
            Button("Refresh") {
                guard let refresh else { return }
                Task { await refresh.action() }
            }
            .keyboardShortcut("r")
            .disabled(refresh == nil)
            Divider()
        }
        // Single window.
        CommandGroup(replacing: .newItem) {}
    }
}

/// Opens a section by selecting it as the split view's detail column.
struct MainMenuSectionOpener {
    let open: (MainMenuSection) -> Void
}

/// A screen's refresh action, offered to the Refresh command.
struct RefreshCommand {
    let action: @Sendable () async -> Void
}

extension FocusedValues {
    @Entry var openMainMenuSection: MainMenuSectionOpener?
    @Entry var refreshCommand: RefreshCommand?
}

extension View {
    /// `refreshable(action:)` that also answers the Refresh command (⌘R) while the screen is in the
    /// focused scene.
    func refreshableCommand(action: @escaping @Sendable () async -> Void) -> some View {
        refreshable(action: action)
            .focusedSceneValue(\.refreshCommand, RefreshCommand(action: action))
    }
}
