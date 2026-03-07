import XCTest
@testable import Somatiq

final class ScoreEngineTests: XCTestCase {
    private let engine = ScoreEngine()

    func testComputeReturnsLowStressForStrongRecoverySignals() {
        let baseline = engine.buildBaseline(from: makeHistory(days: 28, hrv: 42, rhr: 62, sleepHours: 7.6))
        let input = makeInput(
            sleepHours: 7.8,
            efficiency: 0.91,
            hrv: 55,
            nightHR: [53, 54, 55, 54, 53, 52],
            restWindows: [
                RestWindowSample(timestamp: Date(), heartRate: 58, lnHRV: log(52), sourceRank: 3),
                RestWindowSample(timestamp: Date().addingTimeInterval(-1_800), heartRate: 59, lnHRV: log(50), sourceRank: 3),
                RestWindowSample(timestamp: Date().addingTimeInterval(-3_600), heartRate: 57, lnHRV: log(51), sourceRank: 3),
            ],
            activeEnergy: 280,
            steps: 5_100
        )

        let result = engine.compute(input: input, baseline: baseline, previousPublished: nil)

        XCTAssertLessThan(result.stress.score, 45)
        XCTAssertTrue([StressLevel.low, .moderate].contains(result.stress.level))
    }

    func testComputeReturnsHighStressForPoorRecoverySignals() {
        let baseline = engine.buildBaseline(from: makeHistory(days: 28, hrv: 45, rhr: 60, sleepHours: 7.5))
        let input = makeInput(
            sleepHours: 5.1,
            efficiency: 0.72,
            hrv: 19,
            nightHR: [76, 78, 75, 77, 79, 80],
            restWindows: [
                RestWindowSample(timestamp: Date(), heartRate: 84, lnHRV: log(18), sourceRank: 3),
                RestWindowSample(timestamp: Date().addingTimeInterval(-1_800), heartRate: 82, lnHRV: log(20), sourceRank: 3),
                RestWindowSample(timestamp: Date().addingTimeInterval(-3_600), heartRate: 86, lnHRV: log(17), sourceRank: 3),
            ],
            activeEnergy: 900,
            steps: 16_000
        )

        let result = engine.compute(input: input, baseline: baseline, previousPublished: nil)

        XCTAssertGreaterThan(result.stress.score, 60)
        XCTAssertEqual(result.stress.level, .high)
    }

    func testComputeUsesCalibrationModeBeforeWarmup() {
        let baseline = engine.buildBaseline(from: makeHistory(days: 5, hrv: 40, rhr: 62, sleepHours: 7.3))
        let previous = DailyScore(
            date: Date().addingTimeInterval(-86_400),
            stressScore: 48,
            sleepScore: 66,
            bodyBatteryScore: 64,
            stressLevel: StressLevel.moderate.rawValue,
            sleepLevel: SleepLevel.good.rawValue,
            bodyBatteryLevel: BatteryLevel.good.rawValue,
            sleepDurationMin: 430,
            sleepEfficiency: 0.88,
            deepSleepMin: 85,
            remSleepMin: 95,
            coreSleepMin: 250,
            avgSDNN: 40,
            restingHR: 62,
            activeCalories: 380,
            steps: 7_000,
            insightText: "prev",
            scoreConfidence: 0.6,
            qualityReason: "stable"
        )

        let input = makeInput(
            sleepHours: 7.5,
            efficiency: 0.89,
            hrv: 48,
            nightHR: [56, 56, 57, 55, 54, 56],
            restWindows: [
                RestWindowSample(timestamp: Date(), heartRate: 61, lnHRV: log(44), sourceRank: 3),
                RestWindowSample(timestamp: Date().addingTimeInterval(-1_800), heartRate: 60, lnHRV: log(43), sourceRank: 3),
                RestWindowSample(timestamp: Date().addingTimeInterval(-3_600), heartRate: 62, lnHRV: log(42), sourceRank: 3),
            ],
            activeEnergy: 420,
            steps: 8_200
        )

        let result = engine.compute(input: input, baseline: baseline, previousPublished: previous)

        XCTAssertTrue(result.isCalibrating)
        XCTAssertLessThanOrEqual(result.confidence, 0.5)
        XCTAssertEqual(result.stress.score, previous.stressScore)
        XCTAssertEqual(result.battery.score, previous.bodyBatteryScore)
    }

    func testBuildBaselineUsesPersonalHistoryOnly() {
        let history = makeHistory(days: 30, hrv: 50, rhr: 58, sleepHours: 7.9)
        let baseline = engine.buildBaseline(from: history)

        XCTAssertEqual(exp(baseline.lnHrvMedian28), 50, accuracy: 0.5)
        XCTAssertEqual(baseline.rhrMedian28, 58, accuracy: 0.5)
        XCTAssertEqual(baseline.durationMedian28Hours, 7.9, accuracy: 0.2)
    }

