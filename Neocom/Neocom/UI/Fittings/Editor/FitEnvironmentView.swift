import DogmaKit
import LiteRow
import LiteRowUI
import SDEKit
import SwiftUI

/// The token `navigationDestination(item:)` keys the environment screen on.
enum FitEnvironmentRoute: Hashable {
    case environment
}

/// The system effect the fit or fleet is calculated under: the one in force with what it does,
/// then every effect there is, in sections (wormholes by class, incursions, the Triglavian
/// invasion, metaliminal storms and the rest).
///
/// Pushed from the editor's hull card, on the editor's own model: the environment belongs to the
/// open session. One effect at a time; a pick replaces whatever is there, `None` clears it. A
/// document carrying several is still shown and can be cleared. The snapshot carries only the
/// type id; the list, names and modifiers are static data read through `@LiteQuery`.
struct FitEnvironmentView: View {
    let model: FittingEditorModel
    /// For the subtitle; see `FitImplantsView.fitName`.
    let fitName: String

    var body: some View {
        Group {
            if let snapshot = model.snapshot {
                FitEnvironmentCatalogReader(shipTypeID: snapshot.shipTypeID,
                                            fitName: fitName,
                                            environment: snapshot.environment,
                                            onSet: { model.setEnvironment($0) })
            } else {
                ContentUnavailableView {
                    Label("No Fit", systemImage: "sparkles")
                } description: {
                    Text("This fit could not be opened, so there is nothing to apply an environment to.")
                }
            }
        }
        .navigationTitle("Environment")
        .navigationBarTitleDisplayMode(.inline)
        // An alert is held back while another screen covers its view (see `fitCommandAlert`).
        .fitCommandAlert(model)
    }
}

/// Reads the list of effects, which every query below depends on: a `@LiteQuery` has to be built
/// in `init`, before any result of another one is there.
private struct FitEnvironmentCatalogReader: View {
    let shipTypeID: TypeID
    let fitName: String
    let environment: [TypeID]
    let onSet: ([TypeID]) -> Void

    @LiteQuery private var effectRows: [EnvironmentEffectRow]

    init(shipTypeID: TypeID, fitName: String, environment: [TypeID], onSet: @escaping ([TypeID]) -> Void) {
        self.shipTypeID = shipTypeID
        self.fitName = fitName
        self.environment = environment
        self.onSet = onSet
        _effectRows = LiteQuery(FittingBrowser.environmentEffects())
    }

    var body: some View {
        FitEnvironmentBody(catalog: EnvironmentCatalog(rows: effectRows),
                           shipTypeID: shipTypeID,
                           fitName: fitName,
                           environment: environment,
                           onSet: onSet)
    }
}

private struct FitEnvironmentBody: View {
    let catalog: EnvironmentCatalog
    let shipTypeID: TypeID
    let fitName: String
    let environment: [TypeID]
    let onSet: ([TypeID]) -> Void

    /// The hull's name and the names of the effects in force, which need not be in the catalog.
    @LiteQuery private var typeNames: [TypeNameRow]
    @LiteQuery private var attributes: [EnvironmentAttributeRow]
    @LiteQuery private var operations: [EnvironmentOperationRow]

    /// The class the wormhole list shows; `nil` until picked, then the class of the effect in
    /// force, or the first.
    @State private var pickedClass: Int?

    /// A key of its own: the plain `Active` is a pilot's status elsewhere.
    private static let activeTitle = String(localized: "environment.active", defaultValue: "Active",
                                            comment: "Heading over the system effect in force")

    init(catalog: EnvironmentCatalog, shipTypeID: TypeID, fitName: String, environment: [TypeID],
         onSet: @escaping ([TypeID]) -> Void) {
        self.catalog = catalog
        self.shipTypeID = shipTypeID
        self.fitName = fitName
        self.environment = environment
        self.onSet = onSet
        // Sorted: each query is `@LiteQuery`'s cache key.
        let named = Set(environment).union([shipTypeID]).sorted { $0.rawValue < $1.rawValue }
        let read = Set(catalog.effects.map(\.id)).union(environment).sorted { $0.rawValue < $1.rawValue }
        _typeNames = LiteQuery(SDEBrowser.typeNames(of: named))
        _attributes = LiteQuery(FittingBrowser.environmentAttributes(of: read))
        _operations = LiteQuery(FittingBrowser.environmentOperations(of: read))
    }

