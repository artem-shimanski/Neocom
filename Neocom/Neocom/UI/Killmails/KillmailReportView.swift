import DogmaKit
import KillmailKit
import LiteRow
import LiteRowUI
import SDEKit
import SwiftUI

/// One killmail: the hull and the victim, where and when, the damage and the estimated worth,
/// "Open in Fitting Tool" for the lost fit, the final blow and the top damage (all attackers
/// a tap away), and what the ship carried, section by section, destroyed or dropped.
///
/// Opens any killmail — the pilot's from the list, or one a mail links to — through
/// `KillmailsSheet.killmail(_:)`.
struct KillmailReportView: View {
    let sheet: KillmailsSheet
    let ref: KillmailRef

    @Environment(MarketSheet.self) private var market

    var body: some View {
        let snapshot = sheet.killmail(ref)
        Group {
            if let report = snapshot.value {
                KillmailReportBody(sheet: sheet, report: report)
            } else if case let .failed(error) = snapshot.state {
                HUDList {
                    Section {
                        HUDEmptyPanel(title: Text("Killmail Unavailable"), message: Text(error.localizedDescription)) {
                            Button("Retry") {
                                Task { await snapshot.refresh() }
                            }
                            .hudProminentButton()
                        }
                        .hudBareRow()
                    }
                }
            } else {
                ProgressView()
                    .controlSize(.large)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .hudScreen()
        .navigationTitle("Killmail")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let url = KillmailText.zKillboard(killID: ref.id) {
                ToolbarItem(placement: .topBarTrailing) {
                    ShareLink(item: url) {
                        Label("Share zKillboard Link", systemImage: "square.and.arrow.up")
                    }
                }
            }
        }
        .task { await snapshot.ensureFresh() }
        .task { await market.ensurePricesFresh() }
    }
}

private struct KillmailReportBody: View {
    let sheet: KillmailsSheet
    let report: ESIKillmail

    @Environment(MarketSheet.self) private var market
    @Environment(FittingStore.self) private var fittingStore
    /// Handed on to the screens pushed from here: a destination does not inherit it.
    @Environment(\.liteDatabase) private var database

    /// Loaded once, in `.task`: tells charges from modules, counts the hull's slots, opens the
    /// lost fit.
    @State private var typeCatalog: TypeCatalog?
    @State private var pushedRoute: FittingRoute?
    @State private var pendingFitID: UUID?
    @State private var openWarnings: [String]?
    @State private var actionError: (any Error)?

    private var killmail: Killmail { report.killmail }

    var body: some View {
        let killmail = killmail
        let naming = KillmailNaming(names: report.names, sheet: sheet)
        let price: (Int64) -> Double? = { market.ccpAverage(of: $0) }
        let catalog = typeCatalog
        KillmailStaticsReader(systemIDs: [killmail.solarSystemID], typeIDs: killmail.reportTypeIDs,
                              groups: true) { statics in
            let side = KillmailText.side(of: killmail, pilotID: sheet.characterID)
            HUDList {
                HUDListSection {
                    KillmailHeaderRow(shipTypeID: killmail.victim.shipTypeID,
                                      shipName: statics.typeName(killmail.victim.shipTypeID),
                                      fallbackSubtitle: statics.groupName(ofType: killmail.victim.shipTypeID),
                                      side: side)
                    victimRow(naming)
                    HUDReadoutRow("System") {
                        statics.placeLine(killmail.solarSystemID,
                                          details: [statics.system(killmail.solarSystemID)?.regionName])
                            ?? Text(verbatim: "—")
                    }
                    HUDReadoutRow("Time", value: EVETime.dateTimeSeconds(killmail.time))
                    HUDReadoutRow("Damage Taken", value: KillmailText.figure(killmail.victim.damageTaken))
                    valueRows(killmail.value(price: price))
                }

                if !killmail.isCapsule, !killmail.fitItems.isEmpty {
                    Section {
                        Button {
                            openInEditor(shipName: statics.typeName(killmail.victim.shipTypeID),
                                         victim: naming.victim(of: killmail))
                        } label: {
                            Label("Open in Fitting Tool", systemImage: "wrench.and.screwdriver")
                                .frame(maxWidth: .infinity)
                        }
                        .hudProminentButton()
                        .hudBareRow()
                    }
                }

                involved(naming: naming, statics: statics)

                ForEach(killmail.itemGroups(isCharge: catalog.map { catalog in { catalog.isCharge($0) } })) { group in
                    HUDListSection {
                        ForEach(group.rows.indices, id: \.self) { index in
                            let row = group.rows[index]
                            NavigationLink(value: DatabaseRoute.type(TypeID(rawValue: UInt32(clamping: row.item.typeID)))) {
                                KillmailItemRowView(row: row, name: statics.typeName(row.item.typeID),
                                                    group: statics.groupName(ofType: row.item.typeID))
                            }
                            .hudRowButton(KillmailItemRowView.rowStyle)
                        }
                    } header: {
                        HUDSectionHeader(Text(verbatim: KillmailText.sectionTitle(group.section))) {
                            Text(verbatim: KillmailText.sectionCount(group, slots: catalog?.slotCount(of: group.section,
                                                                                                         in: killmail)))
                        }
                    }
                }

                Section {
                    HUDFootnote(Text(killmail.isCapsule
                        ? "Implants are always destroyed with the capsule. The capsule itself has no market price. Values are estimates from average market prices."
                        : "Rigs are always destroyed. Every other item either drops into the wreck or is destroyed, and a stack can split between the two. Values are estimates; the hull counts as destroyed. Open in Fitting Tool copies the lost fit into a new fit in My Fits."))
                        .hudBareRow()
                }
            }
        }
        .task {
            if typeCatalog == nil { typeCatalog = try? TypeCatalog() }
        }
        .navigationDestination(item: $pushedRoute) { route in
            if let database {
                route.destination.liteDatabase(database)
            } else {
                route.destination
            }
        }
        .alert(
            "Not Everything Was Copied",
            isPresented: Binding(get: { openWarnings != nil }, set: { if !$0 { openWarnings = nil } }),
            presenting: openWarnings
        ) { _ in
            Button("Open Fit") {
                if let pendingFitID { pushedRoute = .editor(pendingFitID) }
                pendingFitID = nil
            }
            Button("OK", role: .cancel) {
                if let pendingFitID { fittingStore.discardDraft(pendingFitID) }
                pendingFitID = nil
            }
        } message: { warnings in
            Text(warnings.joined(separator: "\n"))
        }
        .alert(
            "Something Went Wrong",
            isPresented: Binding(get: { actionError != nil }, set: { if !$0 { actionError = nil } }),
            presenting: actionError
        ) { _ in
            Button("OK", role: .cancel) {}
        } message: { error in
            Text(error.localizedDescription)
        }
    }

