import Foundation
import SwiftData

@Model
final class EnergyReading {
    var timestamp: Date
    var level: Double
    var source: String

    init(timestamp: Date, level: Double, source: String) {
        self.timestamp = timestamp
        self.level = level
        self.source = source
    }
}

typealias BatteryReading = EnergyReading
