import Foundation
import HealthKit

protocol HealthDataProviding: Sendable {
    func requestAuthorization() async throws
    func queryHRV(last hours: Int) async throws -> [HRVSample]
    func queryRestingHR() async throws -> Double?
    func querySleep(for date: Date) async throws -> SleepData
    func queryActiveEnergy(for date: Date) async throws -> Double
    func querySteps(for date: Date) async throws -> Int
    func enableBackgroundDelivery() async throws
}

extension HealthDataProviding {
    func authorizeAndEnableBackgroundDelivery() async throws {
        try await requestAuthorization()
        try await enableBackgroundDelivery()
    }
}

enum HealthKitError: LocalizedError {
    case unavailable
    case unauthorized
    case noData
    case queryFailure

    var errorDescription: String? {
        switch self {
        case .unavailable:
            "Health data is unavailable on this device."
        case .unauthorized:
            "Health access is not authorized."
        case .noData:
            "No health data found yet."
        case .queryFailure:
            "Unable to query Apple Health."
        }
    }
}

/// Thread-safe service for HealthKit queries. HKHealthStore is documented as thread-safe.
final class HealthKitService: HealthDataProviding, @unchecked Sendable {
    private let store = HKHealthStore()

    private let readTypes: Set<HKObjectType> = [
        HKQuantityType(.heartRateVariabilitySDNN),
        HKQuantityType(.heartRate),
        HKQuantityType(.restingHeartRate),
        HKCategoryType(.sleepAnalysis),
        HKQuantityType(.activeEnergyBurned),
        HKQuantityType(.stepCount),
    ]

    func requestAuthorization() async throws {
        guard HKHealthStore.isHealthDataAvailable() else {
            throw HealthKitError.unavailable
        }
        try await store.requestAuthorization(toShare: [], read: readTypes)
    }

    func queryHRV(last hours: Int = 24) async throws -> [HRVSample] {
        let type = HKQuantityType(.heartRateVariabilitySDNN)
        let endDate = Date()
        let startDate = Calendar.current.date(byAdding: .hour, value: -max(hours, 1), to: endDate) ?? endDate.addingTimeInterval(-86_400)
        let samples = try await queryQuantitySamples(
            type: type,
            unit: HKUnit.secondUnit(with: .milli),
            from: startDate,
            to: endDate,
            limit: HKObjectQueryNoLimit
        )

        return samples.map { HRVSample(sdnn: $0.value, date: $0.date) }
    }

    func queryRestingHR() async throws -> Double? {
        let type = HKQuantityType(.restingHeartRate)
        let endDate = Date()
        let startDate = Calendar.current.date(byAdding: .day, value: -7, to: endDate) ?? endDate.addingTimeInterval(-604_800)
        let samples = try await queryQuantitySamples(
            type: type,
            unit: HKUnit.count().unitDivided(by: .minute()),
            from: startDate,
            to: endDate,
            limit: 1
        )
        return samples.first?.value
    }

    func querySleep(for date: Date) async throws -> SleepData {
        let type = HKCategoryType(.sleepAnalysis)
        let startDate = Calendar.current.date(byAdding: .day, value: -1, to: date.startOfDay) ?? date.startOfDay
        let endDate = Calendar.current.date(byAdding: .day, value: 1, to: date.startOfDay) ?? date
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate)
        let sort = [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]

