import Foundation
import Observation

enum TrendPeriod: Int, CaseIterable, Identifiable {
    case days7 = 7
    case days30 = 30
    case days90 = 90

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .days7:
            "7D"
        case .days30:
            "30D"
        case .days90:
            "90D"
        }
    }
}

@MainActor
@Observable
final class TrendsViewModel {
    var selectedPeriod: TrendPeriod = .days30
    var history: [DailyScore] = []
    var isLoading = false
    var errorMessage: String?
    var hasInsufficientData = false

    private let trendsService: TrendsDataService

    init(trendsService: TrendsDataService) {
        self.trendsService = trendsService
    }

    func load() {
        isLoading = true
        defer { isLoading = false }

        do {
            errorMessage = nil
            let rawHistory = try trendsService.fetchHistory(for: selectedPeriod)
            history = rawHistory.filter { score in
                if let confidence = score.scoreConfidence, confidence < 0.55 {
                    return false
                }
                return (score.avgSDNN > 0 && score.restingHR > 0) ||
                    score.sleepDurationMin > 0 ||
                    score.activeCalories > 0 ||
                    score.steps > 0
            }
            hasInsufficientData = history.count < 3
        } catch {
            AppLog.error("TrendsViewModel.load", error: error)
            errorMessage = AppErrorMapper.userMessage(for: error)
            history = []
            hasInsufficientData = true
        }
    }

    func updatePeriod(_ period: TrendPeriod) {
        guard selectedPeriod != period else { return }
        selectedPeriod = period
        load()
    }

    var averageStress: Int {
        let values = history.map { Double($0.stressScore) }
        return Int((Statistics.mean(values) ?? 0).rounded())
    }

    var averageSleep: Int {
        let values = history.map { Double($0.sleepScore) }
        return Int((Statistics.mean(values) ?? 0).rounded())
    }

    var averageBodyBattery: Int {
        let values = history.map { Double($0.bodyBatteryScore) }
        return Int((Statistics.mean(values) ?? 0).rounded())
    }
}
