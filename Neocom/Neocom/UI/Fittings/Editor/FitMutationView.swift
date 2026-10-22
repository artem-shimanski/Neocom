import DogmaKit
import LiteRow
import LiteRowUI
import SDEKit
import SwiftUI

/// The token `navigationDestination(item:)` keys the mutation screen on: the module it edits.
struct FitMutationRoute: Hashable {
    var moduleID: ModuleID
}

/// One module's mutation: which mutaplasmid is on it, and every roll it has, each with a slider.
///
/// Pushed from the module's sheet on the editor's own model. A module that is not mutated yet
/// shows only the list of mutaplasmids; nothing is applied until one is picked. The engine's
/// state (type, mutaplasmid, rolls with bounds) comes from `FitSnapshot.Mutation`; the SDE's
/// (mutaplasmids, ranges, attribute names and units) is read through `@LiteQuery`.
struct FitMutationView: View {
    let model: FittingEditorModel
    let moduleID: ModuleID
    /// For the subtitle; see `FitImplantsView.fitName`.
    let fitName: String

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Group {
            if let snapshot = model.snapshot, let module = snapshot.modules.first(where: { $0.id == moduleID }) {
                FitMutationReader(
                    module: module,
                    shipTypeID: snapshot.shipTypeID,
                    fitName: fitName,
                    onMutate: { model.mutate(moduleID, with: $0) },
                    onSetRoll: { attributeID, value in model.setRoll(value, for: attributeID, of: moduleID) },
                    onReset: { model.resetRolls(of: moduleID) },
                    onRemove: {
                        model.demutate(moduleID)
                        dismiss()
                    }
                )
            } else {
                // The module left the fit, or the fit could not be opened.
                ContentUnavailableView {
                    Label("No Module", systemImage: "wand.and.sparkles")
                } description: {
                    Text("This module is no longer in the fit.")
                }
            }
        }
        .navigationTitle("Mutation")
        .navigationBarTitleDisplayMode(.inline)
        // See `fitCommandAlert`.
        .fitCommandAlert(model)
    }
}

/// Reads the mutaplasmids of the module's base type, which the range query depends on: a
/// `@LiteQuery` is built in `init`.
private struct FitMutationReader: View {
    let module: FitSnapshot.Module
    let shipTypeID: TypeID
    let fitName: String
    let onMutate: (TypeID) -> Void
    let onSetRoll: (AttributeID, Double) -> Void
    let onReset: () -> Void
    let onRemove: () -> Void

    @LiteQuery private var mutaplasmids: [MutaplasmidRow]

    init(module: FitSnapshot.Module, shipTypeID: TypeID, fitName: String,
         onMutate: @escaping (TypeID) -> Void,
         onSetRoll: @escaping (AttributeID, Double) -> Void,
         onReset: @escaping () -> Void,
         onRemove: @escaping () -> Void) {
        self.module = module
        self.shipTypeID = shipTypeID
        self.fitName = fitName
        self.onMutate = onMutate
        self.onSetRoll = onSetRoll
        self.onReset = onReset
        self.onRemove = onRemove
        _mutaplasmids = LiteQuery(FittingBrowser.mutaplasmids(for: module.mutation?.baseTypeID ?? module.typeID))
    }

    var body: some View {
        FitMutationBody(module: module,
                        shipTypeID: shipTypeID,
                        fitName: fitName,
                        mutaplasmids: mutaplasmids.sorted {
                            (MutaplasmidTier.rank(of: $0.tierSourceName), $0.name) < (MutaplasmidTier.rank(of: $1.tierSourceName), $1.name)
                        },
                        onMutate: onMutate,
                        onSetRoll: onSetRoll,
                        onReset: onReset,
                        onRemove: onRemove)
    }
}

