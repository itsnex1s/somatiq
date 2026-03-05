import Foundation

@MainActor
final class BaselineService {
    private let storage: StorageService

    init(storage: StorageService) {
        self.storage = storage
    }

    func baselineValue(for metric: BaselineMetric) throws -> Double {
        if let baseline = try storage.baseline(for: metric), baseline.sampleCount > 0 {
            return baseline.median30Day
        }
        return metric.populationDefault
    }

    func recalculateBaselines() throws {
        let scores = try storage.fetchDailyScores(days: 30)

        for metric in BaselineMetric.allCases {
            let values = metricValues(metric, scores: scores)
            guard let personalMedian = Statistics.median(values) else { continue }
            let blended = Self.blendedBaseline(
                personal: personalMedian,
                population: metric.populationDefault,
                dayCount: values.count
            )
            try storage.upsertBaseline(metric: metric, value: blended, sampleCount: values.count)
        }
    }

    nonisolated static func blendedBaseline(personal: Double, population: Double, dayCount: Int) -> Double {
        let weight = min(max(Double(dayCount) / 30, 0), 1)
        return (personal * weight) + (population * (1 - weight))
    }

    private func metricValues(_ metric: BaselineMetric, scores: [DailyScore]) -> [Double] {
        switch metric {
        case .sdnn:
            return scores.map(\.avgSDNN).filter { $0 > 0 }
        case .restingHR:
            return scores.map(\.restingHR).filter { $0 > 0 }
        case .sleepDuration:
            return scores.map { $0.sleepDurationMin / 60 }.filter { $0 > 0 }
        }
    }
}
