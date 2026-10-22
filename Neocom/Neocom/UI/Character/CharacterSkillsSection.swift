import LiteRow
import LiteRowUI
import SDEKit
import SwiftUI
import TrainingKit

/// The wallet. One row, and no section without it: the balance needs its own scope, and a character
/// authorized without it must not read as having a zero balance.
struct CharacterWalletSection: View {
    let balance: Double?

    var body: some View {
        if let balance {
            HUDListSection("Wallet") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Balance")
                        .font(.hudMicro)
                        .tracking(2)
                        .textCase(.uppercase)
                        .foregroundStyle(Color.hudInkMuted)
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(balance, format: .number.precision(.fractionLength(2)))
                            .font(.hudFigureXL)
                            .foregroundStyle(Color.hudAccent)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                        Text("ISK")
                            .font(HUDFont.mono(14, weight: .regular, relativeTo: .body))
                            .foregroundStyle(Color.hudInkMuted)
                    }
                }
                .hudRow(HUDRowStyle(minHeight: 0, verticalPadding: 14))
                .accessibilityElement(children: .combine)
            }
        }
    }
}

/// What the character has trained and what they are training, plus the two remap rows that
/// ride along in the same `/attributes` response as the attributes themselves.
/// Everything here is already in memory; the section makes no request beyond naming the skill in
/// training.
struct CharacterSkillsSection: View {
    let snapshot: CharacterSnapshot
    /// `nil` before the catalog is loaded; the counts still draw, only the queue row waits.
    let pilot: Pilot?

    var body: some View {
        HUDListSection("Skills") {
            HUDStatStrip(items: stats)
                .hudRow(HUDRowStyle(horizontalPadding: 0, minHeight: 0, verticalPadding: 0))

            HUDReadoutRow("Total SP") {
                Text(snapshot.totalSkillPoints, format: .number)
            }

            TrainingRow(entry: pilot?.queue.first)

            if let bonusRemaps = snapshot.bonusRemaps {
                HUDReadoutRow("Bonus Remaps", value: bonusRemaps.formatted(.number))
            }

            if let neuralRemapDate = RemapAvailability(snapshot: snapshot)?.nextNeuralRemap {
                HUDReadoutRow("Neural Remap") {
                    if neuralRemapDate <= .now {
                        Text("Now").foregroundStyle(Color.hudOk)
                    } else {
                        Text(neuralRemapDate, format: .dateTime.year().month(.twoDigits).day(.twoDigits))
                    }
                }
            }
        }
    }

    private var stats: [HUDStatStrip.Item] {
        var items = [
            HUDStatStrip.Item(id: 0, label: Text("Skill Points"),
                              value: Text(verbatim: Self.compact(snapshot.totalSkillPoints))),
            HUDStatStrip.Item(id: 1, label: Text("Skills"),
                              value: Text(snapshot.skills.count, format: .number)),
        ]
        // Skill injectors leave points that belong to no skill yet; nothing to show when there are
        // none.
        if let unallocated = snapshot.unallocatedSkillPoints, unallocated > 0 {
            items.append(HUDStatStrip.Item(id: 2, label: Text("Unallocated"),
                                           value: Text(verbatim: Self.compact(unallocated)),
                                           color: .hudAccent))
        }
        return items
    }

    /// The strip's short form; the exact total is the readout right under it.
    private static func compact(_ value: Int64) -> String {
        Double(value).formatted(.number.notation(.compactName).precision(.significantDigits(1...4)))
    }
}

/// What the game is training right now, named out of the SDE.
private struct TrainingRow: View {
    let entry: CharacterSnapshot.QueueEntry?

    @LiteQuery private var names: [TypeNameRow]

    init(entry: CharacterSnapshot.QueueEntry?) {
        self.entry = entry
        _names = LiteQuery(SDEBrowser.typeNames(of: entry.map { [$0.skillID] } ?? []))
    }

    var body: some View {
        NavigationLink(value: MainMenuSection.trainingQueue) {
            HUDReadoutRow("Training") {
                if let entry {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("\(name(of: entry.skillID)) \(SkillLevel.roman(entry.finishedLevel))")
                        if let finishDate = entry.finishDate {
                            Text(finishDate, format: .dateTime.month().day().hour().minute())
                                .font(HUDFont.mono(11, weight: .regular, relativeTo: .caption))
                                .foregroundStyle(Color.hudInkMuted)
                        } else {
                            // No dates is how ESI reports a paused entry.
                            Text("Paused")
                                .font(.hudLabel)
                                .tracking(1)
                                .textCase(.uppercase)
                                .foregroundStyle(Color.hudWarn)
                        }
                    }
                } else {
                    Text("Not Training")
                        .foregroundStyle(Color.hudWarn)
                }
            }
        }
        .hudRowButton(.readout)
    }

    private func name(of skill: TypeID) -> String {
        names.first { $0.id == skill }?.name ?? ""
    }
}
