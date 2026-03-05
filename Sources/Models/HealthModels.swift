import Foundation

struct HRVSample: Sendable {
    let sdnn: Double
    let date: Date
}

struct SleepData: Sendable {
    var segments: [SleepSegment]
    var inBedStart: Date?
    var inBedEnd: Date?

    var totalSleepMinutes: Double
    var deepMinutes: Double
    var remMinutes: Double
    var coreMinutes: Double
    var awakeMinutes: Double
    var efficiency: Double
    var bedtime: Date?
}

struct SleepSegment: Sendable {
    let stage: SleepStage
    let start: Date
    let end: Date
}

enum SleepStage: String, Sendable {
    case deep
    case rem
    case core
    case awake
    case unspecified
}

enum BaselineMetric: String, CaseIterable, Sendable {
    case sdnn
    case restingHR
    case sleepDuration

    var populationDefault: Double {
        switch self {
        case .sdnn:
            40
        case .restingHR:
            65
        case .sleepDuration:
            7
        }
    }
}