    func testComputeDoesNotCarrySleepWhenNoCurrentNightSleep() {
        let baseline = engine.buildBaseline(from: makeHistory(days: 28, hrv: 46, rhr: 60, sleepHours: 7.4))
        let previous = DailyScore(
            date: Date().addingTimeInterval(-86_400),
            stressScore: 44,
            sleepScore: 79,
            bodyBatteryScore: 72,
            stressLevel: StressLevel.moderate.rawValue,
            sleepLevel: SleepLevel.good.rawValue,
            bodyBatteryLevel: BatteryLevel.good.rawValue,
            sleepDurationMin: 440,
            sleepEfficiency: 0.9,
            deepSleepMin: 95,
            remSleepMin: 98,
            coreSleepMin: 247,
            bedtimeAt: Date().addingTimeInterval(-9 * 3_600),
            avgSDNN: 46,
            restingHR: 60,
            activeCalories: 420,
            steps: 8_200,
            insightText: "prev",
            scoreConfidence: 0.82,
            qualityReason: "stable"
        )

        let input = makeInput(
            sleepHours: 0,
            efficiency: 0,
            hrv: 42,
            nightHR: [57, 56, 58, 55],
            restWindows: [
                RestWindowSample(timestamp: Date(), heartRate: 63, lnHRV: log(40), sourceRank: 3),
                RestWindowSample(timestamp: Date().addingTimeInterval(-1_800), heartRate: 64, lnHRV: log(39), sourceRank: 3),
                RestWindowSample(timestamp: Date().addingTimeInterval(-3_600), heartRate: 62, lnHRV: log(41), sourceRank: 3),
            ],
            activeEnergy: 350,
            steps: 6_700
        )

        let result = engine.compute(input: input, baseline: baseline, previousPublished: previous)

        XCTAssertEqual(result.sleep.score, 0)
        XCTAssertTrue(result.qualityReasons.contains("sleep_missing_today"))
    }

    private func makeInput(
        sleepHours: Double,
        efficiency: Double,
        hrv: Double,
        nightHR: [Double],
        restWindows: [RestWindowSample],
        activeEnergy: Double,
        steps: Int
    ) -> DailyHealthInput {
        let start = Date().addingTimeInterval(-sleepHours * 3_600)
        let end = Date()
        let totalMinutes = sleepHours * 60
        let deep = totalMinutes * 0.2
        let rem = totalMinutes * 0.22
        let core = totalMinutes - deep - rem

        let sleep = SleepData(
            segments: [],
            inBedStart: start,
            inBedEnd: end,
            totalSleepMinutes: totalMinutes,
            deepMinutes: deep,
            remMinutes: rem,
            coreMinutes: core,
            awakeMinutes: max((1 - efficiency) * totalMinutes, 0),
            efficiency: efficiency,
            bedtime: start,
            stageCoverage: totalMinutes > 0 ? 0.82 : 0,
            sourcePurity: 0.95,
            interruptionsCount: 2
        )

        return DailyHealthInput(
            sleep: sleep,
            nightSDNNSamples: [
                HRVSample(value: hrv, date: end.addingTimeInterval(-7_200), sourceRank: 3, algorithmVersion: "1")
            ],
            nightRMSDDSamples: [],
            nightHeartRateBins: nightHR,
            restWindows: restWindows,
            activeEnergy: activeEnergy,
            steps: steps,
            workoutMinutes: 20,
            dayWatchWearCoverage: 0.8,
            nightHRCoverage: 0.65,
            sourcePurity: 0.9,
            qualityNotes: []
        )
    }

    private func makeHistory(days: Int, hrv: Double, rhr: Double, sleepHours: Double) -> [DailyScore] {
        (0..<days).map { index in
            let date = Date().addingTimeInterval(-Double(days - index) * 86_400)
            return DailyScore(
                date: date,
                stressScore: 50,
                sleepScore: 65,
                bodyBatteryScore: 65,
                stressLevel: StressLevel.moderate.rawValue,
                sleepLevel: SleepLevel.good.rawValue,
                bodyBatteryLevel: BatteryLevel.good.rawValue,
                sleepDurationMin: sleepHours * 60,
                sleepEfficiency: 0.88,
                deepSleepMin: sleepHours * 12,
                remSleepMin: sleepHours * 14,
                coreSleepMin: sleepHours * 34,
                bedtimeAt: date.addingTimeInterval(-sleepHours * 3_600),
                avgSDNN: hrv,
                restingHR: rhr,
                activeCalories: 420,
                steps: 8_000,
                insightText: "history",
                scoreConfidence: 0.8,
                qualityReason: "stable"
            )
        }
    }
}
