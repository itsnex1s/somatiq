import Foundation
import SwiftData

struct DashboardSnapshot {
    let today: DailyScore
    let weekScores: [DailyScore]
    let reports: [WellnessReport]
    let isCalibrating: Bool
}

@MainActor
final class DashboardDataService {
    private let storage: StorageService
    private let baselineService: BaselineService
    private let healthDataProvider: any HealthDataProviding
    private let scoreEngine: ScoreEngine
    private let insightGenerator: InsightGenerator
    private let reportService: WellnessReportService
    private let reportNotifier: any ReportNotifying
    private let hrvLookbackWindows = [24, 72, 168]

    init(
        context: ModelContext,
        healthDataProvider: any HealthDataProviding = HealthKitService(),
        scoreEngine: ScoreEngine = ScoreEngine(),
        insightGenerator: InsightGenerator = InsightGenerator(),
        reportNotifier: any ReportNotifying = NoopReportNotificationService()
    ) {
        let storage = StorageService(context: context)
        self.storage = storage
        baselineService = BaselineService(storage: storage)
        self.healthDataProvider = healthDataProvider
        self.scoreEngine = scoreEngine
        self.insightGenerator = insightGenerator
        reportService = WellnessReportService(storage: storage)
        self.reportNotifier = reportNotifier
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
        let reports = try reportService.fetchRecentReports(limit: 180)
        let baseline = try baselineService.baselineValue(for: .sdnn)
        let isCalibrating = baseline == BaselineMetric.sdnn.populationDefault

        return DashboardSnapshot(
            today: todayScore,
            weekScores: weekScores,
            reports: reports,
            isCalibrating: isCalibrating
        )
    }

    func recalculateToday(
        requestAuthorization: Bool = true,
        energySource: String = "daily_recalc"
    ) async throws -> DailyScore {
        try await calculateAndPersistTodayScore(
            requestAuthorization: requestAuthorization,
            batterySource: energySource
        )
    }

    private func calculateAndPersistTodayScore(
        requestAuthorization: Bool,
        batterySource: String
    ) async throws -> DailyScore {
        if requestAuthorization {
            try await healthDataProvider.requestAuthorization()
        }

        let preferences = try storage.fetchPreferences()
        let targetSleepHours = preferences.targetSleepHours

        let avgSDNN = try await resolveAverageSDNN()

        guard let restingHR = try await healthDataProvider.queryRestingHR(), restingHR > 0 else {
            throw HealthKitError.noRecentWatchData
        }
        let sleep = try await healthDataProvider.querySleep(for: Date())
        let calories = try await healthDataProvider.queryActiveEnergy(for: Date())
        let steps = try await healthDataProvider.querySteps(for: Date())

        if avgSDNN <= 0,
           sleep.totalSleepMinutes <= 0,
           calories <= 0,
           steps <= 0 {
            throw HealthKitError.noRecentWatchData
        }

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

        let previousBattery = try storage.latestBatteryReading()?.level
        let wakeHours: Double
        if let sleepEnd = sleep.inBedEnd {
            wakeHours = max(Date().timeIntervalSince(sleepEnd) / 3600, 0)
        } else {
            wakeHours = 8
        }

        // Compute sleep debt: rolling 3-day avg sleep vs target
        let recentScores = try storage.fetchDailyScores(days: 3)
        let recentSleepHours = recentScores.map { $0.sleepDurationMin / 60 }
        let avgRecentSleep = recentSleepHours.isEmpty ? targetSleepHours : (Statistics.mean(recentSleepHours) ?? targetSleepHours)
        let sleepDebtHours = max(targetSleepHours - avgRecentSleep, 0)

        // Overnight recovery bonus: SDNN >110% baseline AND RHR <95% baseline
        let overnightRecoveryBonus = avgSDNN > baselineSDNN * 1.10 && restingHR < baselineRHR * 0.95

        let battery = scoreEngine.calculateBodyBattery(
            sleepData: sleep,
            currentSDNN: avgSDNN,
            baselineSDNN: baselineSDNN,
            currentRHR: restingHR,
            baselineRHR: baselineRHR,
            activeCalories: calories,
            steps: steps,
            wakeHours: wakeHours,
            previousBattery: previousBattery,
            sleepDebtHours: sleepDebtHours,
            overnightRecoveryBonus: overnightRecoveryBonus
        )

        try storage.saveBatteryReading(level: Double(battery.score), source: batterySource)

        let insight = insightGenerator.generateInsight(
            stress: stress,
            sleep: sleepResult,
            battery: battery,
            sleepHours: sleep.totalSleepMinutes / 60,
            hrv: avgSDNN,
            baselineHRV: baselineSDNN
        )

        let todayScore = DailyScore(
            date: Date(),
            stressScore: stress.score,
            sleepScore: sleepResult.score,
            bodyBatteryScore: battery.score,
            stressLevel: stress.level.rawValue,
            sleepLevel: sleepResult.level.rawValue,
            bodyBatteryLevel: battery.level.rawValue,
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

        do {
            if let report = try reportService.generateReportIfNeeded(for: todayScore, source: batterySource) {
                await reportNotifier.notify(report: report)
            }
        } catch {
            AppLog.error("DashboardDataService.generateReportIfNeeded", error: error)
        }

        return todayScore
    }

    private func resolveAverageSDNN() async throws -> Double {
        for window in hrvLookbackWindows {
            let hrvSamples = try await healthDataProvider.queryHRV(last: window)
            if let avgSDNN = Statistics.mean(hrvSamples.map(\.sdnn)), avgSDNN > 0 {
                if window > 24 {
                    AppLog.info("Using fallback HRV lookback window: \(window)h")
                }
                return avgSDNN
            }
        }

        throw HealthKitError.noRecentWatchData
    }
}