private struct FitMutationBody: View {
    let module: FitSnapshot.Module
    let shipTypeID: TypeID
    let fitName: String
    /// In tier order.
    let mutaplasmids: [MutaplasmidRow]
    let onMutate: (TypeID) -> Void
    let onSetRoll: (AttributeID, Double) -> Void
    let onReset: () -> Void
    let onRemove: () -> Void

    @LiteQuery private var typeNames: [TypeNameRow]
    /// The ranges of every listed mutaplasmid and of the one on the module, which need not be
    /// listed.
    @LiteQuery private var ranges: [MutaplasmidRangeRow]
    @LiteQuery private var currentNames: [MutaplasmidNameRow]

    init(module: FitSnapshot.Module, shipTypeID: TypeID, fitName: String, mutaplasmids: [MutaplasmidRow],
         onMutate: @escaping (TypeID) -> Void,
         onSetRoll: @escaping (AttributeID, Double) -> Void,
         onReset: @escaping () -> Void,
         onRemove: @escaping () -> Void) {
        self.module = module
        self.shipTypeID = shipTypeID
        self.fitName = fitName
        self.mutaplasmids = mutaplasmids
        self.onMutate = onMutate
        self.onSetRoll = onSetRoll
        self.onReset = onReset
        self.onRemove = onRemove
        // Sorted: each query is `@LiteQuery`'s cache key.
        var named: Set<TypeID> = [module.typeID, shipTypeID]
        var read = Set(mutaplasmids.map(\.id))
        if let mutation = module.mutation {
            named.insert(mutation.baseTypeID)
            read.insert(mutation.mutaplasmidTypeID)
        }
        _typeNames = LiteQuery(SDEBrowser.typeNames(of: named.sorted { $0.rawValue < $1.rawValue }))
        _ranges = LiteQuery(FittingBrowser.mutaplasmidRanges(of: read.sorted { $0.rawValue < $1.rawValue }))
        _currentNames = LiteQuery(FittingBrowser.mutaplasmidNames(of: module.mutation.map { [$0.mutaplasmidTypeID] } ?? []))
    }

