import Foundation
import SwiftData

@MainActor
final class TrendsDataService {
    private let storage: StorageService

    init(context: ModelContext) {
        storage = StorageService(context: context)
    }

    func fetchHistory(for period: TrendPeriod) throws -> [DailyScore] {
        try storage.fetchDailyScores(days: period.rawValue)
    }
}
