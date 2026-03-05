import Foundation
import SwiftData

@Model
final class DailyScore {
    var date: Date

    var stressScore: Int
    var sleepScore: Int
    var energyScore: Int

    var stressLevel: String
    var sleepLevel: String
    var energyLevel: String

    var createdAt: Date
    var updatedAt: Date

    var sleepDurationMin: Double
    var sleepEfficiency: Double
    var deepSleepMin: Double
    var remSleepMin: Double
    var coreSleepMin: Double
    var bedtimeAt: Date?

    var avgSDNN: Double
    var restingHR: Double

    var activeCalories: Double
    var steps: Int
    var insightText: String

    init(
        date: Date,
        stressScore: Int = 0,
        sleepScore: Int = 0,
        energyScore: Int = 0,
        stressLevel: String = "unknown",
        sleepLevel: String = "unknown",
        energyLevel: String = "unknown",
        sleepDurationMin: Double = 0,
        sleepEfficiency: Double = 0,
        deepSleepMin: Double = 0,
        remSleepMin: Double = 0,
        coreSleepMin: Double = 0,
        bedtimeAt: Date? = nil,
        avgSDNN: Double = 0,
        restingHR: Double = 0,
        activeCalories: Double = 0,
        steps: Int = 0,
        insightText: String = ""
    ) {
        self.date = date.startOfDay
        self.stressScore = stressScore
        self.sleepScore = sleepScore
        self.energyScore = energyScore
        self.stressLevel = stressLevel
        self.sleepLevel = sleepLevel
        self.energyLevel = energyLevel
        self.createdAt = Date()
        self.updatedAt = Date()
        self.sleepDurationMin = sleepDurationMin
        self.sleepEfficiency = sleepEfficiency
        self.deepSleepMin = deepSleepMin
        self.remSleepMin = remSleepMin
        self.coreSleepMin = coreSleepMin
        self.bedtimeAt = bedtimeAt
        self.avgSDNN = avgSDNN
        self.restingHR = restingHR
        self.activeCalories = activeCalories
        self.steps = steps
        self.insightText = insightText
    }
}
