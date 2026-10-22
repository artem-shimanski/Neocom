import SwiftUI
import TrainingTimeline
import WidgetKit

/// Five segments for skill levels I–V: trained levels filled, the level in training half-lit,
/// or hatched in `warn` when the queue is paused. Past it, the levels queued in game behind it
/// are outlined in the accent, and the levels only the local training plan has are outlined
/// dashed — the Skills section draws all of them on one bar.
///
/// Plain by default — which is how the character screens and the training queue draw it. Two
/// opt-ins turn it into a control for the fit editor's skills screen: `includesZero` adds a
/// sixth segment in front (a skill can be set to nothing, and "0" has to be a place to tap), and
/// `onSelect` makes every segment a button that sets its own level and writes its numeral on
/// itself. `ownLevel` is the second colour: where the thing being set runs ahead of what the
/// pilot has, the levels past it are drawn in a dimmer accent.
///
/// `trainingProgress` is the widget's opt-in: the level in training fills by its points, the
/// accent over the half-lit accent, instead of being half-lit all over.
struct HUDLevelBar: View {
    /// Levels already trained, 0…5.
    let trained: Int
    /// The level the queue is working on, if it is the next one.
    var training: Int?
    var paused = false
    /// How far into `training` the skill is, 0…1; `nil` draws the level half-lit all over.
    var trainingProgress: Double?
    /// The last level the game queue reaches behind the one in training: the levels up to it
    /// that are neither trained nor `training` are outlined.
    var queued: Int?
    /// The last level the local training plan reaches: the levels up to it that the game has
    /// nothing for are outlined dashed.
    var planned: Int?
    var height: CGFloat = 10
    var spacing: CGFloat = 4
    /// A "0" segment before "I".
    var includesZero = false
    /// What the pilot has. Trained levels above it are drawn dim; `nil` draws them all alike.
    var ownLevel: Int?
    /// Makes the bar a control: called with the level of the segment that was tapped.
    var onSelect: ((Int) -> Void)?

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: spacing) {
            ForEach(includesZero ? 0...5 : 1...5, id: \.self) { level in
                if let onSelect {
                    Button { onSelect(level) } label: {
                        segment(level)
                            .overlay { numeral(level) }
                            .frame(height: height)
                            .clipShape(shape(level))
                            // The segment is a thin strip; the tap may miss it by a few points
                            // either way without reaching for the next row.
                            .contentShape(Rectangle().inset(by: -6))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("Level \(SkillLevelNumeral.roman(level))"))
                    .accessibilityAddTraits(level == trained ? .isSelected : [])
                } else {
                    segment(level)
                        .frame(height: height)
                        .clipShape(shape(level))
                }
            }
        }
        .modifier(BarAccessibility(isControl: onSelect != nil, label: accessibilityLabel))
    }

    @ViewBuilder
    private func segment(_ level: Int) -> some View {
        if level == 0 {
            // Selected, the empty set reads as a state; otherwise it is just a place to tap.
            trained == 0 ? Color.hudLineLeader : Color.hudSurfaceRaised
        } else {
            let kind = segmentKind(level)
            HUDLevelSegmentFill(segment: kind, shape: shape(level),
                                progress: kind == .training ? trainingProgress : nil)
        }
    }

    /// What one of the levels I…V shows, in the order the states take precedence: what is
    /// trained, then what the game is doing, then what only the plan has.
    private func segmentKind(_ level: Int) -> HUDLevelSegment {
        if level <= trained {
            if let ownLevel, level > ownLevel { return .dimmed }
            return .trained
        }
        if level == training { return paused ? .paused : .training }
        if let queued, level <= queued { return .queued }
        if let planned, level <= planned { return .planned }
        return .empty
    }

    /// The numeral of a tappable segment: dark on a filled one, faint on an empty one.
    private func numeral(_ level: Int) -> some View {
        let filled = level > 0 && level <= trained
        let dimmed = filled && ownLevel.map { level > $0 } == true
        return Text(verbatim: SkillLevelNumeral.roman(level))
            .font(HUDFont.mono(10, weight: .semibold, relativeTo: .caption2))
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .foregroundStyle(filled ? inkOnAccent(dimmed: dimmed) : Color.hudInkFaint)
            .accessibilityHidden(true)
    }

    /// Text on the accent: dark teal on the bright dark-theme accent, white on the deep
    /// light-theme one.
    /// vanish into it, so it takes the ordinary ink there.
    private func inkOnAccent(dimmed: Bool) -> Color {
        if colorScheme == .dark {
            return Color(red: 0x06 / 255, green: 0x26 / 255, blue: 0x2A / 255)
        }
        return dimmed ? .hudInk : .white
    }

    private func shape(_ level: Int) -> UnevenRoundedRectangle {
        // A control has no capsule ends: its segments are six equal keys.
        if onSelect != nil {
            return UnevenRoundedRectangle(cornerRadii: .init(topLeading: 3, bottomLeading: 3, bottomTrailing: 3, topTrailing: 3))
        }
        let outer = height / 2
        let inner: CGFloat = 2
        return UnevenRoundedRectangle(
            topLeadingRadius: level == 1 ? outer : inner,
            bottomLeadingRadius: level == 1 ? outer : inner,
            bottomTrailingRadius: level == 5 ? outer : inner,
            topTrailingRadius: level == 5 ? outer : inner
        )
    }

    /// "Level II, training III, queued to IV, planned to V" — only the parts that apply.
    private var accessibilityLabel: Text {
        var parts = [String(localized: "Level \(SkillLevelNumeral.roman(trained))")]
        var reached = trained
        if let training, training > reached {
            let roman = SkillLevelNumeral.roman(training)
            parts.append(paused ? String(localized: "training \(roman), paused")
                                : String(localized: "training \(roman)"))
            reached = training
        }
        if let queued, queued > reached {
            parts.append(String(localized: "queued to \(SkillLevelNumeral.roman(queued))"))
            reached = queued
        }
        if let planned, planned > reached {
            parts.append(String(localized: "planned to \(SkillLevelNumeral.roman(planned))"))
        }
        return Text(verbatim: parts.joined(separator: ", "))
    }

    /// A plain bar is one element that says its level; a control keeps its segments apart.
    private struct BarAccessibility: ViewModifier {
        let isControl: Bool
        let label: Text

        func body(content: Content) -> some View {
            if isControl {
                content.accessibilityElement(children: .contain)
            } else {
                content
                    .accessibilityElement()
                    .accessibilityLabel(label)
            }
        }
    }
}

