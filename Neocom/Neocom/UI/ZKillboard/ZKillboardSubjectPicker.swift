import DogmaKit
import KillmailKit
import LiteRow
import LiteRowUI
import SDEKit
import SwiftUI

/// A subject's picture: a ship's icon, a pilot's portrait, a corporation's, alliance's or
/// faction's logo, a glyph for a group or a place.
struct ZKillboardSubjectPlate: View {
    let subject: KillboardSubject
    var size: CGFloat = 40

    var body: some View {
        switch subject.kind {
        case .shipType:
            HUDItemIcon(typeID: TypeID(rawValue: UInt32(clamping: subject.id)), size: size)
        case .character:
            HUDImagePlate(url: EVEImage.portrait(characterID: subject.id, size: 128), size: size)
        case .corporation, .faction:
            // The image server keeps factions' logos with the corporations'.
            HUDImagePlate(url: EVEImage.logo(corporationID: subject.id, size: 128), size: size)
        case .alliance:
            HUDImagePlate(url: EVEImage.logo(allianceID: subject.id, size: 128), size: size)
        case .shipGroup, .solarSystem, .constellation, .region:
            HUDSymbolPlate(systemImage: ZKillboardText.symbol(of: subject.kind), size: size)
        }
    }
}

/// The line under a subject's name: its kind, and for a ship its group, for a system its
/// security and region — `SHIP · CRUISER`, `SYSTEM · KAMELA 0.4 · …`. Reads the SDE, so it
/// sits under a `liteDatabase`.
struct ZKillboardSubjectDetails: View {
    let subject: KillboardSubject

    var body: some View {
        let kind = Text(verbatim: ZKillboardText.title(of: subject.kind))
        switch subject.kind {
        case .shipType:
            KillmailStaticsReader(systemIDs: [], typeIDs: [subject.id], groups: true) { statics in
                if let group = statics.groupName(ofType: subject.id) {
                    Text("\(kind) · \(Text(verbatim: group))")
                } else {
                    kind
                }
            }
        case .solarSystem:
            KillmailStaticsReader(systemIDs: [subject.id], typeIDs: []) { statics in
                if let system = statics.system(subject.id) {
                    let security = Text(verbatim: SecurityStatus.string(system.securityStatus))
                        .foregroundStyle(SecurityStatus.color(system.securityStatus))
                    Text("\(kind) · \(security) · \(Text(verbatim: system.regionName))")
                } else {
                    kind
                }
            }
        default:
            kind
        }
    }
}

/// The subject picker, one kind at a time: the SDE's ship groups, systems, constellations,
/// regions and factions, or ESI's search for characters, corporations and alliances (as the
/// signed-in character — `ZKillboardSheet.subjects(matching:kind:mail:)`). Ships have the app's
/// own `ShipPickerView`.
///
/// Opens the database itself, like every sheet that reads the static data (see
/// `ShipPickerView`): a sheet does not reliably inherit `liteDatabase` from behind it.
struct ZKillboardSubjectPicker: View {
    let kind: KillboardSubjectKind
    /// Called once, right before the sheet dismisses itself.
    let onSelect: (KillboardSubject) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""

    var body: some View {
        NavigationStack {
            Group {
                if kind.isSearchedOnESI {
                    ZKillboardESISubjects(kind: kind, searchText: searchText, onSelect: select)
                } else {
                    SDESectionView { database in
                        ZKillboardSDESubjects(kind: kind, database: database, searchText: searchText,
                                              onSelect: select)
                    }
                }
            }
            .hudScreen()
            .navigationTitle(ZKillboardText.choose(kind))
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always),
                        prompt: Text(verbatim: ZKillboardText.title(of: kind)))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark", role: .cancel) { dismiss() }
                }
            }
        }
    }

    private func select(_ subject: KillboardSubject) {
        onSelect(subject)
        dismiss()
    }
}

/// One subject to pick: the plate, the name, a line under it.
private struct ZKillboardSubjectButton: View {
    let subject: KillboardSubject
    var subtitle: Text?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                ZKillboardSubjectPlate(subject: subject, size: 36)
                HUDRowTitle(title: Text(verbatim: subject.name), subtitle: subtitle)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .hudRow(HUDRowStyle(minHeight: 52, verticalPadding: 8))
        }
        .hudRowButton(HUDRowStyle(minHeight: 52, verticalPadding: 8))
    }
}

/// A panel in place of the list: what to type, nothing found.
private struct ZKillboardPickerNote: View {
    let title: Text
    let message: Text

    var body: some View {
        HUDList {
            Section {
                HUDEmptyPanel(title: title, message: message)
                    .hudBareRow()
            }
        }
    }
}

// MARK: - SDE

private struct ZKillboardSDESubjects: View {
    let kind: KillboardSubjectKind
    let database: SDEDatabase
    let searchText: String
    let onSelect: (KillboardSubject) -> Void

