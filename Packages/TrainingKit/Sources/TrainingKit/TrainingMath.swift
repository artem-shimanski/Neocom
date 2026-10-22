import Foundation

/// Training and skill points calculations.
public enum TrainingMath {
    /// Skill points needed for `level` of a skill of `rank`; 0 for a non-positive level or rank.
    public static func skillPoints(rank: Double, level: Int) -> Int {
        guard level > 0, rank > 0 else { return 0 }
        return Int((250.0 * rank * pow(2, 2.5 * Double(level - 1))).rounded())
    }

    /// The highest level (1...5) whose points do not exceed `skillPoints`; 0 below level 1.
    public static func level(rank: Double, skillPoints: Int) -> Int {
        guard skillPoints > 0, rank > 0 else { return 0 }

        for lvl in (1...5).reversed() {
            let requiredPoints = self.skillPoints(rank: rank, level: lvl)
            if requiredPoints <= skillPoints {
                return lvl
            }
        }
        return 0
    }

    /// Skill points per second: `(primary + secondary / 2) / 60`.
    public static func skillPointsPerSecond(primary: Int, secondary: Int) -> Double {
        (Double(primary) + Double(secondary) / 2) / 60
    }

    /// Seconds needed to train `skillPoints`; 0 when the rate is zero.
    public static func trainingTime(skillPoints: Int, primary: Int, secondary: Int) -> TimeInterval {
        let rate = skillPointsPerSecond(primary: primary, secondary: secondary)
        guard rate > 0 else { return 0 }
        return TimeInterval(skillPoints) / rate
    }
}
