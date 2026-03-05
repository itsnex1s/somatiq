import Foundation
import SwiftData

@Model
final class UserBaseline {
    var metricName: String
    var median30Day: Double
    var updatedAt: Date
    var sampleCount: Int

    init(metricName: String, median30Day: Double, sampleCount: Int) {
        self.metricName = metricName
        self.median30Day = median30Day
        self.updatedAt = Date()
        self.sampleCount = sampleCount
    }
}
