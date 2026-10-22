//
//  SDEDataKO.swift
//  SDE
//

import Foundation

/// SDE language file (Korean), embedded in this target's bundle.
///
/// Attached to the main database (`SDEDataMain`) under the `text` schema; tied to its build:
/// `SDEDatabase` compares `buildNumber` on open.
public enum SDEDataKO {
    /// Language code, also the value of `meta.language` inside the file.
    public static let language = "ko"

    public static let fileName = "text-ko.sqlite"

    /// The language database file. The `build-sde` plugin puts it here; an empty `Data` means the
    /// build was never run.
    public static var url: URL {
        guard let url = Bundle.module.url(
            forResource: "text-ko",
            withExtension: "sqlite",
            subdirectory: "Data"
        ) else {
            preconditionFailure(
                "в бандле SDEDataKO нет \(fileName) — соберите базу плагином build-sde"
            )
        }
        return url
    }
}
