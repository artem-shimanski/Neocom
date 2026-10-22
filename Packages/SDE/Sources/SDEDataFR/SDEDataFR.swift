//
//  SDEDataFR.swift
//  SDE
//

import Foundation

/// SDE language file (French), embedded in this target's bundle.
///
/// Attached to the main database (`SDEDataMain`) under the `text` schema; tied to its build:
/// `SDEDatabase` compares `buildNumber` on open.
public enum SDEDataFR {
    /// Language code, also the value of `meta.language` inside the file.
    public static let language = "fr"

    public static let fileName = "text-fr.sqlite"

    /// The language database file. The `build-sde` plugin puts it here; an empty `Data` means the
    /// build was never run.
    public static var url: URL {
        guard let url = Bundle.module.url(
            forResource: "text-fr",
            withExtension: "sqlite",
            subdirectory: "Data"
        ) else {
            preconditionFailure(
                "в бандле SDEDataFR нет \(fileName) — соберите базу плагином build-sde"
            )
        }
        return url
    }
}
