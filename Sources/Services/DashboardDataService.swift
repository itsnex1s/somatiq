import Foundation
import SwiftData

struct DashboardSnapshot {
    let today: DailyScore
    let weekScores: [DailyScore]
    let reports: [WellnessReport]
    let isCalibrating: Bool
}

private struct HRVContext {
    let avgSDNN: Double
    let sampleCount: Int
    let plausibleRatio: Double
    let uniqueHours: Int
    let lookbackHours: Int
}

private struct CoreBaselineBundle {
    let sdnnMedian28: Double
    let sdnnIqr28: Double
    let sdnnMedian60: Double
    let sdnnIqr60: Double
    let rhrMedian28: Double
    let rhrIqr28: Double
    let loadMedian28: Double
    let sleepHoursMedian60: Double
    let bedtimeMinutesMedian60: Double?
    let readinessFactor: Double
}

private struct QualityEvaluation {
    let confidence: Double
    let reason: String?
}

@MainActor
final class DashboardDataService: DashboardSnapshotProviding {
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

    func fetchCachedSnapshot() throws -> DashboardSnapshot? {
        guard let todayScore = try storage.fetchDailyScore(on: Date()) else {
            return nil
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

        let hrvContext = try await resolveHRVContext()
        let avgSDNN = hrvContext.avgSDNN

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
        let history60 = try storage.fetchDailyScores(days: 60)
        let baseline = buildCoreBaseline(
            history60: history60,
            fallbackSDNN: baselineSDNN,
            fallbackRHR: baselineRHR,
            targetSleepHours: targetSleepHours
        )

        var bedtimeHistory = try storage.fetchBedtimes(days: 7)
        if let bedtime = sleep.bedtime {
            bedtimeHistory.append(bedtime)
        }
        let loadToday = scoreEngine.estimateLoad(activeCalories: calories, steps: steps)

        let stress = scoreEngine.calculateStress(
            currentSDNN: avgSDNN,
            currentRHR: restingHR,
            baselineSDNN: baseline.sdnnMedian28,
            baselineRHR: baseline.rhrMedian28,
            baselineSDNNIQR: baseline.sdnnIqr28,
            baselineRHRIQR: baseline.rhrIqr28,
            currentLoad: loadToday,
            baselineLoad: baseline.loadMedian28
        )

        let sleepResult = scoreEngine.calculateSleep(
            sleepData: sleep,
            bedtimeHistory: bedtimeHistory,
            targetHours: max(targetSleepHours, baseline.sleepHoursMedian60),
            currentSDNN: avgSDNN,
            currentRHR: restingHR,
            baselineSDNN: baseline.sdnnMedian28,
            baselineRHR: baseline.rhrMedian28,
            baselineSleepMidpointMinutes: baseline.bedtimeMinutesMedian60
        )

        let previousBattery = try storage.latestBatteryReading()?.level
        let wakeHours: Double
        if let sleepEnd = sleep.inBedEnd {
            wakeHours = max(Date().timeIntervalSince(sleepEnd) / 3600, 0)
        } else {
            wakeHours = 8
        }

        // Compute sleep debt: rolling 7-day avg sleep vs personalized need
        let recentScores = try storage.fetchDailyScores(days: 7)
        let recentSleepHours = recentScores.map { $0.sleepDurationMin / 60 }
        let sleepNeed = max(baseline.sleepHoursMedian60, targetSleepHours, 7)
        let avgRecentSleep = recentSleepHours.isEmpty ? sleepNeed : (Statistics.mean(recentSleepHours) ?? sleepNeed)
        let sleepDebtHours = max(sleepNeed - avgRecentSleep, 0)

        // Overnight recovery bonus: SDNN >110% baseline AND RHR <95% baseline
        let overnightRecoveryBonus = avgSDNN > baseline.sdnnMedian28 * 1.10 && restingHR < baseline.rhrMedian28 * 0.95

        let battery = scoreEngine.calculateBodyBattery(
            sleepData: sleep,
            currentSDNN: avgSDNN,
            baselineSDNN: baseline.sdnnMedian28,
            currentRHR: restingHR,
            baselineRHR: baseline.rhrMedian28,
            activeCalories: calories,
            steps: steps,
            wakeHours: wakeHours,
            previousBattery: previousBattery,
            sleepDebtHours: sleepDebtHours,
            overnightRecoveryBonus: overnightRecoveryBonus,
            stressScore: stress.score
        )

        let quality = evaluateQuality(
            hrvContext: hrvContext,
            sleep: sleep,
            restingHR: restingHR,
            baselineReadinessFactor: baseline.readinessFactor
        )

        if quality.confidence < 0.45 {
            throw HealthKitError.noRecentWatchData
        }

        if quality.confidence < 0.70,
           let cached = try storage.fetchDailyScore(on: Date()) {
            AppLog.info("Skipping noisy score update (confidence \(quality.confidence)).")
            return cached
        }

        let heartScore = scoreEngine.calculateHeartScore(
            currentSDNN: avgSDNN,
            baselineSDNN: baseline.sdnnMedian60,
            baselineSDNNIQR: baseline.sdnnIqr60,
            recentSDNNValues: history60.map(\.avgSDNN).filter { $0 > 0 }
        )

        try storage.saveBatteryReading(level: Double(battery.score), source: batterySource)

        let insight = insightGenerator.generateInsight(
            stress: stress,
            sleep: sleepResult,
            battery: battery,
            sleepHours: sleep.totalSleepMinutes / 60,
            hrv: avgSDNN,
            baselineHRV: baseline.sdnnMedian28,
            scoreConfidence: quality.confidence,
            qualityReason: quality.reason
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
            insightText: insight,
            scoreConfidence: quality.confidence,
            qualityReason: quality.reason ?? "stable"
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

        AppLog.info("Heart resilience proxy score: \(heartScore)")

        return todayScore
    }

    private func resolveHRVContext() async throws -> HRVContext {
        for window in hrvLookbackWindows {
            let hrvSamples = try await healthDataProvider.queryHRV(last: window)
            guard !hrvSamples.isEmpty else { continue }

            let plausible = hrvSamples.filter { $0.sdnn >= 5 && $0.sdnn <= 250 }
            guard !plausible.isEmpty else { continue }

            let winsorized = Statistics.winsorized(plausible.map(\.sdnn))
            let aggregated = Statistics.mean(winsorized) ?? Statistics.median(winsorized) ?? 0
            guard aggregated > 0 else { continue }

            let uniqueHours = Set(plausible.map { $0.date.startOfHour }).count
            let plausibleRatio = Double(plausible.count) / Double(hrvSamples.count)

            if aggregated > 0 {
                if window > 24 {
                    AppLog.info("Using fallback HRV lookback window: \(window)h")
                }
                return HRVContext(
                    avgSDNN: aggregated,
                    sampleCount: plausible.count,
                    plausibleRatio: plausibleRatio,
                    uniqueHours: uniqueHours,
                    lookbackHours: window
                )
            }
        }

        throw HealthKitError.noRecentWatchData
    }

    private func buildCoreBaseline(
        history60: [DailyScore],
        fallbackSDNN: Double,
        fallbackRHR: Double,
        targetSleepHours: Double
    ) -> CoreBaselineBundle {
        let sorted = history60.sorted(by: { $0.date < $1.date })
        let last28 = Array(sorted.suffix(28))

        let sdnn28 = last28.map(\.avgSDNN).filter { $0 > 0 }
        let sdnn60 = sorted.map(\.avgSDNN).filter { $0 > 0 }
        let rhr28 = last28.map(\.restingHR).filter { $0 > 0 }
        let load28 = last28
            .map { scoreEngine.estimateLoad(activeCalories: $0.activeCalories, steps: $0.steps) }
            .filter { $0 > 0 }
        let sleep60 = sorted.map { $0.sleepDurationMin / 60 }.filter { $0 > 0 }
        let bedtimeMinutes60 = sorted.compactMap(\.bedtimeAt).map(minutesFromMidnight(for:))

        let validBaselineDays = sorted.filter { $0.avgSDNN > 0 && $0.restingHR > 0 }.count
        let readinessFactor: Double
        switch validBaselineDays {
        case 21...:
            readinessFactor = 1.0
        case 7...20:
            readinessFactor = 0.9
        case 3...6:
            readinessFactor = 0.8
        default:
            readinessFactor = 0.75
        }

        return CoreBaselineBundle(
            sdnnMedian28: Statistics.median(sdnn28) ?? fallbackSDNN,
            sdnnIqr28: max(Statistics.iqr(sdnn28) ?? fallbackSDNN * 0.2, 6),
            sdnnMedian60: Statistics.median(sdnn60) ?? fallbackSDNN,
            sdnnIqr60: max(Statistics.iqr(sdnn60) ?? fallbackSDNN * 0.25, 6),
            rhrMedian28: Statistics.median(rhr28) ?? fallbackRHR,
            rhrIqr28: max(Statistics.iqr(rhr28) ?? fallbackRHR * 0.1, 3),
            loadMedian28: Statistics.median(load28) ?? 0,
            sleepHoursMedian60: Statistics.median(sleep60) ?? max(targetSleepHours, 7),
            bedtimeMinutesMedian60: Statistics.median(bedtimeMinutes60),
            readinessFactor: readinessFactor
        )
    }

    private func evaluateQuality(
        hrvContext: HRVContext,
        sleep: SleepData,
        restingHR: Double,
        baselineReadinessFactor: Double
    ) -> QualityEvaluation {
        let countScore = Statistics.clamped(Double(hrvContext.sampleCount) / 6, min: 0, max: 1)
        let coverageScore = Statistics.clamped(Double(hrvContext.uniqueHours) / 6, min: 0, max: 1)
        let plausibilityScore = Statistics.clamped(hrvContext.plausibleRatio, min: 0, max: 1)

        let qSignal = Statistics.clamped(
            (0.40 * countScore) + (0.35 * coverageScore) + (0.25 * plausibilityScore),
            min: 0,
            max: 1
        )

        let sleepContext = sleep.totalSleepMinutes > 0 ? 1.0 : 0.25
        let rhrContext = restingHR > 0 ? 1.0 : 0.0
        let qContext = (0.65 * sleepContext) + (0.35 * rhrContext)
        let qSource = 0.85

        let confidence = Statistics.clamped(
            ((0.55 * qSignal) + (0.25 * qContext) + (0.20 * qSource)) * baselineReadinessFactor,
            min: 0,
            max: 1
        )

        if confidence >= 0.70 {
            return QualityEvaluation(confidence: confidence, reason: nil)
        }
        if countScore < 0.5 {
            return QualityEvaluation(confidence: confidence, reason: "low HRV sample count")
        }
        if coverageScore < 0.5 {
            return QualityEvaluation(confidence: confidence, reason: "low HRV coverage")
        }
        if sleepContext < 1 {
            return QualityEvaluation(confidence: confidence, reason: "no sleep window detected")
        }
        if baselineReadinessFactor < 0.85 {
            return QualityEvaluation(confidence: confidence, reason: "baseline still calibrating")
        }
        return QualityEvaluation(confidence: confidence, reason: "mixed quality signals")
    }

    private func minutesFromMidnight(for date: Date) -> Double {
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        return Double((components.hour ?? 0) * 60 + (components.minute ?? 0))
    }
}
