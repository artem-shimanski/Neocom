import Foundation

/// The App Group shared by the app and the widget extension.
/// Compiled into both targets (see `Neocom/Shared/`).
nonisolated enum AppGroup {
    static let identifier = "group.com.shimanski.neocom"

    /// Shared container; nil when the group entitlement is missing.
    static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier)
    }
}