    var body: some View {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        switch kind {
        case .shipGroup:
            ZKillboardShipGroups(filter: trimmed, onSelect: onSelect)
        case .region:
            ZKillboardRegions(filter: trimmed, onSelect: onSelect)
        case .faction:
            ZKillboardFactions(filter: trimmed, onSelect: onSelect)
        case .solarSystem, .constellation:
            if trimmed.isEmpty {
                ZKillboardPickerNote(title: Text(verbatim: ZKillboardText.choose(kind)),
                                     message: Text("Type a name to search."))
            } else if kind == .solarSystem {
                ZKillboardSystems(pattern: database.pattern(trimmed), searchText: trimmed, onSelect: onSelect)
            } else {
                ZKillboardConstellations(pattern: database.pattern(trimmed), searchText: trimmed, onSelect: onSelect)
            }
        default:
            EmptyView()
        }
    }
}

/// Whether `name` contains `filter`, the way a picker filters: case and diacritics ignored.
private func matches(_ name: String, _ filter: String) -> Bool {
    filter.isEmpty || name.range(of: filter, options: [.caseInsensitive, .diacriticInsensitive]) != nil
}

private struct ZKillboardShipGroups: View {
    let filter: String
    let onSelect: (KillboardSubject) -> Void
    @LiteQuery private var groups: [GroupListRow]

    init(filter: String, onSelect: @escaping (KillboardSubject) -> Void) {
        self.filter = filter
        self.onSelect = onSelect
        _groups = LiteQuery(SDEBrowser.groups(inCategory: .ship))
    }

    var body: some View {
        let shown = groups.filter { matches($0.name, filter) }
        if shown.isEmpty, !groups.isEmpty {
            ContentUnavailableView.search(text: filter)
        } else {
            HUDList {
                HUDListSection(shown, row: { group in
                    ZKillboardSubjectButton(subject: KillboardSubject(kind: .shipGroup, id: Int64(group.id.rawValue),
                                                                      name: group.name),
                                            subtitle: Text("\(group.typeCount) ships")) {
                        onSelect(KillboardSubject(kind: .shipGroup, id: Int64(group.id.rawValue), name: group.name))
                    }
                }, header: {
                    HUDSectionHeader(Text("Ship Groups · \(shown.count)"))
                })
            }
        }
    }
}

private struct ZKillboardRegions: View {
    let filter: String
    let onSelect: (KillboardSubject) -> Void
    @LiteQuery private var regions: [MarketRegionRow]

    init(filter: String, onSelect: @escaping (KillboardSubject) -> Void) {
        self.filter = filter
        self.onSelect = onSelect
        _regions = LiteQuery(KillboardBrowser.regions())
    }

    var body: some View {
        let shown = regions.filter { matches($0.name, filter) }
        if shown.isEmpty, !regions.isEmpty {
            ContentUnavailableView.search(text: filter)
        } else {
            HUDList {
                HUDListSection(shown, row: { region in
                    let subject = KillboardSubject(kind: .region, id: Int64(region.id.rawValue), name: region.name)
                    ZKillboardSubjectButton(subject: subject) { onSelect(subject) }
                }, header: {
                    HUDSectionHeader(Text("Regions · \(shown.count)"))
                })
            }
        }
    }
}

private struct ZKillboardFactions: View {
    let filter: String
    let onSelect: (KillboardSubject) -> Void
    @LiteQuery private var factions: [KillboardFactionRow]

    init(filter: String, onSelect: @escaping (KillboardSubject) -> Void) {
        self.filter = filter
        self.onSelect = onSelect
        _factions = LiteQuery(KillboardBrowser.factions())
    }

    var body: some View {
        let shown = factions.filter { matches($0.name, filter) }
        if shown.isEmpty, !factions.isEmpty {
            ContentUnavailableView.search(text: filter)
        } else {
            HUDList {
                HUDListSection(shown, row: { faction in
                    let subject = KillboardSubject(kind: .faction, id: Int64(faction.id.rawValue), name: faction.name)
                    ZKillboardSubjectButton(subject: subject) { onSelect(subject) }
                }, header: {
                    HUDSectionHeader(Text("Factions · \(shown.count)"))
                })
            }
        }
    }
}

private struct ZKillboardSystems: View {
    let searchText: String
    let onSelect: (KillboardSubject) -> Void
    @LiteQuery private var systems: [MarketSystemRow]

    init(pattern: FTS5Pattern?, searchText: String, onSelect: @escaping (KillboardSubject) -> Void) {
        self.searchText = searchText
        self.onSelect = onSelect
        _systems = LiteQuery(pattern.map { KillboardBrowser.searchSystems($0) })
    }

