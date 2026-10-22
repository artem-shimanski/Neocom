//
//  SDEDataRU.swift
//  SDE
//

import Foundation

/// SDE language file (Russian), embedded in this target's bundle.
///
/// Attached to the main database (`SDEDataMain`) under the `text` schema; tied to its build:
/// `SDEDatabase` compares `buildNumber` on open.
public enum SDEDataRU {
    /// Language code, also the value of `meta.language` inside the file.
    public static let language = "ru"

    public static let fileName = "text-ru.sqlite"

    /// The language database file. The `build-sde` plugin puts it here; an empty `Data` means the
    /// build was never run.
    public static var url: URL {
        guard let url = Bundle.module.url(
            forResource: "text-ru",
            withExtension: "sqlite",
            subdirectory: "Data"
        ) else {
            preconditionFailure(
                "в бандле SDEDataRU нет \(fileName) — соберите базу плагином build-sde"
            )
        }
        return url
    }
}
