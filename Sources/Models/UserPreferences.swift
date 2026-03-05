import Foundation
import SwiftData

@Model
final class UserPreferences {
    var name: String
    var targetSleepHours: Double
    var birthYear: Int?
    var lastSyncAt: Date?

    init(
        name: String = "",
        targetSleepHours: Double = 8,
        birthYear: Int? = nil,
        lastSyncAt: Date? = nil
    ) {
        self.name = name
        self.targetSleepHours = targetSleepHours
        self.birthYear = birthYear
        self.lastSyncAt = lastSyncAt
    }
}
