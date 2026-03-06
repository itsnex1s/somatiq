import Foundation
import SwiftData

struct DashboardSnapshot {
    let today: DailyScore
    let weekScores: [DailyScore]
    let reports: [WellnessReport]
    let isCalibrating: Bool
}

@MainActor
final class DashboardDataService: DashboardSnapshotProviding {
    private let storage: StorageService
    private let healthDataProvider: any HealthDataProviding
    private let scoreEngine: ScoreEngine
    private let insightGenerator: InsightGenerator
    private let reportService: WellnessReportService
    private let reportNotifier: any ReportNotifying
    private let dynamicRefreshInterval: TimeInterval = 5 * 60

    init(
        context: ModelContext,
        healthDataProvider: any HealthDataProviding = HealthKitService(),
        scoreEngine: ScoreEngine = ScoreEngine(),
        insightGenerator: InsightGenerator = InsightGenerator(),
        reportNotifier: any ReportNotifying = NoopReportNotificationService()
    ) {
        let storage = StorageService(context: context)
        self.storage = storage
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
        let cachedToday = try storage.fetchDailyScore(on: Date())

        let todayScore: DailyScore
        if forceRecalculate {
            todayScore = try await recalculateToday(
                requestAuthorization: true,
                energySource: "manual_refresh"
            )
        } else if let cachedToday, !needsDynamicRefresh(cached: cachedToday) {
            todayScore = cachedToday
        } else {
            todayScore = try await recalculateToday(
                requestAuthorization: false,
                energySource: cachedToday == nil ? "daily_recalc" : "auto_refresh"
            )
        }

        let weekScores = try storage.fetchDailyScores(days: 7)
        let reports = try reportService.fetchRecentReports(limit: 180)
        let history60 = try storage.fetchDailyScores(days: 60)
        let isCalibrating = calibrationState(from: history60)

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
        let history60 = try storage.fetchDailyScores(days: 60)
        let isCalibrating = calibrationState(from: history60)

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

        let rawInput = try await healthDataProvider.queryDailyInput(for: Date())
        let hasAnySignal = rawInput.sleep.totalSleepMinutes > 0
            || !rawInput.nightSDNNSamples.isEmpty
            || !rawInput.nightHeartRateBins.isEmpty
            || rawInput.activeEnergy > 0
            || rawInput.steps > 0
        if !hasAnySignal {
            throw HealthKitError.noData
        }

        let allScores = try storage.fetchDailyScores(days: 60)
        let today = Date().startOfDay
        let history = allScores.filter { $0.date < today }
        let baseline = scoreEngine.buildBaseline(from: history)

        let previousToday = try storage.fetchDailyScore(on: Date())
        let sleepLocked = shouldLockSleep(previousToday: previousToday)
        let input = sleepLocked
            ? applyLockedSleep(rawInput: rawInput, previousToday: previousToday)
            : rawInput

        let previousPublished = previousToday ?? history.last
        let computed = scoreEngine.compute(
            input: input,
            baseline: baseline,
            previousPublished: previousPublished
        )

        if computed.confidence < 0.4, previousPublished == nil {
            throw HealthKitError.noRecentWatchData
        }

        let effectiveSleep = resolveEffectiveSleep(
            computed: computed,
            input: input,
            previousToday: previousToday,
            sleepLocked: sleepLocked
        )

        var qualityReasons = computed.qualityReasons
        if sleepLocked {
            qualityReasons.append("sleep_locked")
        }
        qualityReasons = Array(Set(qualityReasons)).sorted()
        let qualityReason = qualityReasons.isEmpty ? "stable" : qualityReasons.joined(separator: ",")

        let insight = insightGenerator.generateInsight(
            stress: computed.stress,
            sleep: effectiveSleep.result,
            battery: computed.battery,
            sleepHours: effectiveSleep.metrics.totalSleepMinutes / 60,
            hrv: computed.publishedHRV,
            baselineHRV: exp(baseline.lnHrvMedian28),
            scoreConfidence: computed.confidence,
            qualityReason: qualityReason
        )

        try storage.saveBatteryReading(level: Double(computed.battery.score), source: batterySource)

        let todayScore = DailyScore(
            date: Date(),
            stressScore: computed.stress.score,
            sleepScore: effectiveSleep.result.score,
            bodyBatteryScore: computed.battery.score,
            stressLevel: computed.stress.level.rawValue,
            sleepLevel: effectiveSleep.result.level.rawValue,
            bodyBatteryLevel: computed.battery.level.rawValue,
            sleepDurationMin: effectiveSleep.metrics.totalSleepMinutes,
            sleepEfficiency: effectiveSleep.metrics.efficiency,
            deepSleepMin: effectiveSleep.metrics.deepMinutes,
            remSleepMin: effectiveSleep.metrics.remMinutes,
            coreSleepMin: effectiveSleep.metrics.coreMinutes,
            bedtimeAt: effectiveSleep.metrics.bedtime,
            avgSDNN: computed.publishedHRV,
            restingHR: computed.nightlyRHR,
            heartScore: computed.heartScore,
            activeCalories: input.activeEnergy,
            steps: input.steps,
            insightText: insight,
            scoreConfidence: computed.confidence,
            qualityReason: qualityReason
        )

        try storage.upsertDailyScore(todayScore)

        do {
            if let report = try reportService.generateReportIfNeeded(for: todayScore, source: batterySource) {
                await reportNotifier.notify(report: report)
            }
        } catch {
            AppLog.error("DashboardDataService.generateReportIfNeeded", error: error)
        }

        return todayScore
    }

