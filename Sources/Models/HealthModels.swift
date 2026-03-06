import Foundation

struct HRVSample: Sendable {
    let value: Double
    let date: Date
    let sourceRank: Int
    let algorithmVersion: String?
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
    var stageCoverage: Double
    var sourcePurity: Double
    var interruptionsCount: Int
}

struct SleepSegment: Sendable {
    let stage: SleepStage
    let start: Date
    let end: Date
    let sourceRank: Int
}

enum SleepStage: String, Sendable {
    case deep
    case rem
    case core
    case awake
    case unspecified
}

struct RestWindowSample: Sendable {
    let timestamp: Date
    let heartRate: Double
    let lnHRV: Double?
    let sourceRank: Int
}

struct DailyHealthInput: Sendable {
    let sleep: SleepData
    let nightSDNNSamples: [HRVSample]
    let nightRMSDDSamples: [HRVSample]
    let nightHeartRateBins: [Double]
    let restWindows: [RestWindowSample]
    let activeEnergy: Double
    let steps: Int
    let workoutMinutes: Double
    let dayWatchWearCoverage: Double
    let nightHRCoverage: Double
    let sourcePurity: Double
    let qualityNotes: [String]
}

enum BaselineMetric: String, CaseIterable, Sendable {
    case sdnn
    case restingHR
    case sleepDuration

    var populationDefault: Double {
        switch self {
        case .sdnn: return 35
        case .restingHR: return 62
        case .sleepDuration: return 7
        }
    }
}
