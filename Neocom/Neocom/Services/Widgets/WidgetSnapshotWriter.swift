import CryptoKit
import Foundation
import LiteRow
import SDEKit
import TrainingKit
import TrainingTimeline
import WidgetKit

/// The only writer of the widgets' snapshot (`WidgetSnapshot`) in the App Group.
///
/// Makes no ESI requests. A pilot's queue comes from the training snapshot of their
/// `CharacterSheet`, or from its disk cache when the sheet does not exist. Portraits are taken
/// from `URLCache.shared`.
///
/// Rebuilt at launch and when a sheet reports a new snapshot or the account list, active pilot,
/// a plan or the static data's language changes. The static data is opened only for a pilot whose
/// inputs changed since the last write, and the file is written and the widgets reloaded only
/// when the displayed content changed.
@MainActor
final class WidgetSnapshotWriter {
    static let shared = WidgetSnapshotWriter()

    /// How far `fetchedAt` may move before that alone triggers a write.
    private static let fetchedAtTolerance: TimeInterval = 3600
    /// The plan entries a pilot carries.
    private static let planLimit = 5
    /// `UserDefaults` key of the input digests.
    private static let digestsKey = "WidgetSnapshotDigests"

    private weak var accounts: AccountStore?
    private weak var sde: SDEStore?
    private var dirty = false
    private var flushing: Task<Void, Never>?

    /// The snapshot currently in the file.
    private var written: WidgetSnapshot?
    /// Per pilot, a digest of the training snapshot and plan the written pilot was built from.
    /// Persisted, so an unchanged pilot is reused from the file without the static data.
    private var digests: [String: String] = [:]
    /// Skill names read so far, seeded from the file.
    private var names: [TypeID: String] = [:]

    private init() {}

    /// Called once at launch; builds the snapshot from disk without fetching.
    func attach(accounts: AccountStore, sde: SDEStore) {
        self.accounts = accounts
        self.sde = sde
        written = WidgetStore.read()
        digests = written == nil ? [:] : (UserDefaults.standard.dictionary(forKey: Self.digestsKey) as? [String: String] ?? [:])
        for pilot in written?.pilots ?? [] {
            for entry in pilot.training?.queue ?? [] { names[TypeID(rawValue: UInt32(clamping: entry.skillID))] = entry.name }
            for entry in pilot.plan { names[TypeID(rawValue: UInt32(clamping: entry.skillID))] = entry.name }
        }
        setNeedsUpdate()
    }

    /// Marks the widgets' content as possibly changed; updates are debounced and coalesced.
    func setNeedsUpdate() {
        guard accounts != nil else { return }
        dirty = true
        guard flushing == nil else { return }
        flushing = Task {
            try? await Task.sleep(for: .milliseconds(500))
            while dirty {
                dirty = false
                await build()
            }
            flushing = nil
        }
    }

    /// Builds now and returns once the file is up to date.
    func flush() async {
        setNeedsUpdate()
        await flushing?.value
    }

    /// Rebuilds every pilot after the static data language changed.
    func languageChanged() {
        names = [:]
        digests = [:]
        setNeedsUpdate()
    }

    // MARK: - Building

    private func build() async {
        guard let accounts else { return }

        var pilots: [WidgetSnapshot.Pilot] = []
        var newDigests: [String: String] = [:]
        for account in accounts.accounts {
            let (snapshot, fetchedAt) = await training(of: account, accounts: accounts)
            let plan = accounts.plan(for: account)?.entries ?? []
            let key = String(account.id)
            let digest = Self.digest(snapshot: snapshot, plan: plan)

            var pilot: WidgetSnapshot.Pilot
            if let digest, digest == digests[key], let previous = written?[account.id] {
                pilot = previous
            } else {
                pilot = await makePilot(account, snapshot: snapshot, fetchedAt: fetchedAt, plan: plan)
            }
            // These do not need the static data and are refreshed on every build.
            pilot.name = account.characterName
            if let fetchedAt { pilot.training?.fetchedAt = fetchedAt }
            pilot.portraitFile = portrait(of: account)

            newDigests[key] = digest
            pilots.append(pilot)
        }

        let snapshot = WidgetSnapshot(activePilotID: accounts.currentAccountID, pilots: pilots)
        if let written, !Self.differs(snapshot, from: written) {
            // Nothing to write, but the stored digests still describe the file.
            storeDigests(newDigests)
            return
        }
        guard WidgetStore.write(snapshot) else { return }
        written = snapshot
        storeDigests(newDigests)
        WidgetStore.removePortraits(keeping: Set(pilots.map(\.id)))
        for kind in WidgetKind.all {
            WidgetCenter.shared.reloadTimelines(ofKind: kind)
        }
    }

    private func storeDigests(_ new: [String: String]) {
        guard new != digests else { return }
        digests = new
        UserDefaults.standard.set(new, forKey: Self.digestsKey)
    }

