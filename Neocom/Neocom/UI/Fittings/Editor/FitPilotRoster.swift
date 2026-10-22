import DogmaKit
import SDEKit
import SwiftUI
import TrainingKit

/// The signed-in characters a fit's skills and implants can be copied from.
///
/// Each character's data comes from their own `CharacterSheet` (`AccountStore.sheet(for:)`);
/// `ensureFresh()` asks each sheet to refresh. The fit remembers no character: the chosen pilot is
/// the one whose trained set, or implants, the fit holds exactly. A fit matching nobody reads
/// `Custom`.
@MainActor
struct FitPilotRoster {
    struct Member: Identifiable {
        let account: Account
        let sheet: CharacterSheet
        /// `nil` until the training snapshot has arrived; a zero fallback must not be offered as
        /// skills.
        let pilot: Pilot?

        var id: Int64 { account.id }

        /// What the character has trained, as a set.
        var skills: FitDocument.Skills? {
            pilot.map { FitDocument.Skills.trained(by: $0) }
        }

        /// The implants the character wears; `nil` until the snapshot has arrived.
        var implants: [TypeID]? {
            sheet.snapshot?.implants
        }
    }

    /// In the order the accounts screen lists them.
    let members: [Member]
    let currentID: Int64?

    init(accounts: AccountStore, catalog: SkillCatalog?) {
        members = accounts.pickerAccounts.map { account in
            let sheet = accounts.sheet(for: account)
            let pilot = sheet.snapshot == nil ? nil : catalog.map { sheet.pilot(using: $0) }
            return Member(account: account, sheet: sheet, pilot: pilot)
        }
        currentID = accounts.currentAccountID
    }

    var current: Member? {
        members.first { $0.id == currentID }
    }

    /// The character whose trained set `skills` is exactly, the selected character first on a tie.
    func member(trained skills: FitDocument.Skills) -> Member? {
        if let current, current.skills == skills { return current }
        return members.first { $0.id != currentID && $0.skills == skills }
    }

    /// The character whose implants the fit carries exactly: by implants alone, never one wearing
    /// none.
    func member(wearing implants: [TypeID]) -> Member? {
        let implants = implants.sortedIDs
        guard !implants.isEmpty else { return nil }
        if let current, current.implants?.sortedIDs == implants { return current }
        return members.first { $0.id != currentID && $0.implants?.sortedIDs == implants }
    }

    /// The set in words, by `FitDocument.Skills.SetKind`, naming any signed-in character.
    func label(of skills: FitDocument.Skills) -> String {
        let match = member(trained: skills)
        return skills.setKind(comparedTo: match?.skills)
            .label(characterName: match?.account.characterName)
    }

    /// Brings every character's training snapshot up to date, in parallel.
    func ensureFresh() async {
        await withTaskGroup(of: Void.self) { group in
            for member in members {
                let sheet = member.sheet
                group.addTask { await sheet.ensureFresh() }
            }
        }
    }

    /// The key a `.task` over `ensureFresh()` restarts on: the set of characters.
    var memberIDs: [Int64] {
        members.map(\.id)
    }
}