    var body: some View {
        if systems.isEmpty {
            ContentUnavailableView.search(text: searchText)
        } else {
            HUDList {
                HUDListSection(systems, row: { system in
                    let subject = KillboardSubject(kind: .solarSystem, id: Int64(system.id.rawValue), name: system.name)
                    let security = Text(verbatim: SecurityStatus.string(system.securityStatus))
                        .foregroundStyle(SecurityStatus.color(system.securityStatus))
                    ZKillboardSubjectButton(subject: subject,
                                            subtitle: Text("\(security) · \(Text(verbatim: system.regionName))")) {
                        onSelect(subject)
                    }
                }, header: {
                    HUDSectionHeader(Text("Systems · \(systems.count)"))
                })
            }
        }
    }
}

private struct ZKillboardConstellations: View {
    let searchText: String
    let onSelect: (KillboardSubject) -> Void
    @LiteQuery private var constellations: [KillboardConstellationRow]

    init(pattern: FTS5Pattern?, searchText: String, onSelect: @escaping (KillboardSubject) -> Void) {
        self.searchText = searchText
        self.onSelect = onSelect
        _constellations = LiteQuery(pattern.map { KillboardBrowser.searchConstellations($0) })
    }

    var body: some View {
        if constellations.isEmpty {
            ContentUnavailableView.search(text: searchText)
        } else {
            HUDList {
                HUDListSection(constellations, row: { row in
                    let subject = KillboardSubject(kind: .constellation, id: Int64(row.id.rawValue), name: row.name)
                    ZKillboardSubjectButton(subject: subject, subtitle: Text(verbatim: row.regionName)) {
                        onSelect(subject)
                    }
                }, header: {
                    HUDSectionHeader(Text("Constellations · \(constellations.count)"))
                })
            }
        }
    }
}

// MARK: - ESI

/// Characters, corporations and alliances: ESI's search as the signed-in character, from three
/// letters on, after a pause in typing. Says so when there is no character or no permission,
/// rather than showing nothing.
private struct ZKillboardESISubjects: View {
    static let minimumLength = 3
    static let debounce: Duration = .milliseconds(400)

    let kind: KillboardSubjectKind
    let searchText: String
    let onSelect: (KillboardSubject) -> Void

    @Environment(AccountStore.self) private var accounts
    @Environment(ZKillboardSheet.self) private var zkillboard
    @State private var results: [KillboardSubject] = []
    @State private var searchedText = ""
    @State private var isSearching = false

    var body: some View {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let mail = accounts.currentMail
        Group {
            if mail == nil {
                HUDList {
                    Section {
                        HUDGrantAccessPanel(title: Text("No Character"),
                                            message: Text("Pilots, corporations and alliances are found through EVE's own search, which needs a signed-in character. Ships, groups, places and factions need none."))
                            .hudBareRow()
                    }
                }
            } else if let mail, !mail.hasSearchScope {
                HUDList {
                    Section {
                        HUDGrantAccessPanel(title: Text("No Search Access"),
                                            message: Text("Finding pilots, corporations and alliances needs one more permission. Sign in to EVE again and allow Neocom to search."))
                            .hudBareRow()
                    }
                }
            } else if trimmed.count < Self.minimumLength {
                ZKillboardPickerNote(title: Text(verbatim: ZKillboardText.choose(kind)),
                                     message: Text("Type three letters or more to search all of EVE."))
            } else if results.isEmpty {
                if isSearching || searchedText != trimmed {
                    ProgressView()
                        .controlSize(.large)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ContentUnavailableView.search(text: trimmed)
                }
            } else {
                HUDList {
                    HUDListSection(results, row: { subject in
                        ZKillboardSubjectButton(subject: subject) { onSelect(subject) }
                    }, header: {
                        HUDSectionHeader(Text("EVE · \(results.count)")) {
                            if isSearching { ProgressView().controlSize(.mini) }
                        }
                    })
                }
            }
        }
        .task(id: SearchKey(text: trimmed, mail: mail.map(ObjectIdentifier.init), hasScope: mail?.hasSearchScope ?? false)) {
            await search(trimmed, mail: mail)
        }
    }

    /// What a search is for: the text, and whose search it runs as — another character signed
    /// in, or the scope granted, asks again.
    private struct SearchKey: Hashable {
        var text: String
        var mail: ObjectIdentifier?
        var hasScope: Bool
    }

    /// A new text or account cancels the old one's task (`task(id:)`), so a stale answer never
    /// lands.
    private func search(_ text: String, mail: MailSheet?) async {
        guard let mail, mail.hasSearchScope, text.count >= Self.minimumLength else {
            results = []
            searchedText = text
            return
        }
        isSearching = true
        defer { if !Task.isCancelled { isSearching = false } }
        do {
            try await Task.sleep(for: Self.debounce)
        } catch {
            return
        }
        let found = await zkillboard.subjects(matching: text, kind: kind, mail: mail)
        guard !Task.isCancelled else { return }
        results = found
        searchedText = text
    }
}
