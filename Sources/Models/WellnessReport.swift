import Foundation
import SwiftData

@Model
final class WellnessReport {
    var id: UUID
    var createdAt: Date
    var day: Date
    var triggerType: String
    var headline: String
    var body: String
    var stressScore: Int
    var sleepScore: Int
    var bodyBatteryScore: Int
    var heartScore: Int
    var source: String

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        triggerType: String,
        headline: String,
        body: String,
        stressScore: Int,
        sleepScore: Int,
        bodyBatteryScore: Int,
        heartScore: Int,
        source: String
    ) {
        self.id = id
        self.createdAt = createdAt
        day = createdAt.startOfDay
        self.triggerType = triggerType
        self.headline = headline
        self.body = body
        self.stressScore = stressScore
        self.sleepScore = sleepScore
        self.bodyBatteryScore = bodyBatteryScore
        self.heartScore = heartScore
        self.source = source
    }
}
