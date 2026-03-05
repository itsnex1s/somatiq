import XCTest
@testable import Somatiq

final class ScoreEngineTests: XCTestCase {
    private let engine = ScoreEngine()

    func testStressScoreIsLowWhenHRVAboveBaseline() {
        let result = engine.calculateStress(
            currentSDNN: 72,
            currentRHR: 54,
            baselineSDNN: 40,
            baselineRHR: 65
        )

        XCTAssertLessThan(result.score, 40)
        XCTAssertEqual(result.level, .low)
    }

    func testStressScoreIsHighWhenHRVDropsAndRHRRises() {
        let result = engine.calculateStress(
            currentSDNN: 22,
            currentRHR: 78,
            baselineSDNN: 45,
            baselineRHR: 62
        )

        XCTAssertGreaterThan(result.score, 66)
        XCTAssertEqual(result.level, .high)
    }

    func testSleepScoreRewardsBalancedNight() {
        let sleep = SleepData(
            segments: [],
            inBedStart: Date(),
            inBedEnd: Date().addingTimeInterval(8 * 3600),
            totalSleepMinutes: 450,
            deepMinutes: 85,
            remMinutes: 105,
            coreMinutes: 260,
            awakeMinutes: 25,
            efficiency: 0.9,
            bedtime: Date()
        )

        let result = engine.calculateSleep(
            sleepData: sleep,
            bedtimeHistory: [
                Date(),
                Date().addingTimeInterval(-86_400),
                Date().addingTimeInterval(-172_800),
            ],
            targetHours: 8
        )

        XCTAssertGreaterThan(result.score, 75)
        XCTAssertTrue([SleepLevel.good, .great].contains(result.level))
    }

    func testEnergyScoreClampsToRange() {
        let sleep = SleepData(
            segments: [],
            inBedStart: Date(),
            inBedEnd: Date(),
            totalSleepMinutes: 420,
            deepMinutes: 110,
            remMinutes: 90,
            coreMinutes: 220,
            awakeMinutes: 10,
            efficiency: 0.94,
            bedtime: Date()
        )

        let result = engine.calculateEnergy(
            sleepData: sleep,
            currentSDNN: 55,
            baselineSDNN: 40,
            currentRHR: 62,
            baselineRHR: 65,
            activeCalories: 900,
            steps: 18_000,
            wakeHours: 14,
            previousEnergy: 95
        )

        XCTAssertLessThanOrEqual(result.score, 100)
        XCTAssertGreaterThanOrEqual(result.score, 0)
    }

    func testBlendedBaselineTransitionsToPersonalMedian() async {
        let values = await MainActor.run { () -> (Double, Double) in
            let early = BaselineService.blendedBaseline(personal: 60, population: 40, dayCount: 3)
            let mature = BaselineService.blendedBaseline(personal: 60, population: 40, dayCount: 30)
            return (early, mature)
        }
        let early = values.0
        let mature = values.1

        XCTAssertLessThan(early, mature)
        XCTAssertEqual(mature, 60, accuracy: 0.001)
    }
}
