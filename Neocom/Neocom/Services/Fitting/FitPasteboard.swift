import DogmaKit
import DogmaKitIO
import DogmaText
import Foundation
import UIKit

/// A fit read from the general pasteboard.
nonisolated struct PastedFit: Sendable {
    var document: FitDocument
    var shipTypeID: TypeID
    /// The fit's own name, or the ship's English name for plain DNA.
    var name: String
    var warnings: [ImportWarning]
}

/// Reads a fit in EFT, DNA (bare or as a chat link) or the editor's web-link format from the
/// general pasteboard.
///
/// Reading another app's text makes the system ask for permission, so the text is read only on
/// the player's request; `hasStrings` does not read it.
@MainActor
enum FitPasteboard {
    /// Whether the pasteboard holds text at all; neither reads it nor prompts.
    static var hasText: Bool { UIPasteboard.general.hasStrings }

    enum Result {
        case fit(PastedFit)
        /// The pasteboard holds text, but the system gave none: the player declined to paste.
        case denied
        case noFit
    }

    /// Changes whenever the pasteboard content does; reading it does not prompt.
    static var changeCount: Int { UIPasteboard.general.changeCount }

    static func read() async -> Result {
        guard let text = UIPasteboard.general.string else { return .denied }
        guard looksLikeFit(text), let fit = await parse(text) else { return .noFit }
        return .fit(fit)
    }

    // MARK: - Parsing

    nonisolated private static let maxLength = 64 * 1024
    nonisolated private static let webLinkMarker = "#eft="

    /// A cheap filter before the importer: an EFT header `[Ship, Name]`, a DNA line or chat link,
    /// or a web link with an EFT payload.
    nonisolated private static func looksLikeFit(_ text: String) -> Bool {
        guard text.utf8.count <= maxLength else { return false }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.contains("<url=fitting:") || trimmed.contains(webLinkMarker) { return true }
        let line = trimmed.prefix { !$0.isNewline }.trimmingCharacters(in: .whitespaces)
        if line.hasPrefix("[") {
            return line.hasSuffix("]") && line.contains(",")
        }
        let dnaCharacters = Set("0123456789:;_")
        return line.contains(":") && line.allSatisfy(dnaCharacters.contains)
    }

    @concurrent
    nonisolated private static func parse(_ text: String) async -> PastedFit? {
        guard let catalog = try? TypeCatalog(), let names = try? englishNames.get() else { return nil }
        let importer = FitImporter(resolver: names, catalog: catalog)
        let source = webLinkPayload(text) ?? text
        let result: ImportResult
        switch FitImporter.detect(source) {
        case .eft?: result = importer.load(source, as: .eft)
        case .dna?: result = importer.load(source, as: .dna)
        case .xml?, nil: return nil
        }
        guard let document = result.documents.first,
              let shipTypeID = document.pilots.first?.ship?.type,
              let category = catalog.categoryID(of: shipTypeID),
              category == .ship || category == .structure else { return nil }
        let own = document.name?.trimmingCharacters(in: .whitespacesAndNewlines)
        return PastedFit(document: document,
                         shipTypeID: shipTypeID,
                         name: own?.isEmpty == false ? own! : names.name(of: shipTypeID) ?? "",
                         warnings: result.warnings)
    }

    /// English names: EFT and the game's chat links name types in English whatever the app's language.
    /// Built once, so the reverse index the resolver builds on first use is kept.
    nonisolated private static let englishNames = Swift.Result { try TextCatalog.english() }

    /// The EFT text of a web link `…#eft=<base64url>`.
    nonisolated private static func webLinkPayload(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.contains(where: \.isWhitespace),
              let range = trimmed.range(of: webLinkMarker) else { return nil }
        var payload = trimmed[range.upperBound...]
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        payload += String(repeating: "=", count: (4 - payload.count % 4) % 4)
        guard let data = Data(base64Encoded: payload) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
