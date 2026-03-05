import Foundation
import SwiftData

struct DashboardSnapshot {
    let today: DailyScore
    let weekScores: [DailyScore]
    let isCalibrating: Bool
}

@MainActor
final class DashboardDataService {
    private let storage: StorageService
    private let baselineService: BaselineService
    private let healthDataProvider: any HealthDataProviding
    private let scoreEngine: ScoreEngine
    private let insightGenerator: InsightGenerator

    init(
        context: ModelContext,
        healthDataProvider: any HealthDataProviding = HealthKitService(),
        scoreEngine: ScoreEngine = ScoreEngine(),
        insightGenerator: InsightGenerator = InsightGenerator()
    ) {
        let storage = StorageService(context: context)
        self.storage = storage
        baselineService = BaselineService(storage: storage)
        self.healthDataProvider = healthDataProvider
        self.scoreEngine = scoreEngine
        self.insightGenerator = insightGenerator
    }

    func authorizeHealth() async throws {
        try await healthDataProvider.authorizeAndEnableBackgroundDelivery()
    }

    func fetchSnapshot(forceRecalculate: Bool) async throws -> DashboardSnapshot {
        let todayScore: DailyScore
        if !forceRecalculate, let cached = try storage.fetchDailyScore(on: Date()) {
            todayScore = cached
        } else {
            todayScore = try await recalculateToday()
        }

        let weekScores = try storage.fetchDailyScores(days: 7)
        let baseline = try baselineService.baselineValue(for: .sdnn)
        let isCalibrating = baseline == BaselineMetric.sdnn.populationDefault

        return DashboardSnapshot(
            today: todayScore,
            weekScores: weekScores,
            isCalibrating: isCalibrating
        )
    }

    func recalculateToday(
        requestAuthorization: Bool = true,
        energySource: String = "daily_recalc"
    ) async throws -> DailyScore {
        try await calculateAndPersistTodayScore(
            requestAuthorization: requestAuthorization,
            energySource: energySource
        )
    }

    private func calculateAndPersistTodayScore(
        requestAuthorization: Bool,
        energySource: String
    ) async throws -> DailyScore {
        if requestAuthorization {
            try await healthDataProvider.requestAuthorization()
        }

        let preferences = try storage.fetchPreferences()
        let targetSleepHours = preferences.targetSleepHours

        let hrvSamples = try await healthDataProvider.queryHRV(last: 24)
        guard let avgSDNN = Statistics.mean(hrvSamples.map(\.sdnn)), avgSDNN > 0 else {
            throw HealthKitError.noData
        }

        let restingHR = try await healthDataProvider.queryRestingHR() ?? BaselineMetric.restingHR.populationDefault
        let sleep = try await healthDataProvider.querySleep(for: Date())
        let calories = try await healthDataProvider.queryActiveEnergy(for: Date())
        let steps = try await healthDataProvider.querySteps(for: Date())

        let baselineSDNN = try baselineService.baselineValue(for: .sdnn)
        let baselineRHR = try baselineService.baselineValue(for: .restingHR)

        var bedtimeHistory = try storage.fetchBedtimes(days: 7)
        if let bedtime = sleep.bedtime {
            bedtimeHistory.append(bedtime)
        }

        let stress = scoreEngine.calculateStress(
            currentSDNN: avgSDNN,
            currentRHR: restingHR,
            baselineSDNN: baselineSDNN,
            baselineRHR: baselineRHR
        )

        let sleepResult = scoreEngine.calculateSleep(
            sleepData: sleep,
            bedtimeHistory: bedtimeHistory,
            targetHours: targetSleepHours
        )

        let previousEnergy = try storage.latestEnergyReading()?.level
        let wakeHours: Double
        if let sleepEnd = sleep.inBedEnd {
            wakeHours = max(Date().timeIntervalSince(sleepEnd) / 3600, 0)
        } else {
            wakeHours = 8
        }

        let energy = scoreEngine.calculateEnergy(
            sleepData: sleep,
            currentSDNN: avgSDNN,
            baselineSDNN: baselineSDNN,
            currentRHR: restingHR,
            baselineRHR: baselineRHR,
            activeCalories: calories,
            steps: steps,
            wakeHours: wakeHours,
            previousEnergy: previousEnergy
        )

        try storage.saveEnergyReading(level: Double(energy.score), source: energySource)

        let insight = insightGenerator.generateInsight(
            stress: stress,
            sleep: sleepResult,
            energy: energy,
            sleepHours: sleep.totalSleepMinutes / 60,
            hrv: avgSDNN,
            baselineHRV: baselineSDNN
        )

        let todayScore = DailyScore(
            date: Date(),
            stressScore: stress.score,
            sleepScore: sleepResult.score,
            energyScore: energy.score,
            stressLevel: stress.level.rawValue,
            sleepLevel: sleepResult.level.rawValue,
            energyLevel: energy.level.rawValue,
            sleepDurationMin: sleep.totalSleepMinutes,
            sleepEfficiency: sleep.efficiency,
            deepSleepMin: sleep.deepMinutes,
            remSleepMin: sleep.remMinutes,
            coreSleepMin: sleep.coreMinutes,
            bedtimeAt: sleep.bedtime,
            avgSDNN: avgSDNN,
            restingHR: restingHR,
            activeCalories: calories,
            steps: steps,
            insightText: insight
        )

        try storage.upsertDailyScore(todayScore)
        try baselineService.recalculateBaselines()
        return todayScore
    }
}
