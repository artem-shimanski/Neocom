import DogmaKit
import SwiftUI

// MARK: - Damage types

/// The four damage types in the game's order, each with its HUD colour.
///
/// The order is positional: players read EM-Therm-Kin-Exp by column.
enum HUDDamageType: Int, CaseIterable, Identifiable {
    case em, thermal, kinetic, explosive

    var id: Int { rawValue }

    /// The game's abbreviations.
    var label: LocalizedStringResource {
        switch self {
        case .em: "EM"
        case .thermal: "Therm"
        case .kinetic: "Kin"
        case .explosive: "Exp"
        }
    }

    /// `EM 0 · THERM 10 · KIN 14 · EXP 0`: four figures on one line, each after its type's
    /// abbreviation. `percent` writes them as shares (`KIN 58%`).
    static func splitLine(_ values: DamageVector, percent: Bool = false) -> String {
        allCases.map { type in
            let figure = values[type.rawValue].formatted(.number.precision(.fractionLength(0...1)))
            return String(localized: type.label).uppercased() + " " + figure + (percent ? "%" : "")
        }
        .joined(separator: " · ")
    }

    var color: Color {
        switch self {
        case .em: .hudDamageEm
        case .thermal: .hudDamageThermal
        case .kinetic: .hudDamageKinetic
        case .explosive: .hudDamageExplosive
        }
    }
}

/// The damage types of one subject: four columns, each with the type's name in its colour over
/// a 24 pt track filled from the left to the type's share, and the figure centred on top.
///
/// One component for item resistances, fit resistances and fit damage; they differ only in what
/// the figure means, which is `scale` plus `numbers`:
///
/// * a resistance arrives as a share (`.unit`) and reads as a percentage;
/// * damage arrives as a quantity per type (`.sum`), and the share is each type's part of the
///   sum. `isToggleable` lets a tap swap the two readings.
///
/// The current reading is view state, not part of the snapshot or the document.
struct HUDDamageBlock: View {
    /// Where the percentage is taken from.
    enum Scale {
        /// Each value is already a share of one.
        case unit
        /// Each value is a quantity; its share is its part of the sum.
        case sum
    }

    /// What the figure on the track reads as.
    enum Numbers {
        case percent
        case raw

        var other: Numbers {
            switch self {
            case .percent: .raw
            case .raw: .percent
            }
        }
    }

    /// Four values in `HUDDamageType` order; `nil` is a missing value, drawn as a dash.
    private let values: [Double?]
    private let scale: Scale
    private let numbers: Numbers
    private let isToggleable: Bool
    /// Whether each column carries its own label. Off for blocks stacked under one set of
    /// `HUDDamageTypeLabels`.
    private let showsLabels: Bool
    /// How a raw figure is written.
    private let format: FloatingPointFormatStyle<Double>

    @State private var isSwapped = false

    /// Gap between the four columns; the labels above them must match it.
    static let columnSpacing: CGFloat = 5
    /// Track height, and so the height of a matrix row.
    static let trackHeight: CGFloat = 24

    init(values: [Double?], scale: Scale, numbers: Numbers, isToggleable: Bool = false,
         showsLabels: Bool = true,
         format: FloatingPointFormatStyle<Double> = .number.precision(.fractionLength(0...1))) {
        // Padded and trimmed to four columns; a missing one draws a dash.
        self.values = (0..<4).map { $0 < values.count ? values[$0] : nil }
        self.scale = scale
        self.numbers = numbers
        self.isToggleable = isToggleable
        self.showsLabels = showsLabels
        self.format = format
    }

    /// The engine's damage vector, the source of every fit-side figure.
    init(_ vector: DamageVector, scale: Scale, numbers: Numbers, isToggleable: Bool = false,
         showsLabels: Bool = true,
         format: FloatingPointFormatStyle<Double> = .number.precision(.fractionLength(0...1))) {
        self.init(values: [vector.em, vector.thermal, vector.kinetic, vector.explosive],
                  scale: scale, numbers: numbers, isToggleable: isToggleable,
                  showsLabels: showsLabels, format: format)
    }

    var body: some View {
        HStack(spacing: Self.columnSpacing) {
            ForEach(HUDDamageType.allCases) { type in
                column(type)
            }
        }
        .contentShape(Rectangle())
        .modifier(TapToSwap(isEnabled: isToggleable) {
            withAnimation(.easeInOut(duration: 0.15)) { isSwapped.toggle() }
        })
    }

