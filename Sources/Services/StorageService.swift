import Foundation
import SwiftData

@MainActor
final class StorageService {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func upsertDailyScore(_ score: DailyScore) throws {
        if let existing = try fetchDailyScore(on: score.date) {
            existing.stressScore = score.stressScore
            existing.sleepScore = score.sleepScore
            existing.bodyBatteryScore = score.bodyBatteryScore
            existing.stressLevel = score.stressLevel
            existing.sleepLevel = score.sleepLevel
            existing.bodyBatteryLevel = score.bodyBatteryLevel
            existing.sleepDurationMin = score.sleepDurationMin
            existing.sleepEfficiency = score.sleepEfficiency
            existing.deepSleepMin = score.deepSleepMin
            existing.remSleepMin = score.remSleepMin
            existing.coreSleepMin = score.coreSleepMin
            existing.bedtimeAt = score.bedtimeAt
            existing.avgSDNN = score.avgSDNN
            existing.restingHR = score.restingHR
            existing.activeCalories = score.activeCalories
            existing.steps = score.steps
            existing.insightText = score.insightText
            existing.updatedAt = Date()
        } else {
            context.insert(score)
        }
        try context.save()
    }

    func fetchDailyScore(on date: Date) throws -> DailyScore? {
        let dayStart = date.startOfDay
        let descriptor = FetchDescriptor<DailyScore>(
            predicate: #Predicate { score in
                score.date == dayStart
            },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        return try context.fetch(descriptor).first
    }

    func fetchDailyScores(days: Int) throws -> [DailyScore] {
        let startDate = Date().adding(days: -max(days - 1, 0)).startOfDay
        let descriptor = FetchDescriptor<DailyScore>(
            predicate: #Predicate { score in
                score.date >= startDate
            },
            sortBy: [SortDescriptor(\.date, order: .forward)]
        )
        return try context.fetch(descriptor)
    }

    func fetchBedtimes(days: Int) throws -> [Date] {
        let scores = try fetchDailyScores(days: days)
        return scores.compactMap(\.bedtimeAt)
    }

    func saveBatteryReading(level: Double, source: String) throws {
        let reading = BatteryReading(
            timestamp: Date().startOfHour,
            level: Statistics.clamped(level, min: 0, max: 100),
            source: source
        )
        context.insert(reading)
        try context.save()
    }

    func latestBatteryReading() throws -> BatteryReading? {
        var descriptor = FetchDescriptor<BatteryReading>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    func fetchPreferences() throws -> UserPreferences {
        let descriptor = FetchDescriptor<UserPreferences>()
        if let existing = try context.fetch(descriptor).first {
            return existing
        }

        let defaults = UserPreferences()
        context.insert(defaults)
        try context.save()
        return defaults
    }

    func savePreferences(_ preferences: UserPreferences) throws {
        _ = preferences
        try context.save()
    }

    func markHealthSync(at date: Date = Date()) throws {
        let preferences = try fetchPreferences()
        preferences.lastSyncAt = date
        try context.save()
    }

    func baseline(for metric: BaselineMetric) throws -> UserBaseline? {
        let metricName = metric.rawValue
        let descriptor = FetchDescriptor<UserBaseline>(
            predicate: #Predicate { baseline in
                baseline.metricName == metricName
            }
        )
        return try context.fetch(descriptor).first
    }

    func upsertBaseline(metric: BaselineMetric, value: Double, sampleCount: Int) throws {
        if let existing = try baseline(for: metric) {
            existing.median30Day = value
            existing.sampleCount = sampleCount
            existing.updatedAt = Date()
        } else {
            let newBaseline = UserBaseline(metricName: metric.rawValue, median30Day: value, sampleCount: sampleCount)
            context.insert(newBaseline)
        }
        try context.save()
    }
}
