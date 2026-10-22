//
//  SDEDataMain.swift
//  SDE
//

import Foundation

/// Main SDE database file, embedded in this target's bundle.
///
/// Contains no text, only `NameID`/`DescriptionID`, which the language file (`SDEDataEN`,
/// `SDEDataRU` and others) resolves.
///
/// ```swift
/// let sde = try await SDEDatabase(main: SDEDataMain.url, text: SDEDataRU.url)
/// ```
public enum SDEDataMain {
    public static let fileName = "sde.sqlite"

    /// The main database file. The `build-sde` plugin puts it here; an empty `Data` means the build
    /// was never run, and crashing is better than `nil`.
    public static var url: URL {
        guard let url = Bundle.module.url(
            forResource: "sde",
            withExtension: "sqlite",
            subdirectory: "Data"
        ) else {
            preconditionFailure(
                "в бандле SDEDataMain нет \(fileName) — соберите базу плагином build-sde"
            )
        }
        return url
    }
}