    @ViewBuilder
    private func column(_ type: HUDDamageType) -> some View {
        VStack(spacing: 4) {
            if showsLabels {
                HUDDamageTypeLabel(type)
            }
            track(type)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    /// The figure on its track. A missing value leaves the track empty with a dash.
    private func track(_ type: HUDDamageType) -> some View {
        let value = values[type.rawValue]
        return Color.hudSurfaceRaised
            .frame(height: Self.trackHeight)
            .overlay(alignment: .leading) {
                if let value {
                    GeometryReader { proxy in
                        type.color.opacity(HUDResourceBar.fillOpacity)
                            .frame(width: proxy.size.width * min(max(share(of: value), 0), 1))
                    }
                }
            }
            .overlay {
                // Ink whatever the type: the fill behind it carries the colour.
                if let value {
                    Text(verbatim: figure(value))
                        .font(HUDFont.mono(11, weight: .semibold, relativeTo: .caption))
                        .foregroundStyle(Color.hudInk)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .padding(.horizontal, 2)
                } else {
                    Text(verbatim: "—")
                        .font(HUDFont.mono(11, weight: .semibold, relativeTo: .caption))
                        .foregroundStyle(Color.hudInkFaint)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
    }

    /// The reading currently showing: `numbers`, or its opposite after a tap.
    private var reading: Numbers {
        isSwapped ? numbers.other : numbers
    }

    private func figure(_ value: Double) -> String {
        switch reading {
        case .percent:
            (share(of: value) * 100).formatted(.number.precision(.fractionLength(0))) + "%"
        case .raw:
            value.formatted(format)
        }
    }

    /// The fill fraction and the percentage one value reads as.
    private func share(of value: Double) -> Double {
        switch scale {
        case .unit:
            value
        case .sum:
            total > 0 ? value / total : 0
        }
    }

    private var total: Double {
        values.reduce(0) { $0 + ($1 ?? 0) }
    }

    /// The tap, attached only where swapping is on, so a block that does not swap leaves taps
    /// to the row around it.
    private struct TapToSwap: ViewModifier {
        let isEnabled: Bool
        let action: () -> Void

        func body(content: Content) -> some View {
            if isEnabled {
                content
                    .onTapGesture(perform: action)
                    .accessibilityAddTraits(.isButton)
                    .accessibilityAction(named: Text("Switch values"), action)
            } else {
                content
            }
        }
    }
}

/// One bar split by damage type, the glance version of the block above for a row that carries
/// its own number. An all-zero vector leaves the bare track.
struct HUDDamageSplitBar: View {
    let vector: DamageVector
    var height: CGFloat = 4

    var body: some View {
        GeometryReader { proxy in
            HStack(spacing: 0) {
                ForEach(HUDDamageType.allCases) { type in
                    type.color.opacity(HUDResourceBar.fillOpacity)
                        .frame(width: proxy.size.width * share(of: type))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.hudSurfaceRaised)
            .clipShape(.capsule)
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }

    private func share(of type: HUDDamageType) -> Double {
        let total = vector.sum()
        guard total > 0 else { return 0 }
        let values = [vector.em, vector.thermal, vector.kinetic, vector.explosive]
        return max(values[type.rawValue], 0) / total
    }
}

/// One damage type's name: mono 10, tracked, centred, in the type's colour.
struct HUDDamageTypeLabel: View {
    let type: HUDDamageType

    init(_ type: HUDDamageType) {
        self.type = type
    }

    var body: some View {
        Text(type.label)
            .font(.hudMicro)
            .tracking(1)
            .textCase(.uppercase)
            .foregroundStyle(type.color)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .frame(maxWidth: .infinity)
    }
}

/// The four labels alone, in the block's columns, for a matrix of several blocks.
struct HUDDamageTypeLabels: View {
    var body: some View {
        HStack(spacing: HUDDamageBlock.columnSpacing) {
            ForEach(HUDDamageType.allCases) { type in
                HUDDamageTypeLabel(type)
            }
        }
    }
}

#Preview {
    HUDList {
        HUDListSection("Resistances") {
            HUDDamageBlock(values: [0.0, 0.2, 0.4, 0.5], scale: .unit, numbers: .percent)
                .hudRow()
            HUDDamageBlock(values: [0.6, nil, 0.25], scale: .unit, numbers: .percent)
                .hudRow()
        }

        HUDListSection("Damage — tap to switch") {
            HUDDamageBlock(DamageVector(em: 240, thermal: 180, kinetic: 0, explosive: 60),
                           scale: .sum, numbers: .raw, isToggleable: true)
                .hudRow()
        }

        HUDListSection("Labels once, blocks under them") {
            HUDDamageTypeLabels()
                .hudRow(HUDRowStyle(minHeight: 0))
            HUDDamageBlock(values: [0.5, 0.4, 0.3, 0.2], scale: .unit, numbers: .percent,
                           showsLabels: false)
                .hudRow()
        }
    }
}