    var body: some View {
        let names = Dictionary(typeNames.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        HUDList {
            header(names: names)
            mutaplasmidSection
            if let mutation = module.mutation {
                rollSections(mutation)
                Section {
                    HUDActionList(groups: [[
                        HUDAction("Reset Rolls to Base", systemImage: "arrow.counterclockwise", action: onReset),
                        HUDAction("Remove Mutation", systemImage: "trash", role: .destructive, action: onRemove),
                    ]])
                }
                Section {
                    HUDFootnote("Rolls are the item's attribute values, as in the game and ESI. Every change is saved with the fit.")
                        .hudBareRow()
                }
            } else {
                Section {
                    HUDFootnote("Pick a mutaplasmid to mutate this module. Its rolls start at the base values.")
                        .hudBareRow()
                }
            }
        }
        .navigationSubtitle(Text(verbatim: FitScreenSubtitle.text(hullName: names[shipTypeID] ?? "", fitName: fitName)))
    }

    // MARK: Header

    /// The type the module is now, `MUTATED` and the type it was mutated from; the slot under it.
    private func header(names: [TypeID: String]) -> some View {
        HUDListSection {
            HStack(spacing: 14) {
                HUDItemIcon(typeID: module.typeID, size: 64)
                VStack(alignment: .leading, spacing: 8) {
                    Text(verbatim: names[module.typeID] ?? "")
                        .font(HUDFont.display(22, weight: .bold, relativeTo: .title2))
                        .tracking(0.5)
                        .textCase(.uppercase)
                        .foregroundStyle(Color.hudInk)
                    if let mutation = module.mutation {
                        HStack(spacing: 6) {
                            HUDOutlineTag(text: Text("Mutated"))
                            // A key of its own: the plain `From %@` is a mail's sender.
                            Text(String(localized: "mutation.base",
                                        defaultValue: "From \(names[mutation.baseTypeID] ?? "")",
                                        comment: "Under a mutated module's name: the type it was mutated from"))
                                .font(.hudLabel)
                                .textCase(.uppercase)
                                .foregroundStyle(Color.hudInkMuted)
                                .lineLimit(2)
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            .hudRow(HUDRowStyle(minHeight: 0, verticalPadding: 16))
            Text(verbatim: "\(module.slot.captionName) \(module.socket + 1)")
                .font(.hudLabel)
                .textCase(.uppercase)
                .foregroundStyle(Color.hudInkMuted)
                .frame(maxWidth: .infinity, alignment: .leading)
                .hudRow(HUDRowStyle(minHeight: 0, verticalPadding: 11))
        }
    }

    // MARK: Mutaplasmids

    @ViewBuilder
    private var mutaplasmidSection: some View {
        let current = module.mutation?.mutaplasmidTypeID
        if mutaplasmids.isEmpty {
            Section {
                HUDEmptyPanel(title: Text("No Mutaplasmids"),
                              message: Text("The database lists no mutaplasmid for this module."))
                    .hudBareRow()
            } header: {
                HUDSectionHeader("Mutaplasmid").hudListHeader()
            }
        } else {
            HUDListSection(mutaplasmids, row: { mutaplasmid in
                HUDChoiceRow(title: Text(verbatim: mutaplasmid.name),
                             subtitle: hint(of: mutaplasmid.id).map { Text(verbatim: $0) },
                             isOn: mutaplasmid.id == current) {
                    guard mutaplasmid.id != current else { return }
                    onMutate(mutaplasmid.id)
                }
            }, header: {
                HUDSectionHeader("Mutaplasmid")
            })
        }
    }

    /// `ARMOR REPAIRED −10…+15% · CYCLE TIME −7.5…+5%`: the first two ranges as changes from the
    /// base value; the tier alone does not say how far a mutaplasmid goes.
    private func hint(of mutaplasmidID: TypeID) -> String? {
        let parts = ranges.lazy
            .filter { $0.mutaplasmidID == mutaplasmidID }
            .prefix(2)
            .map { range in
                "\(Self.attributeRow(range).title.uppercased()) \(Self.percent(range.minMultiplier))…\(Self.percent(range.maxMultiplier))%"
            }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// A multiplier as the change it makes, without the `%`: `−10`, `+7.5`, `0`.
    private static func percent(_ multiplier: Double) -> String {
        let change = ((multiplier - 1) * 1000).rounded() / 10
        let number = abs(change).formatted(.number.precision(.fractionLength(0...1)))
        return change > 0 ? "+\(number)" : change < 0 ? "−\(number)" : number
    }

    // MARK: Rolls

    /// One card per roll, `ROLLS` and the tier over the first.
    @ViewBuilder
    private func rollSections(_ mutation: FitSnapshot.Mutation) -> some View {
        let tier = currentNames.first.map { MutaplasmidTier.name(of: $0.tierSourceName) ?? $0.name }
        let attributes = Dictionary(ranges.filter { $0.mutaplasmidID == mutation.mutaplasmidTypeID }.map { ($0.attributeID, $0) },
                                    uniquingKeysWith: { first, _ in first })
        ForEach(Array(mutation.rolls.enumerated()), id: \.element.attributeID) { index, roll in
            let card = FitRollCard(roll: roll,
                                   attribute: attributes[roll.attributeID].map(Self.attributeRow)
                                       ?? Self.attributeRow(id: roll.attributeID),
                                   onSet: { onSetRoll(roll.attributeID, $0) })
            if index == 0 {
                HUDListSection {
                    card
                } header: {
                    HUDSectionHeader(Text("Rolls")) {
                        if let tier { Text(verbatim: tier.uppercased()) }
                    }
                }
            } else {
                HUDListSection { card }
            }
        }
    }

    /// The attribute as the item screen's rows carry it (`TypeAttributeRow.formatted(_:)`).
    private static func attributeRow(_ range: MutaplasmidRangeRow) -> TypeAttributeRow {
        TypeAttributeRow(id: range.attributeID, name: range.name, displayName: range.displayName,
                         value: 0, baseValue: 0, unitID: range.unitID, unitName: range.unitName,
                         categoryID: nil, categoryName: nil)
    }

    /// For a roll the database has no range row for.
    private static func attributeRow(id: AttributeID) -> TypeAttributeRow {
        TypeAttributeRow(id: id, name: "\(id.rawValue)", displayName: nil, value: 0, baseValue: 0,
                         unitID: nil, unitName: nil, categoryID: nil, categoryName: nil)
    }
}

/// One roll: the value and its distance from the base, the bar, and the slider that moves it.
///
/// The slider sends its command when released, so a drag is one command; a change that is not a
/// drag (VoiceOver, keyboard) is sent at once.
private struct FitRollCard: View {
    let roll: MutationRoll
    /// Its name and unit, and the formatting.
    let attribute: TypeAttributeRow
    let onSet: (Double) -> Void

    /// The thumb's value from the first move until the engine's value changes.
    @State private var pending: Double?
    @State private var isEditing = false

    var body: some View {
        let value = pending ?? roll.value
        let tint = Self.tint(value: value, roll: roll)
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(verbatim: attribute.title)
                    .font(.hudLabel)
                    .tracking(2)
                    .textCase(.uppercase)
                    .foregroundStyle(Color.hudInkMuted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(verbatim: Self.change(value: value, base: roll.baseValue))
                    .font(HUDFont.mono(12, weight: .semibold, relativeTo: .caption))
                    .foregroundStyle(tint)
            }
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(verbatim: attribute.formatted(value))
                    .font(HUDFont.mono(24, weight: .semibold, relativeTo: .title2))
                    .foregroundStyle(Color.hudInk)
                    .contentTransition(.numericText())
                Spacer(minLength: 8)
                Text("Base \(attribute.formatted(roll.baseValue))")
                    .font(.hudLabel)
                    .textCase(.uppercase)
                    .foregroundStyle(Color.hudInkMuted)
            }
            HUDRollBar(range: roll.range,
                       reference: roll.baseValue,
                       value: value,
                       tint: tint,
                       lowerLabel: Text(verbatim: attribute.formatted(roll.range.lowerBound)),
                       upperLabel: Text(verbatim: attribute.formatted(roll.range.upperBound)))
            if roll.range.upperBound > roll.range.lowerBound {
                Slider(value: Binding(get: { value }, set: { newValue in
                    pending = newValue
                    if !isEditing { onSet(newValue) }
                }), in: roll.range) { editing in
                    isEditing = editing
                    if !editing, let pending { onSet(pending) }
                }
                .tint(Color.hudAccent)
                .accessibilityLabel(Text(verbatim: attribute.title))
                .accessibilityValue(Text(verbatim: attribute.formatted(value)))
            }
        }
        .hudRow(HUDRowStyle(minHeight: 0, verticalPadding: 14))
        .onChange(of: roll.value) { _, _ in
            if !isEditing { pending = nil }
        }
    }

    /// Better than the base in `ok`, worse in `danger`, the base muted; "better" by `highIsGood`.
    private static func tint(value: Double, roll: MutationRoll) -> Color {
        let base = roll.baseValue
        guard abs(value - base) > abs(base) * 0.0005 else { return .hudInkMuted }
        return (value > base) == roll.highIsGood ? .hudOk : .hudDanger
    }

    /// `+10.1%`, `−4.0%`, `±0.0%`: the change from the base, by the base's size.
    private static func change(value: Double, base: Double) -> String {
        guard base != 0 else { return "±0.0%" }
        let change = ((value - base) / abs(base) * 1000).rounded() / 10
        let number = abs(change).formatted(.number.precision(.fractionLength(1)))
        return change > 0 ? "+\(number)%" : change < 0 ? "−\(number)%" : "±\(number)%"
    }
}
