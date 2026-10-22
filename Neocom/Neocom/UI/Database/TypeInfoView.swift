import DogmaKit
import LiteRow
import LiteRowUI
import SDEKit
import SwiftUI
import TrainingKit

/// One type with its description and dogma attributes. `fitValues` are the attribute values the
/// type has inside a fit (skills and modules applied); when given, the screen offers both
/// readings, otherwise it is the plain SDE page.
struct TypeInfoView: View {
    let typeID: TypeID
    let fitValues: [AttributeID: Double]?
    let fitContext: TypeInfoFitContext?

    @LiteQuery private var summary: TypeSummary?

    init(typeID: TypeID, fitValues: [AttributeID: Double]? = nil, fitContext: TypeInfoFitContext? = nil) {
        self.typeID = typeID
        self.fitValues = fitValues
        self.fitContext = fitContext
        _summary = LiteQuery(SDEBrowser.summary(of: typeID))
    }

    var body: some View {
        Group {
            if let summary {
                TypeInfoBody(summary: summary, fitValues: fitValues, fitContext: fitContext)
            } else {
                ContentUnavailableView(
                    "Unknown Item",
                    systemImage: "questionmark.square.dashed",
                    description: Text("Item \(typeID.rawValue, format: .number.grouping(.never)) is not in the database.")
                )
            }
        }
        .hudScreen()
        .navigationTitle(summary?.name ?? "")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// What the screen says about the fit it is shown in, as plain strings.
struct TypeInfoFitContext {
    /// The fit's name; empty for an unnamed fit.
    var fitName: String
    /// The set the fit is calculated for (`All V`, the pilot's name, `Custom`).
    var skillsLabel: String
    /// Where the item sits (`High slot`); only a module has one.
    var slotName: String?
}

/// Everything else about the type, keyed off the confirmed id; a separate view because
/// `@LiteQuery` builds its query in `init`.
private struct TypeInfoBody: View {
    let summary: TypeSummary
    let fitValues: [AttributeID: Double]?
    let fitContext: TypeInfoFitContext?

    @State private var showsFit = true

    @LiteQuery private var group: GroupHeader?
    @LiteQuery private var attributes: [TypeAttributeRow]
    @LiteQuery private var referencedTypes: [TypeReference]
    @LiteQuery private var referencedGroups: [GroupReference]
    @LiteQuery private var referencedAttributes: [AttributeReference]

    init(summary: TypeSummary, fitValues: [AttributeID: Double]?, fitContext: TypeInfoFitContext?) {
        self.summary = summary
        self.fitValues = fitValues
        self.fitContext = fitContext
        _group = LiteQuery(SDEBrowser.header(ofGroup: summary.groupID))
        _attributes = LiteQuery(SDEBrowser.attributes(of: summary.id))
        _referencedTypes = LiteQuery(SDEBrowser.referencedTypes(of: summary.id))
        _referencedGroups = LiteQuery(SDEBrowser.referencedGroups(of: summary.id))
        _referencedAttributes = LiteQuery(SDEBrowser.referencedAttributes(of: summary.id))
    }

    @Environment(\.trainingContext) private var trainingContext

    /// The type's attributes with the fit's numbers swapped in. The SDE figure stays as `baseValue`,
    /// so a row can show what the fit changed. A row the fit has no value for keeps its SDE one; the
    /// fit never adds or drops rows. Id-valued rows (`requiredSkill1`, `canFitShipGroup01`) are
    /// substituted like any other; `AttributeRowView` draws a reference it cannot name as a plain
    /// value.
    private var rows: [TypeAttributeRow] {
        guard showsFit, let fitValues else { return attributes }
        return attributes.map { row in
            guard let value = fitValues[row.id] else { return row }
            var fitted = row
            fitted.value = value
            return fitted
        }
    }

    var body: some View {
        let layout = AttributeLayout(rows: rows)
        HUDList {
            HUDListSection {
                header
                if fitValues != nil, let fitContext {
                    modeCaption(fitContext)
                }
                if let group {
                    NavigationLink(value: DatabaseRoute.group(group.id)) {
                        HUDReadoutRow(Text(group.categoryName)) {
                            HStack(spacing: 8) {
                                Text(group.name)
                                HUDChevron()
                            }
                        }
                    }
                    .hudRowButton(.readout)
                }
            }

            if summary.isOnMarket {
                MarketPriceCard(typeID: summary.id)
            }

            if let description = summary.descriptionText, !description.isEmpty {
                Section {
                    HUDDescriptionPanel(text: EVEMarkup.attributedString(from: description))
                        .hudBareRow()
                } header: {
                    HUDSectionHeader(Text("Description")).hudListHeader()
                }
            }

            RequiredSkillsSection(typeID: summary.id)

            // Only when the type is a skill and there is a pilot to train it.
            SkillLevelsSection(skillID: summary.id)

            MasterySection(typeID: summary.id)

            ForEach(layout.sections) { section in
                switch section.kind {
                case .defenses:
                    if let defenses = layout.defenses {
                        DefensesCard(defenses: defenses)
                    }
                case let .attributes(rows, slots):
                    HUDListSection {
                        if !slots.isEmpty {
                            HUDStatStrip(items: slots, valueFont: HUDFont.mono(18, weight: .semibold, relativeTo: .title3))
                                .hudRow(HUDRowStyle(horizontalPadding: 0, minHeight: 0, verticalPadding: 0))
                        }
                        ForEach(rows) { row in
                            AttributeRowView(
                                row: row,
                                typeNames: typeNames,
                                groupNames: groupNames,
                                attributeNames: attributeNames
                            )
                        }
                    } header: {
                        HUDSectionHeader(verbatim: section.title)
                    }
                }
            }
        }
        .toolbar {
            if fitValues != nil {
                // In the middle of the bar, where the title would be.
                ToolbarItem(placement: .principal) {
                    Picker("Values", selection: $showsFit) {
                        Text("Base").tag(false)
                        Text("In Fit").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 200)
                }
            }
        }
    }

    /// Which reading is on screen: the fit and its skill set, or the database's own numbers. The dot
    /// is the accent while the fit's values show.
    private func modeCaption(_ context: TypeInfoFitContext) -> some View {
        let text = showsFit
            ? ([String(localized: "In Fit")] + [context.fitName].filter { !$0.isEmpty } + [context.skillsLabel])
                .joined(separator: " · ")
            : String(localized: "Base values from the database")
        return HStack(spacing: 8) {
            Circle()
                .fill(showsFit ? Color.hudAccent : Color.hudInkFaint)
                .frame(width: 6, height: 6)
            Text(verbatim: text)
                .font(HUDFont.mono(11, weight: .regular, relativeTo: .caption))
                .textCase(.uppercase)
                .foregroundStyle(Color.hudInkMuted)
        }
        .hudRow(HUDRowStyle(minHeight: 0, verticalPadding: 11))
    }

    private var header: some View {
        HStack(spacing: 14) {
            HUDItemIcon(typeID: summary.id, size: 72)
            VStack(alignment: .leading, spacing: 8) {
                Text(summary.name)
                    .font(.hudPilotName)
                    .tracking(0.5)
                    .textCase(.uppercase)
                if let skill = skillProgress {
                    HUDLevelBar(trained: skill.level, training: skill.training, paused: skill.paused,
                                height: 8, spacing: 3)
                }
                if fitValues != nil, let fitContext {
                    fittedMeta(fitContext)
                } else if let caption = headerCaption {
                    Text(verbatim: caption)
                        .font(.hudCaption)
                        .textCase(.uppercase)
                        .foregroundStyle(Color.hudInkMuted)
                }
            }
            Spacer(minLength: 0)
        }
        .hudRow(HUDRowStyle(minHeight: 0, verticalPadding: HUDMetrics.gutter))
    }

    /// The header line under the name for an item in a fit: the tier badge, then the kind and slot
    /// (`HYBRID WEAPON · HIGH SLOT`). The Database shows the plain meta group text instead. The badge
    /// is tinted by `MetaTier.badgeColor`.
    private func fittedMeta(_ context: TypeInfoFitContext) -> some View {
        let badge = MetaTier.badgeText(id: summary.metaGroupID, name: summary.metaGroupName)
        let tint = MetaTier.badgeColor(id: summary.metaGroupID, red: summary.metaColorRed,
                                       green: summary.metaColorGreen, blue: summary.metaColorBlue)
        let caption = [group?.name, context.slotName].compactMap { $0 }.joined(separator: " · ")
        return HStack(alignment: .firstTextBaseline, spacing: 6) {
            if let badge {
                HUDMetaBadge(text: Text(verbatim: badge), color: tint)
            }
            if !caption.isEmpty {
                Text(verbatim: caption)
                    .font(.hudCaption)
                    .textCase(.uppercase)
                    .foregroundStyle(Color.hudInkMuted)
            }
        }
    }

    /// For a skill: the level the pilot has, and the one the game is training, if any.
    private var skillProgress: (level: Int, training: Int?, paused: Bool)? {
        guard let context = trainingContext, context.catalog.isSkill(summary.id),
              let pilot = context.pilot else { return nil }
        let entry = pilot.queue.first { $0.skillID == summary.id }
        return (pilot.trainedLevel(of: summary.id), entry?.finishedLevel, entry != nil && entry?.finishDate == nil)
    }

    /// "LEVEL IV · RANK 3" for a skill, the meta group for everything else.
    private var headerCaption: String? {
        if let context = trainingContext, let skill = context.catalog[summary.id] {
            let rank = String(localized: "Rank \(skill.rank.formatted(.number.precision(.fractionLength(0...1))))")
            guard let progress = skillProgress else { return rank }
            let level = progress.level == 0
                ? String(localized: "Not trained")
                : String(localized: "Level \(SkillLevel.roman(progress.level))")
            return "\(level) · \(rank)"
        }
        return summary.metaGroupName
    }

    private var typeNames: [TypeID: String] {
        Dictionary(referencedTypes.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
    }

    private var groupNames: [GroupID: String] {
        Dictionary(referencedGroups.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
    }

    private var attributeNames: [AttributeID: String] {
        Dictionary(
            referencedAttributes.map { ($0.id, $0.displayName.flatMap { $0.isEmpty ? nil : $0 } ?? $0.name) },
            uniquingKeysWith: { first, _ in first }
        )
    }
}

/// One attribute. A row that names another type or group is a link to it; everything else is
/// a value.
private struct AttributeRowView: View {
    let row: TypeAttributeRow
    let typeNames: [TypeID: String]
    let groupNames: [GroupID: String]
    let attributeNames: [AttributeID: String]

    var body: some View {
        switch row.reference {
        case let .type(id) where typeNames[id] != nil:
            NavigationLink(value: DatabaseRoute.type(id)) {
                linkRow(typeNames[id] ?? "")
            }
            .hudRowButton(.readout)
        case let .group(id) where groupNames[id] != nil:
            NavigationLink(value: DatabaseRoute.group(id)) {
                linkRow(groupNames[id] ?? "")
            }
            .hudRowButton(.readout)
        case let .attribute(id) where attributeNames[id] != nil:
            HUDReadoutRow(Text(row.title), value: attributeNames[id] ?? "")
        default:
            // Includes references whose target is not in the database; they render as plain values.
            if row.isChangedByFit {
                HUDReadoutRow(Text(row.title)) {
                    HUDChangedValue(value: row.formattedValue, base: row.formattedBaseValue)
                }
            } else {
                HUDReadoutRow(Text(row.title), value: row.formattedValue)
            }
        }
    }

    private func linkRow(_ value: String) -> some View {
        HUDReadoutRow(Text(row.title)) {
            HStack(spacing: 8) {
                Text(value)
                HUDChevron()
            }
        }
    }
}

/// Attributes under the heading CCP files them under.
private struct AttributeSection: Identifiable {
    var id: String { title }
    var title: String
    var rows: [TypeAttributeRow]

    private static let other = String(localized: "Other")

    /// Groups rows already ordered by category, keeping that order, with "Other" moved to the end.
    static func sections(from rows: [TypeAttributeRow]) -> [AttributeSection] {
        var order: [String] = []
        var byTitle: [String: [TypeAttributeRow]] = [:]
        for row in rows {
            let title = title(of: row)
            if byTitle[title] == nil { order.append(title) }
            byTitle[title, default: []].append(row)
        }
        if let index = order.firstIndex(of: other) {
            order.append(order.remove(at: index))
        }
        return order.map { AttributeSection(title: $0, rows: byTitle[$0] ?? []) }
    }

    private static func title(of row: TypeAttributeRow) -> String {
        guard let name = row.categoryName, !name.isEmpty, name != "NULL" else { return other }
        return name
    }
}

// MARK: - Fitting and defenses

/// How the attribute sections of one type are laid out: CCP's categories in CCP's order, with
/// the slot counts as a strip and the Shield, Armor and Structure attributes of a ship pulled out
/// into one matrix where the first of those categories stood.
private struct AttributeLayout {
    struct Section: Identifiable {
        enum Kind {
            case attributes([TypeAttributeRow], slots: [HUDStatStrip.Item])
            case defenses
        }

        var id: String
        var title: String
        var kind: Kind
    }

    private static let slotAttributes: [(AttributeID, LocalizedStringKey)] = [
        (.hiSlots, "High"), (.medSlots, "Med"), (.lowSlots, "Low"), (.rigSlots, "Rig"),
    ]

    var sections: [Section] = []
    var defenses: Defenses?

    init(rows: [TypeAttributeRow]) {
        let byID = Dictionary(rows.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let defenses = Defenses(attributes: byID)
        self.defenses = defenses
        let pulled = defenses?.attributeIDs ?? []
        let slotIDs = Set(Self.slotAttributes.map(\.0))

        var placedDefenses = false
        for section in AttributeSection.sections(from: rows) {
            let holdsDefenses = section.rows.contains { pulled.contains($0.id) }
            if holdsDefenses, !placedDefenses {
                sections.append(Section(id: "defenses", title: "", kind: .defenses))
                placedDefenses = true
            }
            let slots = Self.slotAttributes.enumerated().compactMap { index, slot -> HUDStatStrip.Item? in
                guard let row = section.rows.first(where: { $0.id == slot.0 }) else { return nil }
                return HUDStatStrip.Item(id: index, label: Text(slot.1), value: Text(row.formattedValue))
            }
            let remaining = section.rows.filter { !pulled.contains($0.id) && !(slots.isEmpty ? false : slotIDs.contains($0.id)) }
            guard !remaining.isEmpty || !slots.isEmpty else { continue }
            sections.append(Section(id: section.id, title: section.title, kind: .attributes(remaining, slots: slots)))
        }
    }
}

/// Hit points and resistances of the three layers; `nil` unless all three hit point pools exist.
private struct Defenses {
    struct Layer: Identifiable {
        var id: Int
        var title: LocalizedStringKey
        var hp: Double
        var resistances: [Double?]
    }

    var layers: [Layer]
    var shieldRecharge: TypeAttributeRow?
    var attributeIDs: Set<AttributeID>

    init?(attributes: [AttributeID: TypeAttributeRow]) {
        let definitions: [(LocalizedStringKey, AttributeID, [AttributeID])] = [
            ("Shield", .shieldCapacity, [.shieldEmDamageResonance, .shieldThermalDamageResonance,
                                         .shieldKineticDamageResonance, .shieldExplosiveDamageResonance]),
            ("Armor", .armorHP, [.armorEmDamageResonance, .armorThermalDamageResonance,
                                 .armorKineticDamageResonance, .armorExplosiveDamageResonance]),
            ("Structure", .hp, [.emDamageResonance, .thermalDamageResonance,
                                .kineticDamageResonance, .explosiveDamageResonance]),
        ]
        guard definitions.allSatisfy({ attributes[$0.1] != nil }) else { return nil }

        layers = definitions.enumerated().map { index, definition in
            Layer(id: index,
                  title: definition.0,
                  hp: attributes[definition.1]?.value ?? 0,
                  // A resonance is what gets through: the resistance is what is left of 1.
                  resistances: definition.2.map { id in attributes[id].map { 1 - $0.value } })
        }
        shieldRecharge = attributes[.shieldRechargeRate]
        attributeIDs = Set(definitions.flatMap { [$0.1] + $0.2 } + [.shieldRechargeRate])
    }
}

/// The resistance matrix, in the shared `HUDDefenseMatrix` that the fit's `TANK` section draws.
private struct DefensesCard: View {
    let defenses: Defenses

    var body: some View {
        HUDListSection("Defenses") {
            // The matrix pads itself horizontally and draws the rules between its own layers.
            HUDDefenseMatrix(
                layers: defenses.layers.map { layer in
                    HUDDefenseMatrix.Layer(
                        id: layer.id,
                        title: Text(layer.title),
                        resistances: layer.resistances,
                        hitPoints: Text(verbatim: layer.hp.formatted(.number.precision(.fractionLength(0)))))
                },
                hitPointsColumn: Text("HP"))
            .hudRow(HUDRowStyle(horizontalPadding: 0, minHeight: 0, verticalPadding: 0))

            if let recharge = defenses.shieldRecharge {
                HUDReadoutRow("Shield Recharge", value: recharge.formattedValue)
            }
        }
    }
}
