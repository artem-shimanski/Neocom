import Testing
@testable import TrainingKit

struct TrainingMathTests {
    // MARK: - skillPoints Tests

    @Test("skillPoints for rank 1 matches game data")
    func skillPointsRank1() {
        let testCases = [
            (level: 1, expected: 250),
            (level: 2, expected: 1414),
            (level: 3, expected: 8000),
            (level: 4, expected: 45255),
            (level: 5, expected: 256000),
        ]

        for (level, expected) in testCases {
            let result = TrainingMath.skillPoints(rank: 1, level: level)
            #expect(result == expected, "skillPoints(rank: 1, level: \(level)) should be \(expected), got \(result)")
        }
    }

    @Test("skillPoints(rank: 3, level: 2) equals 4243")
    func skillPointsRank3Level2() {
        let result = TrainingMath.skillPoints(rank: 3, level: 2)
        #expect(result == 4243)
    }

    @Test("skillPoints with zero rank or level returns 0")
    func skillPointsZeroRankOrLevel() {
        #expect(TrainingMath.skillPoints(rank: 0, level: 1) == 0)
        #expect(TrainingMath.skillPoints(rank: 1, level: 0) == 0)
        #expect(TrainingMath.skillPoints(rank: 0, level: 0) == 0)
    }

    // MARK: - level Tests

    @Test("level is inverse of skillPoints for all levels")
    func levelIsInverse() {
        let testLevels = [1, 2, 3, 4, 5]

        for lvl in testLevels {
            let sp = TrainingMath.skillPoints(rank: 1, level: lvl)
            let resultLevel = TrainingMath.level(rank: 1, skillPoints: sp)
            #expect(resultLevel == lvl, "level(rank: 1, skillPoints: \(sp)) should be \(lvl), got \(resultLevel)")
        }
    }

    @Test("level returns 0 for zero rank or skillPoints")
    func levelZeroRankOrSkillPoints() {
        #expect(TrainingMath.level(rank: 0, skillPoints: 100) == 0)
        #expect(TrainingMath.level(rank: 1, skillPoints: 0) == 0)
        #expect(TrainingMath.level(rank: 0, skillPoints: 0) == 0)
    }

    @Test("level returns highest matching level")
    func levelHighestMatching() {
        // skillPoints(rank: 1, level: 2) == 1414
        // skillPoints(rank: 1, level: 3) == 8000
        // So for skillPoints = 2000, level should be 2
        let result = TrainingMath.level(rank: 1, skillPoints: 2000)
        #expect(result == 2)
    }

    // MARK: - skillPointsPerSecond Tests

    @Test("skillPointsPerSecond(primary: 20, secondary: 20) equals 0.5")
    func skillPointsPerSecondTest() {
        let result = TrainingMath.skillPointsPerSecond(primary: 20, secondary: 20)
        #expect(result == 0.5)
    }

    // MARK: - trainingTime Tests

    @Test("trainingTime with zero skill points returns 0")
    func trainingTimeZeroSkillPoints() {
        let result = TrainingMath.trainingTime(skillPoints: 0, primary: 20, secondary: 20)
        #expect(result == 0)
    }

    @Test("trainingTime with zero rate returns 0 instead of dividing by zero")
    func trainingTimeZeroRate() {
        let result = TrainingMath.trainingTime(skillPoints: 1000, primary: 0, secondary: 0)
        #expect(result == 0)
    }

    @Test("trainingTime calculation is correct")
    func trainingTimeCalculation() {
        // skillPointsPerSecond(primary: 20, secondary: 20) == 0.5
        // trainingTime(skillPoints: 250, primary: 20, secondary: 20) should be 250 / 0.5 = 500 seconds
        let result = TrainingMath.trainingTime(skillPoints: 250, primary: 20, secondary: 20)
        #expect(result == 500)
    }
}