    /// The pilot's training snapshot: the sheet's, otherwise the cache file read off the main actor.
    private func training(of account: Account, accounts: AccountStore) async -> (CharacterSnapshot?, Date?) {
        if let sheet = accounts.existingSheets(for: account).sheet, let snapshot = sheet.snapshot {
            return (snapshot, sheet.fetchedAt)
        }
        let characterID = account.id
        let cached = await Task.detached {
            ESICache().load(CharacterSnapshot.self, kind: CharacterSheet.trainingCacheKind,
                            characterID: characterID)
        }.value
        // A sheet created while the file was read takes precedence.
        if let sheet = accounts.existingSheets(for: account).sheet, let snapshot = sheet.snapshot {
            return (snapshot, sheet.fetchedAt)
        }
        return (cached?.value, cached?.fetchedAt)
    }

    /// The part of a pilot that needs the static data: skill names, points missing from ESI and
    /// the times of paused entries and of the plan.
    private func makePilot(_ account: Account, snapshot: CharacterSnapshot?, fetchedAt: Date?,
                           plan: [SkillCatalog.Requirement]) async -> WidgetSnapshot.Pilot {
        var pilot = WidgetSnapshot.Pilot(id: account.id, name: account.characterName)
        guard let snapshot, let fetchedAt else { return pilot }

        let catalog = await catalog()
        await loadNames(snapshot.queue.map(\.skillID) + plan.map(\.skillID))
        pilot.training = WidgetSnapshot.Training(snapshot: snapshot, fetchedAt: fetchedAt, catalog: catalog,
                                                 previous: written?[account.id]?.training, name: name(of:))
        guard let catalog, !plan.isEmpty else { return pilot }

        let trained = Pilot(snapshot: snapshot, catalog: catalog, now: .now)
        func entries() -> [WidgetSnapshot.PlanEntry] {
            WidgetSnapshot.PlanEntry.entries(plan: plan, pilot: trained, catalog: catalog,
                                             limit: Self.planLimit, name: name(of:))
        }
        pilot.plan = entries()
        // The plan queue expands prerequisites, whose names may be unread.
        let missing = pilot.plan.map { TypeID(rawValue: UInt32(clamping: $0.skillID)) }.filter { names[$0] == nil }
        if !missing.isEmpty {
            await loadNames(missing)
            pilot.plan = entries()
        }
        return pilot
    }

    private func name(of skill: TypeID) -> String {
        names[skill] ?? "#\(skill.rawValue)"
    }

    /// The skill catalog, opening the static data if needed; `nil` when it cannot be opened.
    private func catalog() async -> SkillCatalog? {
        guard let sde else { return nil }
        if let catalog = sde.skillCatalog { return catalog }
        await sde.load()
        return sde.skillCatalog
    }

    /// Reads the names of `ids` not read yet.
    private func loadNames(_ ids: [TypeID]) async {
        let missing = Array(Set(ids).filter { names[$0] == nil })
        guard let sde, !missing.isEmpty else { return }
        await sde.load()
        guard case let .ready(database) = sde.state else { return }
        let query = SDEBrowser.typeNames(of: missing)
        let rows = (try? await database.database.read { reader in try reader.fetchAll(query) }) ?? []
        for row in rows {
            names[row.id] = row.name
        }
    }

    /// The portrait's file name in the App Group, written once from the image cached by the app;
    /// `nil` until cached.
    private func portrait(of account: Account) -> String? {
        if WidgetStore.hasPortrait(characterID: account.id) {
            return WidgetStore.portraitFileName(characterID: account.id)
        }
        guard let response = URLCache.shared.cachedResponse(for: URLRequest(url: account.portraitURL)),
              !response.data.isEmpty
        else { return nil }
        return WidgetStore.writePortrait(response.data, characterID: account.id)
    }

    // MARK: - Comparing

    private struct Inputs: Encodable {
        var snapshot: CharacterSnapshot?
        var plan: [[UInt32]]
    }

    /// A launch-stable digest of a pilot's inputs.
    private static func digest(snapshot: CharacterSnapshot?, plan: [SkillCatalog.Requirement]) -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let inputs = Inputs(snapshot: snapshot,
                            plan: plan.map { [$0.skillID.rawValue, UInt32(clamping: $0.level)] })
        guard let data = try? encoder.encode(inputs) else { return nil }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// Whether `new` shows anything `old` does not; `fetchedAt` counts only when it moved by more
    /// than `fetchedAtTolerance`.
    private static func differs(_ new: WidgetSnapshot, from old: WidgetSnapshot) -> Bool {
        guard new != old else { return false }
        guard new.activePilotID == old.activePilotID, new.pilots.count == old.pilots.count else { return true }
        var aligned = new
        for index in aligned.pilots.indices {
            guard let newDate = aligned.pilots[index].training?.fetchedAt,
                  let oldDate = old.pilots[index].training?.fetchedAt,
                  abs(newDate.timeIntervalSince(oldDate)) < fetchedAtTolerance
            else { continue }
            aligned.pilots[index].training?.fetchedAt = oldDate
        }
        return aligned != old
    }
}
