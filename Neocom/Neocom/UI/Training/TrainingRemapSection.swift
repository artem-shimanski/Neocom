import SDEKit
import SwiftUI
import TrainingKit

/// What the plan would cost with the best attributes the in-game remap allows: attributes now and
/// after, the plan's time with each, and whether a remap can be spent right away.
///
/// Optimizes over the plan alone, not the game's queue ahead of it. Absent when there is nothing to
/// time; one column when the plan has nothing to gain.
///
/// `now` comes from the screen's single clock.
struct TrainingRemapSection: View {
    let queue: TrainingQueue
    let availability: RemapAvailability?
    let now: Date

    var body: some View {
        if !queue.isEmpty, let remap = queue.optimalRemap() {
            // A saving the two-unit time format cannot show is not worth a remap: the plan is
            // reported as already suited.
            let isOptimal = !remap.isChanged
                || TrainingTime.string(remap.currentTime) == TrainingTime.string(remap.optimalTime)
            HUDListSection {
                if !isOptimal {
                    HUDColumnsHeader(columns: [Text("Current"), Text("Optimal")])
                }
                ForEach(Array(CharacterAttribute.displayOrder.enumerated()), id: \.element) { index, attribute in
                    attributeRow(attribute, remap: remap, isOptimal: isOptimal,
                                 divider: index == 0 && !isOptimal ? .clear : .hudLineSubtle)
                }
                timeRow(remap, isOptimal: isOptimal)
                if let availability {
                    availabilityRow(availability)
                }
            } header: {
                header(remap, isOptimal: isOptimal)
            } footer: {
                if isOptimal {
                    HUDFootnote("Your attributes already suit this plan best.")
                } else {
                    HUDFootnote("Base attributes, without implants; the times count the implants you wear. Remap in the EVE client.")
                }
            }
        }
    }

    private func header(_ remap: AttributeRemap, isOptimal: Bool) -> some View {
        HUDSectionHeader(Text("Optimal Remap")) {
            if isOptimal {
                Text("Optimal")
                    .foregroundStyle(Color.hudOk)
            } else {
                Text(verbatim: "\u{2212}" + TrainingTime.string(remap.savedTime))
                    .foregroundStyle(Color.hudOk)
                    .accessibilityLabel(Text("Saves \(Self.spoken(remap.savedTime))"))
            }
        }
    }

    // MARK: - Rows

    private func attributeRow(_ attribute: CharacterAttribute, remap: AttributeRemap,
                              isOptimal: Bool, divider: Color) -> some View {
        let current = remap.current[attribute]
        let optimal = remap.optimal[attribute]
        let delta = optimal - current
        let title = attribute.title
        let values: [Text] = isOptimal
            ? [Text(current, format: .number)]
            : [Text(current, format: .number), Self.optimalText(value: optimal, delta: delta)]
        let spoken: Text
        if isOptimal {
            spoken = Text(current, format: .number)
        } else if delta > 0 {
            spoken = Text("\(optimal), up \(delta) from \(current)")
        } else if delta < 0 {
            spoken = Text("\(optimal), down \(-delta) from \(current)")
        } else {
            spoken = Text("\(optimal), unchanged")
        }
        return HUDColumnsRow(label: Text(title), values: values, divider: divider)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(title))
            .accessibilityValue(spoken)
    }

    /// The new value with its change in front: `+6  27`. A decrease is muted, not warned. The runs
    /// carry their own colours, which win over the row's ink.
    private static func optimalText(value: Int, delta: Int) -> Text {
        guard delta != 0 else { return Text(value, format: .number) }
        var change = AttributedString((delta > 0 ? "+" : "\u{2212}") + "\(abs(delta))")
        change.font = .hudMicro
        change.foregroundColor = delta > 0 ? .hudOk : .hudInkMuted
        var figure = AttributedString("  \(value)")
        figure.foregroundColor = .hudAccent
        return Text(change + figure)
    }

    private func timeRow(_ remap: AttributeRemap, isOptimal: Bool) -> some View {
        let current = Text(verbatim: TrainingTime.string(remap.currentTime))
        let optimal = Text(verbatim: TrainingTime.string(remap.optimalTime))
            .foregroundStyle(Color.hudAccent)
        let spoken = isOptimal
            ? Text(verbatim: Self.spoken(remap.currentTime))
            : Text("\(Self.spoken(remap.optimalTime)), now \(Self.spoken(remap.currentTime))")
        return HUDColumnsRow(label: Text("Plan Time"),
                             values: isOptimal ? [current] : [current, optimal],
                             isEmphasized: true, divider: .hudLineLeader)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("Plan Time"))
            .accessibilityValue(spoken)
    }

    private func availabilityRow(_ availability: RemapAvailability) -> some View {
        HUDReadoutRow("Next Remap") {
            if availability.isAvailable(at: now) {
                Text(Self.availableText(bonus: availability.bonusRemaps))
            } else if let date = availability.nextNeuralRemap {
                Text(date, format: .dateTime.year().month(.twoDigits).day(.twoDigits))
            }
        }
    }

    /// `Now`, with ` · 2 bonus` after it when remaps are banked.
    private static func availableText(bonus: Int) -> AttributedString {
        var text = AttributedString(String(localized: "Now"))
        text.foregroundColor = .hudOk
        if bonus > 0 {
            var banked = AttributedString(" · " + String(localized: "\(bonus) bonus"))
            banked.foregroundColor = .hudInkMuted
            text += banked
        }
        return text
    }

    /// The duration for VoiceOver: "45 days, 23 hours" rather than the narrow "45d 23h".
    private static func spoken(_ time: TimeInterval) -> String {
        Duration.seconds(time).formatted(
            .units(allowed: [.days, .hours, .minutes, .seconds], width: .wide, maximumUnitCount: 2)
        )
    }
}
