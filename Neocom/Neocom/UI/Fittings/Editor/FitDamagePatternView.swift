import DogmaKit
import SwiftUI

/// The damage pattern the stats screen's effective figures are read against: a slider per damage
/// type, then the named patterns as chips (flat, the four single types, NPC factions).
///
/// A sheet over the stats screen, on the editor's own pattern (`FittingEditorModel`); nothing
/// here reaches the fit or the engine. The sliders show the pattern in force; moving one makes it
/// custom, and a custom pattern or an item's pattern lights no chip. An ammo charge's or a drone's
/// damage split is chosen through `FitDamageSourcePicker`.
struct FitDamagePatternView: View {
    @Binding var pattern: FitDamagePattern
    /// What the "From ammo or drone…" list offers, read off the fit when the sheet opened.
    let sources: FitDamageSources

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            HUDList(isTransparent: true) {
                HUDListSection {
                    ForEach(HUDDamageType.allCases) { type in
                        weightRow(type)
                    }
                }
                Section {
                    HUDWrapLayout(spacing: 6) {
                        ForEach(FitDamagePattern.Preset.ordered) { preset in
                            HUDChoiceChip(title: chipTitle(of: preset), isSelected: pattern.preset == preset) {
                                pattern = FitDamagePattern(preset)
                            }
                        }
                    }
                    .padding(.horizontal, 2)
                    .hudBareRow()
                }
                Section {
                    sourceRow
                } footer: {
                    HUDFootnote("Drag a share; the others keep their values and everything is normalised to 100%. NPC profiles are approximate (≈).")
                        .hudListFooter()
                }
            }
            .navigationDestination(for: FitDamageSourceRoute.self) { _ in
                FitDamageSourcePicker(sources: sources, pattern: $pattern)
            }
            .navigationTitle("Damage Pattern")
            .navigationSubtitle(pattern.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done", systemImage: "xmark", role: .cancel) { dismiss() }
                }
            }
        }
        // Short enough that the stats behind stay in sight; `.large` is for the rest.
        .presentationDetents([.fraction(0.75), .large])
    }

    // MARK: Weights

    private func weightRow(_ type: HUDDamageType) -> some View {
        VStack(spacing: 2) {
            HStack(spacing: 10) {
                Circle()
                    .fill(type.color)
                    .frame(width: 8, height: 8)
                Text(type.label)
                    .font(HUDFont.mono(12, weight: .regular, relativeTo: .caption))
                    .tracking(1)
                    .textCase(.uppercase)
                    .foregroundStyle(Color.hudInkBodyMuted)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(verbatim: pattern.weights[type.rawValue].formatted(.number.precision(.fractionLength(0))))
                    .font(HUDFont.mono(13, weight: .semibold, relativeTo: .subheadline))
                    .foregroundStyle(Color.hudInk)
                    .monospacedDigit()
                Text(verbatim: "= " + Self.percent(share(of: type)))
                    .font(HUDFont.mono(11, weight: .regular, relativeTo: .caption))
                    .foregroundStyle(Color.hudInkMuted)
                    .monospacedDigit()
                    .frame(width: 48, alignment: .trailing)
            }
            .accessibilityHidden(true)
            Slider(value: weight(of: type), in: 0...100) {
                Text(type.label)
            }
            .tint(type.color)
            .accessibilityValue(Text(verbatim: Self.percent(share(of: type))))
        }
        .hudRow(Self.weightRowStyle)
    }

    private static let weightRowStyle: HUDRowStyle = {
        var style = HUDRowStyle.sheet
        style.minHeight = 0
        style.verticalPadding = 6
        style.cardEdgePadding = 4
        return style
    }()

    /// One slider's weight. A move that changes nothing leaves the preset in force. The slider has
    /// no `step` (a stepped one draws a tick per step); the weight is rounded here instead.
    private func weight(of type: HUDDamageType) -> Binding<Double> {
        Binding {
            pattern.weights[type.rawValue]
        } set: { value in
            // Compared rounded: an item's shares are fractions, and a touch must not make them
            // custom.
            guard value.rounded() != pattern.weights[type.rawValue].rounded() else { return }
            var weights = pattern.weights
            weights[type.rawValue] = value.rounded()
            pattern = .custom(weights)
        }
    }

    private func share(of type: HUDDamageType) -> Double {
        let vector = pattern.vector
        return vector[type.rawValue] / vector.sum()
    }

    private static func percent(_ share: Double) -> String {
        (share * 100).formatted(.number.precision(.fractionLength(0))) + "%"
    }

    // MARK: Presets

    /// The preset's name, `≈ ` in front of an NPC faction's: its figures are an average.
    private func chipTitle(of preset: FitDamagePattern.Preset) -> Text {
        preset.isApproximate ? Text(verbatim: "≈ " + String(localized: preset.title)) : Text(preset.title)
    }

    // MARK: Item

    /// The third way in: an ammo charge or a drone whose split becomes the pattern. A row that
    /// pushes `FitDamageSourcePicker`; while the pattern is an item's split, it shows the item and
    /// shares.
    private var sourceRow: some View {
        NavigationLink(value: FitDamageSourceRoute.picker) {
            if let item = pattern.item {
                HUDTypeRow(typeID: item.typeID, name: item.name,
                           subtitle: Text(verbatim: HUDDamageType.splitLine(pattern.vector, percent: true)))
            } else {
                HUDLinkRowLabel(systemImage: nil, title: Text("From ammo or drone…"))
            }
        }
        .hudRowButton(pattern.item == nil ? Self.sourceRowStyle : Self.itemRowStyle)
    }

    /// The sliders' card fill, at the height of the row inside.
    private static let sourceRowStyle: HUDRowStyle = {
        var style = HUDRowStyle.sheet
        style.minHeight = HUDRowStyle.default.minHeight
        return style
    }()

    private static let itemRowStyle: HUDRowStyle = {
        var style = HUDRowStyle.sheet
        style.minHeight = HUDTypeRow.rowStyle.minHeight
        return style
    }()
}

/// The push from the sheet's item row to the "Damage from…" list.
enum FitDamageSourceRoute: Hashable {
    case picker
}

#Preview {
    @Previewable @State var pattern = FitDamagePattern(.guristas)
    Color.clear.sheet(isPresented: .constant(true)) {
        FitDamagePatternView(pattern: $pattern,
                             sources: FitDamageSources(fitName: "Vexor", inFit: [], chargeSlots: [], allowed: []))
    }
    .environment(SDEStore())
}