    var body: some View {
        let names = Dictionary(typeNames.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        HUDList {
            activeSection(names: names)
            HUDListSection {
                HUDChoiceRow(title: Text("None"), isOn: environment.isEmpty) {
                    onSet([])
                }
            }
            wormholeSection
            ForEach(catalog.sections) { section in
                HUDListSection(section.effects, row: { effect in
                    choiceRow(effect, title: effect.name)
                }, header: {
                    HUDSectionHeader(verbatim: section.category.title)
                })
            }
            Section {
                HUDFootnote("Applies to every ship in the fit or fleet. Not saved to the in-game fit.")
                    .hudBareRow()
            }
        }
        .navigationSubtitle(Text(verbatim: FitScreenSubtitle.text(hullName: names[shipTypeID] ?? "", fitName: fitName)))
    }

    // MARK: Active

    /// `ACTIVE`, then one card per effect in force (name, section, the cross that removes it, what
    /// it changes), or the dashed note when there is none.
    @ViewBuilder
    private func activeSection(names: [TypeID: String]) -> some View {
        if environment.isEmpty {
            Section {
                HUDEmptyPanel(title: Text("No Effect"), message: Text("Pick a system effect below."))
                    .hudBareRow()
            } header: {
                HUDSectionHeader(Text(Self.activeTitle)).hudListHeader()
            }
        } else {
            HUDListSection(Text(Self.activeTitle)) {
                ForEach(Array(environment.enumerated()), id: \.offset) { index, typeID in
                    let effect = catalog.effect(typeID)
                    let name = effect?.name ?? names[typeID] ?? ""
                    let lines = EnvironmentModifierLine.lines(of: typeID, attributes: attributes, operations: operations)
                    activeHeading(name: name, label: effect?.categoryLabel) {
                        var remaining = environment
                        remaining.remove(at: index)
                        onSet(remaining)
                    }
                    if lines.isEmpty {
                        Text("The database lists no modifiers for this effect.")
                            .font(.hudReadout)
                            .foregroundStyle(Color.hudInkMuted)
                            .hudRow(.readout)
                    } else {
                        ForEach(lines) { line in
                            HUDReadoutRow(Text(verbatim: line.title), value: line.value)
                        }
                    }
                }
            }
        }
    }

    /// The effect's name, the section it is from, and the cross.
    private func activeHeading(name: String, label: String?, onRemove: @escaping () -> Void) -> some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 6) {
                Text(verbatim: name)
                    .font(HUDFont.display(18, weight: .bold, relativeTo: .headline))
                    .tracking(0.3)
                    .foregroundStyle(Color.hudInk)
                if let label {
                    HUDOutlineTag(text: Text(verbatim: label))
                }
            }
            .padding(.top, 6)
            Spacer(minLength: 0)
            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color.hudInkMuted)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Remove \(name)"))
        }
        // The cross is a 44 pt target reaching nearly to the card's edge.
        .padding(.leading, HUDMetrics.gutter)
        .padding(.trailing, 8)
        .hudRow(HUDRowStyle(horizontalPadding: 0, minHeight: 0, verticalPadding: 4))
    }

    // MARK: Lists

    /// The wormhole effects of one class, the class picked in a segmented control (`C1 … C6`).
    @ViewBuilder
    private var wormholeSection: some View {
        let classes = catalog.wormholeClasses
        if !classes.isEmpty {
            let shown = shownClass(among: classes)
            let effects = catalog.wormholes(ofClass: shown)
            HUDListSection {
                Picker("Wormhole class", selection: Binding(get: { shown }, set: { pickedClass = $0 })) {
                    ForEach(classes, id: \.self) { wormholeClass in
                        Text(verbatim: "C\(wormholeClass)").tag(wormholeClass)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                // Kept once shown, so clearing the effect does not reset the picker to C1.
                .onChange(of: shown, initial: true) { _, new in pickedClass = new }
                .hudLeadingBlock(hasCardBelow: !effects.isEmpty)
                ForEach(effects) { effect in
                    choiceRow(effect, title: effect.phenomenon, subtitle: hint(of: effect.id))
                }
            } header: {
                HUDSectionHeader(verbatim: EnvironmentCategory.wormhole.title)
            }
        }
    }

    private func shownClass(among classes: [Int]) -> Int {
        if let pickedClass, classes.contains(pickedClass) { return pickedClass }
        let active = environment.lazy.compactMap { catalog.effect($0)?.wormholeClass }.first
        return active ?? classes[0]
    }

    private func choiceRow(_ effect: EnvironmentEffect, title: String, subtitle: String? = nil) -> some View {
        HUDChoiceRow(title: Text(verbatim: title),
                     subtitle: subtitle.map { Text(verbatim: $0) },
                     isOn: environment == [effect.id]) {
            guard environment != [effect.id] else { return }
            onSet([effect.id])
        }
    }

    /// What a wormhole phenomenon changes, by the names of its lines: the six rows read the same
    /// otherwise (`Pulsar`, `Magnetar`).
    private func hint(of typeID: TypeID) -> String? {
        let titles = EnvironmentModifierLine.lines(of: typeID, attributes: attributes, operations: operations).map(\.title)
        return titles.isEmpty ? nil : titles.joined(separator: ", ")
    }
}

/// `Vexor — drone ratting`: the subtitle of the screens pushed from the editor about the whole
/// fit. A fit named after its own hull shows just one of the two.
enum FitScreenSubtitle {
    static func text(hullName: String, fitName: String) -> String {
        var parts = [hullName, fitName].filter { !$0.isEmpty }
        if parts.count == 2, parts[0].localizedCaseInsensitiveCompare(parts[1]) == .orderedSame {
            parts.removeLast()
        }
        return parts.joined(separator: " — ")
    }
}
