import Foundation
import Observation

@MainActor
@Observable
final class TodayViewModel {
    var isLoading = false
    var isRefreshing = false
    var errorMessage: String?
    var noDataMessage: String?

    var stressScore = 0
    var sleepScore = 0
    var bodyBatteryScore = 0

    var stressLevel = StressLevel.low
    var sleepLevel = SleepLevel.poor
    var bodyBatteryLevel = BatteryLevel.low

    var restingHeartRate = 0
    var hrvValue = 0
    var sleepDurationText = "--"
    var activeCalories = 0
    var steps = 0
    var insightText = "Your body signals are stable today."
    var lastUpdated: Date?
    var isCalibrating = false

    var weekScores: [DailyScore] = []

    var restingHRTrend: VitalTrend = .neutral("--")
    var hrvTrend: VitalTrend = .neutral("--")
    var sleepTrend: VitalTrend = .neutral("--")
    var batteryTrend: VitalTrend = .neutral("--")

    private let dashboardService: DashboardDataService
    let trendsService: TrendsDataService

    init(dashboardService: DashboardDataService, trendsService: TrendsDataService) {
        self.dashboardService = dashboardService
        self.trendsService = trendsService
    }

    func loadIfNeeded() async {
        if lastUpdated == nil {
            await refresh(forceRecalculate: false)
        }
    }

    func requestHealthAuthorization() async {
        do {
            try await dashboardService.authorizeHealth()
        } catch {
            AppLog.error("TodayViewModel.requestHealthAuthorization", error: error)
            errorMessage = AppErrorMapper.userMessage(for: error)
        }
    }

    func refresh(forceRecalculate: Bool) async {
        if forceRecalculate {
            isRefreshing = true
        } else {
            isLoading = true
        }

        defer {
            isLoading = false
            isRefreshing = false
        }

        do {
            errorMessage = nil
            noDataMessage = nil

            let snapshot = try await dashboardService.fetchSnapshot(forceRecalculate: forceRecalculate)
            apply(score: snapshot.today)
            weekScores = snapshot.weekScores
            isCalibrating = snapshot.isCalibrating
            calculateTrends()
        } catch {
            AppLog.error("TodayViewModel.refresh", error: error)
            if let healthError = error as? HealthKitError {
                switch healthError {
                case .noData:
                    noDataMessage = "No data yet. Wear Apple Watch and allow Health access."
                    errorMessage = nil
                    return
                case .noRecentWatchData:
                    noDataMessage = "Apple Watch metrics are not synced yet. Keep watch on wrist/unlocked, open Health once, then pull to refresh."
                    errorMessage = nil
                    return
                default:
                    break
                }
            }
            noDataMessage = nil
            errorMessage = AppErrorMapper.userMessage(for: error)
        }
    }

    private func apply(score: DailyScore) {
        stressScore = score.stressScore
        sleepScore = score.sleepScore
        bodyBatteryScore = score.bodyBatteryScore
        stressLevel = StressLevel(rawValue: score.stressLevel) ?? .low
        sleepLevel = SleepLevel(rawValue: score.sleepLevel) ?? .poor
        bodyBatteryLevel = BatteryLevel(rawValue: score.bodyBatteryLevel) ?? .low
        restingHeartRate = Int(score.restingHR.rounded())
        hrvValue = Int(score.avgSDNN.rounded())
        sleepDurationText = sleepDurationString(minutes: score.sleepDurationMin)
        activeCalories = Int(score.activeCalories.rounded())
        steps = score.steps
        insightText = score.insightText.isEmpty ? "Your body signals are stable today." : score.insightText
        lastUpdated = score.updatedAt
    }

    private func calculateTrends() {
        guard weekScores.count >= 4 else { return }

        let recent = Array(weekScores.suffix(3))
        let earlier = Array(weekScores.dropLast(3))

        restingHRTrend = makeTrend(
            recent: recent.map(\.restingHR),
            earlier: earlier.map(\.restingHR),
            invertBetter: true,
            format: { String(format: "%.0f bpm avg", $0) }
        )

        hrvTrend = makeTrend(
            recent: recent.map(\.avgSDNN),
            earlier: earlier.map(\.avgSDNN),
            invertBetter: false,
            format: { String(format: "%.0f ms avg", $0) }
        )

        sleepTrend = makeTrend(
            recent: recent.map { $0.sleepDurationMin / 60 },
            earlier: earlier.map { $0.sleepDurationMin / 60 },
            invertBetter: false,
            format: { String(format: "%.1fh avg", $0) }
        )

        batteryTrend = makeTrend(
            recent: recent.map(\.activeCalories),
            earlier: earlier.map(\.activeCalories),
            invertBetter: false,
            format: { String(format: "%.0f kcal avg", $0) }
        )
    }

    private func makeTrend(
        recent: [Double],
        earlier: [Double],
        invertBetter: Bool,
        format: (Double) -> String
    ) -> VitalTrend {
        guard let recentAvg = Statistics.mean(recent),
              let earlierAvg = Statistics.mean(earlier),
              earlierAvg > 0 else {
            return .neutral("--")
        }

        let change = (recentAvg - earlierAvg) / earlierAvg
        let label = format(recentAvg)

        if abs(change) < 0.02 {
            return .neutral(label)
        }

        let isUp = change > 0
        let isBetter = invertBetter ? !isUp : isUp
        return isBetter ? .up(label) : .down(label)
    }

    private func sleepDurationString(minutes: Double) -> String {
        guard minutes > 0 else { return "--" }
        let rounded = Int(minutes.rounded())
        let hours = rounded / 60
        let mins = rounded % 60
        return "\(hours)h \(mins)m"
    }
}