    private func calibrationState(from scores: [DailyScore]) -> Bool {
        let validCount = scores.filter { score in
            score.sleepDurationMin >= 240
                && score.avgSDNN > 0
                && score.restingHR > 0
                && (score.scoreConfidence ?? 0) >= 0.4
        }.count
        return validCount < 14
    }

    private func needsDynamicRefresh(cached: DailyScore) -> Bool {
        Date().timeIntervalSince(cached.updatedAt) >= dynamicRefreshInterval
    }

    private func shouldLockSleep(previousToday: DailyScore?) -> Bool {
        guard let previousToday else { return false }
        return previousToday.sleepDurationMin > 0
    }

    private func applyLockedSleep(rawInput: DailyHealthInput, previousToday: DailyScore?) -> DailyHealthInput {
        guard let previousToday else { return rawInput }

        let lockedSleep = SleepData(
            segments: [],
            inBedStart: previousToday.bedtimeAt,
            inBedEnd: previousToday.bedtimeAt.map { start in
                let inBedMinutes = previousToday.sleepEfficiency > 0
                    ? previousToday.sleepDurationMin / max(previousToday.sleepEfficiency, 0.01)
                    : previousToday.sleepDurationMin
                return start.addingTimeInterval(max(inBedMinutes, 0) * 60)
            },
            totalSleepMinutes: previousToday.sleepDurationMin,
            deepMinutes: previousToday.deepSleepMin,
            remMinutes: previousToday.remSleepMin,
            coreMinutes: previousToday.coreSleepMin,
            awakeMinutes: max(
                (
                    previousToday.sleepEfficiency > 0
                        ? previousToday.sleepDurationMin / max(previousToday.sleepEfficiency, 0.01)
                        : previousToday.sleepDurationMin
                ) - previousToday.sleepDurationMin,
                0
            ),
            efficiency: previousToday.sleepEfficiency > 0 ? previousToday.sleepEfficiency : rawInput.sleep.efficiency,
            bedtime: previousToday.bedtimeAt ?? rawInput.sleep.bedtime,
            stageCoverage: previousToday.sleepDurationMin > 0
                ? Statistics.clamped(
                    (previousToday.deepSleepMin + previousToday.remSleepMin + previousToday.coreSleepMin)
                        / max(previousToday.sleepDurationMin, 1),
                    min: 0,
                    max: 1
                )
                : rawInput.sleep.stageCoverage,
            sourcePurity: rawInput.sleep.sourcePurity,
            interruptionsCount: rawInput.sleep.interruptionsCount
        )

        return DailyHealthInput(
            sleep: lockedSleep,
            nightSDNNSamples: rawInput.nightSDNNSamples,
            nightRMSDDSamples: rawInput.nightRMSDDSamples,
            nightHeartRateBins: rawInput.nightHeartRateBins,
            restWindows: rawInput.restWindows,
            activeEnergy: rawInput.activeEnergy,
            steps: rawInput.steps,
            workoutMinutes: rawInput.workoutMinutes,
            dayWatchWearCoverage: rawInput.dayWatchWearCoverage,
            nightHRCoverage: rawInput.nightHRCoverage,
            sourcePurity: rawInput.sourcePurity,
            qualityNotes: rawInput.qualityNotes
        )
    }

    private func resolveEffectiveSleep(
        computed: EngineComputation,
        input: DailyHealthInput,
        previousToday: DailyScore?,
        sleepLocked: Bool
    ) -> (result: SleepResult, metrics: SleepData) {
        guard sleepLocked, let previousToday else {
            return (computed.sleep, input.sleep)
        }

        let previousSleepLevel = SleepLevel(rawValue: previousToday.sleepLevel) ?? computed.sleep.level
        let result = SleepResult(score: previousToday.sleepScore, level: previousSleepLevel)
        return (result, input.sleep)
    }
}