    // MARK: Header

    private func victimRow(_ naming: KillmailNaming) -> some View {
        let victim = killmail.victim
        let isPilot = victim.characterID == sheet.characterID
        let organization = naming.organization(corporationID: victim.corporationID, allianceID: victim.allianceID,
                                               factionID: victim.characterID == nil ? nil : victim.factionID)
        return HStack(spacing: 12) {
            HUDImagePlate(url: KillmailImages.portrait(characterID: victim.characterID,
                                                       corporationID: victim.corporationID),
                          size: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text("Victim")
                    .font(.hudMicro)
                    .tracking(1.5)
                    .textCase(.uppercase)
                    .foregroundStyle(Color.hudInkMuted)
                Text(verbatim: naming.victim(of: killmail))
                    .font(HUDFont.display(16, weight: .semibold, relativeTo: .body))
                    .foregroundStyle(isPilot ? Color.hudAccent : Color.hudInk)
                    .lineLimit(1)
                if !organization.isEmpty {
                    Text(verbatim: organization)
                        .font(HUDFont.mono(11, weight: .regular, relativeTo: .caption))
                        .foregroundStyle(Color.hudInkMuted)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .hudRow(HUDRowStyle(minHeight: 0, verticalPadding: 10))
    }

    @ViewBuilder
    private func valueRows(_ value: KillmailValue) -> some View {
        HUDStatStrip(items: [
            .init(id: 0, label: Text("Destroyed"), value: Text(verbatim: KillmailText.isk(value.destroyed)), color: .hudDanger),
            .init(id: 1, label: Text("Dropped"), value: Text(verbatim: KillmailText.isk(value.dropped)), color: .hudOk),
            .init(id: 2, label: Text("Total"), value: Text(verbatim: KillmailText.isk(value.total))),
        ])
        .hudRow(HUDRowStyle(horizontalPadding: 0, minHeight: 0, verticalPadding: 0))
        Text("Est. ISK · Average market prices · Not an in-game value")
            .font(.hudMicro)
            .tracking(1)
            .textCase(.uppercase)
            .foregroundStyle(Color.hudInkMuted)
            .hudRow(HUDRowStyle(minHeight: 0, verticalPadding: 9))
    }

    // MARK: Involved

    @ViewBuilder
    private func involved(naming: KillmailNaming, statics: KillmailStatics) -> some View {
        let leading = killmail.leadingAttackers
        if !leading.isEmpty {
            HUDListSection {
                ForEach(leading) { row in
                    KillmailLeadingAttackerRow(row: row,
                                               name: naming.attacker(row.attacker, statics: statics),
                                               isPilot: row.attacker.characterID == sheet.characterID,
                                               ship: Self.shipLine(row.attacker, statics: statics))
                }
                if killmail.involvedCount > leading.count {
                    NavigationLink {
                        attackersScreen
                    } label: {
                        HStack(spacing: 10) {
                            Text("All Attackers")
                                .font(HUDFont.display(15, weight: .semibold, relativeTo: .body))
                                .foregroundStyle(Color.hudAccent)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text(verbatim: "\(killmail.involvedCount)")
                                .font(.hudLabel)
                                .tracking(1)
                                .foregroundStyle(Color.hudInkMuted)
                            HUDChevron()
                        }
                        .hudRow(HUDRowStyle(minHeight: 50, verticalPadding: 0))
                    }
                    .hudRowButton(HUDRowStyle(minHeight: 50, verticalPadding: 0))
                }
            } header: {
                HUDSectionHeader(Text("Involved · \(killmail.involvedCount)")) {
                    Text(killmail.isSolo ? "Solo" : "Gang")
                }
            }
        }
    }

    @ViewBuilder
    private var attackersScreen: some View {
        if let database {
            KillmailAttackersView(sheet: sheet, report: report).liteDatabase(database)
        } else {
            KillmailAttackersView(sheet: sheet, report: report)
        }
    }

    /// `RETRIBUTION · SMALL FOCUSED BEAM LASER II`: the ship, and the weapon when it is not the
    /// ship itself.
    static func shipLine(_ attacker: KillmailAttacker, statics: KillmailStatics) -> String {
        [statics.typeName(attacker.shipTypeID), statics.typeName(attacker.separateWeaponTypeID)]
            .compactMap { $0 }
            .joined(separator: " · ")
    }

    // MARK: Fitting Tool

    /// The lost fit as a draft in the Fitting Tool, the way an In Game fitting opens
    /// (`FittingStore.createDraft(from:catalog:)`): stored once the player changes or saves it.
    private func openInEditor(shipName: String?, victim: String) {
        if typeCatalog == nil { typeCatalog = try? TypeCatalog() }
        guard let typeCatalog else {
            actionError = CopyFittingError.catalogUnavailable
            return
        }
        let name = [shipName, victim].compactMap { $0 }.joined(separator: " · ")
        let fitting = ESIFitting(lostFitOf: killmail, name: name,
                                 description: String(localized: "Lost on killmail \(String(killmail.id)), \(EVETime.dateTime(killmail.time))."))
        let (id, warnings) = fittingStore.createDraft(from: fitting, catalog: typeCatalog)
        if warnings.isEmpty {
            pushedRoute = .editor(id)
        } else {
            pendingFitID = id
            openWarnings = warnings
        }
    }
}

/// Portraits and logos for the people on a killmail.
enum KillmailImages {
    /// A pilot's portrait, or — with no pilot — the corporation's logo.
    static func portrait(characterID: Int64?, corporationID: Int64?) -> URL? {
        if let characterID { return EVEImage.portrait(characterID: characterID, size: 64) }
        return corporationID.map { EVEImage.logo(corporationID: $0, size: 64) }
    }
}

/// The report's first row: the hull's render, its name and line (`GALLENTE · CRUISER`), and
/// kill or loss. Leads to the hull in the database.
private struct KillmailHeaderRow: View {
    let shipTypeID: Int64
    let shipName: String?
    let fallbackSubtitle: String?
    let side: KillmailSide?

    @LiteQuery private var context: ShipContextRow?

    init(shipTypeID: Int64, shipName: String?, fallbackSubtitle: String?, side: KillmailSide?) {
        self.shipTypeID = shipTypeID
        self.shipName = shipName
        self.fallbackSubtitle = fallbackSubtitle
        self.side = side
        _context = LiteQuery(FittingBrowser.shipContext(TypeID(rawValue: UInt32(clamping: shipTypeID))))
    }

    var body: some View {
        let style = HUDRowStyle(minHeight: 0, verticalPadding: 0)
        NavigationLink(value: DatabaseRoute.type(TypeID(rawValue: UInt32(clamping: shipTypeID)))) {
            HStack(spacing: 14) {
                HUDImagePlate(url: EVEImage.render(typeID: shipTypeID, size: 256), size: 72,
                              fallbackURL: EVEImage.icon(typeID: shipTypeID, size: 128))
                VStack(alignment: .leading, spacing: 6) {
                    Text(verbatim: shipName ?? String(localized: "Unknown Ship"))
                        .font(HUDFont.display(24, weight: .bold, relativeTo: .title2))
                        .tracking(0.5)
                        .textCase(.uppercase)
                        .lineLimit(2)
                    if let subtitle {
                        Text(verbatim: subtitle)
                            .font(HUDFont.mono(11, weight: .regular, relativeTo: .caption))
                            .tracking(1)
                            .textCase(.uppercase)
                            .foregroundStyle(Color.hudInkMuted)
                    }
                    if let side {
                        HUDStatusChip(text: Text(verbatim: KillmailText.title(of: side)),
                                      color: KillmailText.color(of: side), mark: .dot)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                HUDChevron()
            }
            .padding(.top, 16)
            .padding(.bottom, 14)
            .hudRow(style)
        }
        .hudRowButton(style)
    }

    private var subtitle: String? {
        if let context {
            return [context.raceName, context.groupName].compactMap { $0 }.joined(separator: " · ")
        }
        return fallbackSubtitle
    }
}

/// The final blow or the top damage, in the report's Involved card.
private struct KillmailLeadingAttackerRow: View {
    let row: KillmailAttackerRow
    let name: String
    let isPilot: Bool
    let ship: String

    var body: some View {
        let attacker = row.attacker
        HStack(spacing: 12) {
            HUDImagePlate(url: attacker.characterID.map { EVEImage.portrait(characterID: $0, size: 64) }
                ?? attacker.shipTypeID.map { EVEImage.icon(typeID: $0, size: 64) },
                          size: 36)
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(verbatim: name)
                        .font(HUDFont.display(15, weight: .semibold, relativeTo: .body))
                        .foregroundStyle(isPilot ? Color.hudAccent : Color.hudInk)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(verbatim: KillmailText.share(row.share))
                        .font(HUDFont.mono(13, weight: .semibold, relativeTo: .subheadline))
                        .lineLimit(1)
                        .fixedSize()
                }
                HStack(spacing: 6) {
                    Text(verbatim: ship)
                        .font(HUDFont.mono(11, weight: .regular, relativeTo: .caption))
                        .textCase(.uppercase)
                        .foregroundStyle(Color.hudInkMuted)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    KillmailAttackerMarks(row: row, showsNPC: false)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .hudRow(HUDRowStyle(minHeight: 60, verticalPadding: 10))
    }
}

/// `FINAL BLOW`, `TOP DAMAGE`, and `NPC` where the row asks for it.
struct KillmailAttackerMarks: View {
    let row: KillmailAttackerRow
    var showsNPC = true

    var body: some View {
        HStack(spacing: 6) {
            if row.isFinalBlow { HUDOutlineTag(text: Text("Final Blow")) }
            if row.isTopDamage { HUDOutlineTag(text: Text("Top Damage")) }
            if showsNPC, row.attacker.isNPC { HUDOutlineTag(text: Text(verbatim: "NPC"), color: .hudInkMuted) }
        }
    }
}

/// One item of a section: a module, the charge loaded into it, a drone, a container's
/// contents — with how many were destroyed and how many dropped.
private struct KillmailItemRowView: View {
    static let rowStyle = HUDRowStyle(horizontalPadding: 0, minHeight: 0, verticalPadding: 0)

    let row: KillmailItemRow
    let name: String?
    let group: String?

    /// A nested row starts under its parent's name: past the parent's plate and the gap.
    private static let indent: CGFloat = 48

    var body: some View {
        let nested = row.isNested
        HStack(spacing: 12) {
            HUDItemIcon(typeID: TypeID(rawValue: UInt32(clamping: row.item.typeID)), size: nested ? 28 : 36)
            HUDRowTitle(title: Text(verbatim: name ?? String(localized: "Unknown Item")),
                        subtitle: subtitle,
                        font: HUDFont.display(nested ? 14 : 15, weight: .semibold, relativeTo: .body))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .trailing, spacing: 3) {
                if row.item.quantityDestroyed > 0 {
                    quantity(Text("Destroyed"), color: .hudDanger, row.item.quantityDestroyed)
                }
                if row.item.quantityDropped > 0 {
                    quantity(Text("Dropped"), color: .hudOk, row.item.quantityDropped)
                }
            }
            .fixedSize()
        }
        .padding(.leading, 12 + CGFloat(row.depth) * Self.indent)
        .padding(.trailing, 14)
        .padding(.vertical, nested ? 6 : 8)
        .frame(minHeight: nested ? 48 : 58)
        .accessibilityElement(children: .combine)
        .hudRow(Self.rowStyle)
    }

    private var subtitle: Text? {
        if row.isLoaded {
            return Text(verbatim: [String(localized: "Loaded"), group].compactMap { $0 }.joined(separator: " · "))
        }
        return group.map { Text(verbatim: $0) }
    }

    private func quantity(_ label: Text, color: Color, _ value: Int64) -> some View {
        HStack(spacing: 6) {
            label
                .font(.hudMicro)
                .tracking(1)
                .textCase(.uppercase)
                .foregroundStyle(color)
            Text(verbatim: "×\(KillmailText.figure(value))")
                .font(HUDFont.mono(13, weight: .semibold, relativeTo: .subheadline))
        }
        .lineLimit(1)
    }
}
