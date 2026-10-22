//
//  AttributeRemap.swift
//  TrainingKit
//

import Foundation
import SDEKit

/// A distribution of base attributes the in-game remap allows, and what it does to a plan.
public struct AttributeRemap: Sendable, Hashable {
    /// Base attributes before and after; implants excluded in both.
    public var current: CharacterAttributes
    public var optimal: CharacterAttributes
    /// The plan's time with each, implants included.
    public var currentTime: TimeInterval
    public var optimalTime: TimeInterval

    public var savedTime: TimeInterval { max(currentTime - optimalTime, 0) }
    public var isChanged: Bool { optimal != current }

    /// 17...27 each, 99 in total: 14 points over the minimum, at most 10 on one attribute.
    public static let range = 17...27
    public static let total = 99

    /// Every distribution the game accepts (2 885 of them), built once.
    public static let distributions: [CharacterAttributes] = {
        var result: [CharacterAttributes] = []
        for perception in range {
            for memory in range {
                for willpower in range {
                    for intelligence in range {
                        let charisma = total - perception - memory - willpower - intelligence
                        guard range.contains(charisma) else { continue }
                        result.append(CharacterAttributes(charisma: charisma, intelligence: intelligence,
                                                          memory: memory, perception: perception,
                                                          willpower: willpower))
                    }
                }
            }
        }
        return result
    }()

    /// The best distribution for `items`, or `nil` when there are none.
    ///
    /// Among equal times the distribution closest to `current` wins.
    public static func optimal(for items: [TrainingQueue.Item],
                               current: CharacterAttributes,
                               implants: CharacterAttributes) -> AttributeRemap? {
        guard !items.isEmpty else { return nil }

        // Time depends only on the points per attribute pair; fold the plan to at most 20 pairs,
        // sorted so the summation order is stable.
        var folded: [Pair: Int] = [:]
        for item in items {
            folded[Pair(primary: item.primaryAttribute, secondary: item.secondaryAttribute), default: 0] += item.skillPoints
        }
        let pairs = folded.sorted {
            ($0.key.primary.rawValue, $0.key.secondary.rawValue) < ($1.key.primary.rawValue, $1.key.secondary.rawValue)
        }

        func time(_ base: CharacterAttributes) -> TimeInterval {
            let total = base + implants
            return pairs.reduce(0) {
                $0 + TrainingMath.trainingTime(skillPoints: $1.value,
                                               primary: total[$1.key.primary],
                                               secondary: total[$1.key.secondary])
            }
        }
        func distance(_ base: CharacterAttributes) -> Int {
            CharacterAttribute.allCases.reduce(0) { $0 + abs(base[$1] - current[$1]) }
        }

        let currentTime = time(current)
        var best = current
        var bestTime = currentTime
        var bestDistance = 0
        // Float noise between two equal sums is far below a millisecond.
        let epsilon = 1e-6

        for candidate in distributions {
            let candidateTime = time(candidate)
            if candidateTime < bestTime - epsilon {
                best = candidate
                bestTime = candidateTime
                bestDistance = distance(candidate)
            } else if candidateTime <= bestTime + epsilon {
                let candidateDistance = distance(candidate)
                if candidateDistance < bestDistance {
                    best = candidate
                    bestTime = min(bestTime, candidateTime)
                    bestDistance = candidateDistance
                }
            }
        }
        return AttributeRemap(current: current, optimal: best,
                              currentTime: currentTime, optimalTime: bestTime)
    }

    private struct Pair: Hashable {
        var primary: CharacterAttribute
        var secondary: CharacterAttribute
    }
}

extension TrainingQueue {
    /// `AttributeRemap.optimal(for: items, current: baseAttributes, implants: implantBonus)`.
    public func optimalRemap() -> AttributeRemap? {
        AttributeRemap.optimal(for: items, current: baseAttributes, implants: implantBonus)
    }
}

/// When the character can remap next, from the `/attributes` response.
public struct RemapAvailability: Sendable, Hashable {
    public var bonusRemaps: Int
    public var nextNeuralRemap: Date?

    public init(bonusRemaps: Int, nextNeuralRemap: Date?) {
        self.bonusRemaps = bonusRemaps
        self.nextNeuralRemap = nextNeuralRemap
    }

    /// `nil` when the snapshot carries no remap data at all.
    ///
    /// Uses `accrued_remap_cooldown_date`, falling back to one year after the last remap.
    public init?(snapshot: CharacterSnapshot) {
        let next = snapshot.accruedRemapCooldownDate
            ?? snapshot.lastRemapDate.flatMap { Calendar.current.date(byAdding: .year, value: 1, to: $0) }
        guard snapshot.bonusRemaps != nil || next != nil else { return nil }
        self.init(bonusRemaps: snapshot.bonusRemaps ?? 0, nextNeuralRemap: next)
    }

    /// A banked remap can be spent at once, the free one only after its date.
    public func isAvailable(at now: Date) -> Bool {
        bonusRemaps > 0 || (nextNeuralRemap.map { $0 <= now } ?? false)
    }
}