        let samples: [HKCategorySample] = try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: type,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: sort
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let categorySamples = (samples as? [HKCategorySample]) ?? []
                continuation.resume(returning: categorySamples)
            }
            store.execute(query)
        }

        var segments: [SleepSegment] = []
        var inBedStart: Date?
        var inBedEnd: Date?
        var deepMinutes: Double = 0
        var remMinutes: Double = 0
        var coreMinutes: Double = 0
        var awakeMinutes: Double = 0
        var totalSleepMinutes: Double = 0
        var bedtime: Date?

        for sample in samples {
            let duration = sample.endDate.timeIntervalSince(sample.startDate) / 60
            let stage = mapSleepStage(sample.value)

            if sample.value == HKCategoryValueSleepAnalysis.inBed.rawValue {
                if inBedStart == nil || sample.startDate < inBedStart! {
                    inBedStart = sample.startDate
                }
                if inBedEnd == nil || sample.endDate > inBedEnd! {
                    inBedEnd = sample.endDate
                }
            } else {
                segments.append(SleepSegment(stage: stage, start: sample.startDate, end: sample.endDate))
            }

            switch stage {
            case .deep:
                deepMinutes += duration
                totalSleepMinutes += duration
            case .rem:
                remMinutes += duration
                totalSleepMinutes += duration
            case .core, .unspecified:
                coreMinutes += duration
                totalSleepMinutes += duration
            case .awake:
                awakeMinutes += duration
            }
        }

        bedtime = segments.first(where: { $0.stage != .awake })?.start
        let inBedMinutes: Double
        if let inBedStart, let inBedEnd {
            inBedMinutes = max(1, inBedEnd.timeIntervalSince(inBedStart) / 60)
        } else {
            inBedMinutes = max(1, totalSleepMinutes + awakeMinutes)
        }

        let efficiency = Statistics.clamped(totalSleepMinutes / inBedMinutes, min: 0, max: 1)
        return SleepData(
            segments: segments,
            inBedStart: inBedStart,
            inBedEnd: inBedEnd,
            totalSleepMinutes: totalSleepMinutes,
            deepMinutes: deepMinutes,
            remMinutes: remMinutes,
            coreMinutes: coreMinutes,
            awakeMinutes: awakeMinutes,
            efficiency: efficiency,
            bedtime: bedtime
        )
    }

    func queryActiveEnergy(for date: Date) async throws -> Double {
        try await queryDailySum(
            type: HKQuantityType(.activeEnergyBurned),
            unit: .kilocalorie(),
            for: date
        )
    }

    func querySteps(for date: Date) async throws -> Int {
        let value = try await queryDailySum(
            type: HKQuantityType(.stepCount),
            unit: .count(),
            for: date
        )
        return Int(value.rounded())
    }

    func enableBackgroundDelivery() async throws {
        let types = [
            HKQuantityType(.heartRateVariabilitySDNN),
            HKCategoryType(.sleepAnalysis),
            HKQuantityType(.activeEnergyBurned),
        ]

        for type in types {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                store.enableBackgroundDelivery(for: type, frequency: .hourly) { success, error in
                    if let error {
                        continuation.resume(throwing: error)
                        return
                    }
                    if success {
                        continuation.resume(returning: ())
                    } else {
                        continuation.resume(throwing: HealthKitError.queryFailure)
                    }
                }
            }
        }
    }

    private func queryQuantitySamples(
        type: HKQuantityType,
        unit: HKUnit,
        from startDate: Date,
        to endDate: Date,
        limit: Int
    ) async throws -> [(value: Double, date: Date)] {
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate)
        let sort = [NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)]

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: type,
                predicate: predicate,
                limit: limit,
                sortDescriptors: sort
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                let quantitySamples = (samples as? [HKQuantitySample]) ?? []
                let mapped = quantitySamples.map {
                    (value: $0.quantity.doubleValue(for: unit), date: $0.endDate)
                }
                continuation.resume(returning: mapped)
            }
            store.execute(query)
        }
    }

    private func queryDailySum(type: HKQuantityType, unit: HKUnit, for date: Date) async throws -> Double {
        let start = date.startOfDay
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start) ?? date
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: type,
                quantitySamplePredicate: predicate,
                options: [.cumulativeSum]
            ) { _, statistics, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                let value = statistics?.sumQuantity()?.doubleValue(for: unit) ?? 0
                continuation.resume(returning: value)
            }
            store.execute(query)
        }
    }

    private func mapSleepStage(_ value: Int) -> SleepStage {
        switch value {
        case HKCategoryValueSleepAnalysis.asleepDeep.rawValue:
            return .deep
        case HKCategoryValueSleepAnalysis.asleepREM.rawValue:
            return .rem
        case HKCategoryValueSleepAnalysis.asleepCore.rawValue:
            return .core
        case HKCategoryValueSleepAnalysis.awake.rawValue:
            return .awake
        case HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue:
            return .unspecified
        default:
            return .unspecified
        }
    }
}
