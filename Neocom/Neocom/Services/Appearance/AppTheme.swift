import SwiftUI
import UIKit

/// The app's appearance: system, light or dark. Stored in `UserDefaults` under `storageKey`.
///
/// Applied as `overrideUserInterfaceStyle` on every window rather than `.preferredColorScheme`,
/// which does not reliably reset already presented sheets, alerts and popovers when set back to Auto.
enum AppTheme: String, CaseIterable, Identifiable {
    case system, light, dark

    static let storageKey = "appearance.theme"

    var id: Self { self }

    var title: String {
        switch self {
        case .system: String(localized: "appearance.theme.auto", defaultValue: "Auto", comment: "Theme that follows the system appearance")
        case .light: String(localized: "appearance.theme.light", defaultValue: "Light", comment: "Light colour theme")
        case .dark: String(localized: "appearance.theme.dark", defaultValue: "Dark", comment: "Dark colour theme")
        }
    }

    var interfaceStyle: UIUserInterfaceStyle {
        switch self {
        case .system: .unspecified
        case .light: .light
        case .dark: .dark
        }
    }

    /// Sets the style on all windows now. Windows created later are covered by `ThemeApplier`.
    @MainActor
    static func apply(_ theme: AppTheme) {
        for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
            for window in scene.windows where window.overrideUserInterfaceStyle != theme.interfaceStyle {
                window.overrideUserInterfaceStyle = theme.interfaceStyle
            }
        }
    }
}

/// Keeps the stored theme on the windows: at launch, on change and for windows and scenes created later.
private struct ThemeApplier: ViewModifier {
    @AppStorage(AppTheme.storageKey) private var stored = AppTheme.system.rawValue

    private var theme: AppTheme { AppTheme(rawValue: stored) ?? .system }

    func body(content: Content) -> some View {
        content
            .onAppear { AppTheme.apply(theme) }
            .onChange(of: stored) { AppTheme.apply(theme) }
            .onReceive(NotificationCenter.default.publisher(for: UIWindow.didBecomeKeyNotification)) { _ in
                AppTheme.apply(theme)
            }
            .onReceive(NotificationCenter.default.publisher(for: UIScene.didActivateNotification)) { _ in
                AppTheme.apply(theme)
            }
    }
}

extension View {
    /// Applies the player's chosen theme to the windows of the app. Put it on the root view.
    func appliesAppTheme() -> some View { modifier(ThemeApplier()) }
}