/// What one segment of a level bar shows.
enum HUDLevelSegment: Hashable {
    case empty
    case trained
    /// Trained, past what the pilot has (`HUDLevelBar.ownLevel`).
    case dimmed
    /// In training, the queue running.
    case training
    /// In training, the queue paused.
    case paused
    /// In the game queue behind the level in training.
    case queued
    /// In the local training plan only.
    case planned
}

/// The paint of one segment, inside the shape it is clipped to — the outlines are drawn on that
/// same shape, inset, so the clip never cuts them in half.
///
/// In a widget the colours follow its rendering mode (`HUDInk`), and the accent parts join the
/// widget's accent group.
struct HUDLevelSegmentFill: View {
    let segment: HUDLevelSegment
    let shape: UnevenRoundedRectangle
    /// The filled part of a `.training` segment, 0…1; `nil` leaves it half-lit all over.
    var progress: Double?

    @Environment(\.widgetRenderingMode) private var renderingMode

    var body: some View {
        let ink = HUDInk(renderingMode)
        let accent = ink.accent
        let raised = ink.surfaceRaised
        switch segment {
        case .empty:
            raised
        case .trained:
            accent.widgetAccentable()
        case .dimmed:
            accent.opacity(0.45)
        case .training:
            ZStack(alignment: .leading) {
                accent.opacity(0.45).widgetAccentable()
                if let progress {
                    GeometryReader { proxy in
                        accent
                            .frame(width: proxy.size.width * min(max(progress, 0), 1))
                            .widgetAccentable()
                    }
                }
            }
        case .paused:
            HUDHatch()
        case .queued:
            raised
                .overlay { shape.strokeBorder(accent, lineWidth: 1.5) }
        case .planned:
            HUDDashedOutline(cornerRadii: shape.cornerRadii).fill(accent)
        }
    }
}

/// One segment on its own, the size of a bar's segment: what a legend explains a bar with, and
/// what a count of queued skills is marked with.
struct HUDLevelSwatch: View {
    let segment: HUDLevelSegment
    var width: CGFloat = 14
    var height: CGFloat = 8

    var body: some View {
        let shape = UnevenRoundedRectangle(cornerRadii: .init(topLeading: 1.5, bottomLeading: 1.5, bottomTrailing: 1.5, topTrailing: 1.5),
                                           style: .continuous)
        HUDLevelSegmentFill(segment: segment, shape: shape)
            .frame(width: width, height: height)
            .clipShape(shape)
            .accessibilityHidden(true)
    }
}
