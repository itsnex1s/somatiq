import Foundation
import HealthKit

protocol HealthDataProviding: Sendable {
    func requestAuthorization() async throws
    func queryDailyInput(for date: Date) async throws -> DailyHealthInput
    func enableBackgroundDelivery() async throws
}

extension HealthDataProviding {
    func authorizeAndEnableBackgroundDelivery() async throws {
        try await requestAuthorization()
        do {
            try await enableBackgroundDelivery()
        } catch {
            AppLog.error("HealthDataProviding.authorizeAndEnableBackgroundDelivery", error: error)
        }
    }
}

enum HealthKitError: LocalizedError {
    case unavailable
    case unauthorized
    case noData
    case noRecentWatchData
    case queryFailure

    var errorDescription: String? {
        switch self {
        case .unavailable:
            "Health data is unavailable on this device."
        case .unauthorized:
            "Health access is not authorized."
        case .noData:
            "No health data found yet."
        case .noRecentWatchData:
            "No recent Apple Watch metrics are available yet."
        case .queryFailure:
            "Unable to query Apple Health."
        }
    }
}

final class HealthKitService: HealthDataProviding, @unchecked Sendable {
    private struct QuantitySampleRecord {
        let start: Date
        let end: Date
        let value: Double
        let sourceRank: Int
    }

    private struct RankedHeartRateSample {
        let timestamp: Date
        let bpm: Double
        let sourceRank: Int
        let motionContext: HKHeartRateMotionContext?
    }

    private struct TimeRange {
        let start: Date
        let end: Date

        func overlaps(start: Date, end: Date) -> Bool {
            start < self.end && end > self.start
        }

        func contains(_ date: Date) -> Bool {
            date >= start && date <= end
        }
    }

    private let store = HKHealthStore()
    private let calendar = Calendar.current
    private let readTypes: Set<HKObjectType> = [
        HKQuantityType(.heartRateVariabilitySDNN),
        HKQuantityType(.heartRate),
        HKQuantityType(.restingHeartRate),
        HKCategoryType(.sleepAnalysis),
        HKQuantityType(.activeEnergyBurned),
        HKQuantityType(.stepCount),
        HKObjectType.workoutType(),
        HKSeriesType.heartbeat(),
    ]

    func requestAuthorization() async throws {
        guard HKHealthStore.isHealthDataAvailable() else {
            throw HealthKitError.unavailable
        }
        try await store.requestAuthorization(toShare: [], read: readTypes)
    }

    func queryDailyInput(for date: Date) async throws -> DailyHealthInput {
        let dayStart = date.startOfDay
        let dayEnd = min(Date(), dayStart.addingTimeInterval(86_400))

        let sleep = try await queryMainSleep(for: dayStart)
        let defaultNightStart = calendar.date(byAdding: .hour, value: -8, to: dayEnd) ?? dayStart
        let nightStart = sleep.inBedStart ?? sleep.bedtime ?? defaultNightStart
        let nightEnd = sleep.inBedEnd ?? dayEnd

        let nightSDNNSamples = try await queryHRVSamples(from: nightStart, to: nightEnd)
        let nightRMSDDSamples = try await queryRMSDDSamples(from: nightStart, to: nightEnd)
        let nightHeartRateSamples = try await queryHeartRateSamples(from: nightStart, to: nightEnd)
        let nightHeartRateBins = makeHeartRateBins(from: nightHeartRateSamples)
        let nightExpectedBins = max(Int(nightEnd.timeIntervalSince(nightStart) / 300), 1)
        let nightHRCoverage = Statistics.clamped(
            Double(nightHeartRateBins.count) / Double(nightExpectedBins),
            min: 0,
            max: 1
        )

        let workouts = try await queryWorkouts(from: dayStart, to: dayEnd)
        let dayHeartRateSamples = try await queryHeartRateSamples(from: dayStart, to: dayEnd)
        let dayHRVSamples = try await queryHRVSamples(from: dayStart, to: dayEnd)

        let stepSamples = try await queryCumulativeSamples(
            type: HKQuantityType(.stepCount),
            unit: .count(),
            from: dayStart,
            to: dayEnd
        )
        let activeEnergySamples = try await queryCumulativeSamples(
            type: HKQuantityType(.activeEnergyBurned),
            unit: .kilocalorie(),
            from: dayStart,
            to: dayEnd
        )

        let restWindows = buildRestWindows(
            dayHeartRateSamples: dayHeartRateSamples,
            dayHRVSamples: dayHRVSamples,
            workouts: workouts,
            stepSamples: stepSamples,
            activeEnergySamples: activeEnergySamples
        )

        let activeEnergy = resolveCumulativeTotal(from: activeEnergySamples)
        let steps = Int(resolveCumulativeTotal(from: stepSamples).rounded())
        let workoutMinutes = workouts.reduce(0) { partial, workout in
            partial + max(workout.end.timeIntervalSince(workout.start), 0) / 60
        }

        let wakeReference = max(sleep.inBedEnd ?? dayStart, dayStart)
        let watchHeartRateBins = Set(
            dayHeartRateSamples
                .filter { $0.sourceRank == 3 }
                .map { startOfFiveMinuteBucket(for: $0.timestamp) }
        )
        let expectedAwakeBins = max(Int(dayEnd.timeIntervalSince(wakeReference) / 300), 1)
        let dayWatchWearCoverage = Statistics.clamped(
            Double(watchHeartRateBins.count) / Double(expectedAwakeBins),
            min: 0,
            max: 1
        )

        let sourcePurity = resolveSourcePurity(
            nightHRV: nightSDNNSamples,
            nightHeartRate: nightHeartRateSamples,
            restWindows: restWindows,
            sleep: sleep
        )

        var qualityNotes: [String] = []
        if nightSDNNSamples.isEmpty {
            qualityNotes.append("insufficient_hrv_samples")
        }
        if nightHeartRateBins.isEmpty {
            qualityNotes.append("insufficient_hr_samples")
        }
        if sleep.totalSleepMinutes <= 0 {
            qualityNotes.append("insufficient_sleep_duration")
            qualityNotes.append("no_watch_sleep_data")
        }
        if restWindows.count < 3 {
            qualityNotes.append("insufficient_rest_windows")
        }
        if sleep.stageCoverage < 0.5 {
            qualityNotes.append("low_stage_coverage")
        }
        if dayWatchWearCoverage < 0.5 {
            qualityNotes.append("low_daytime_wear")
        }

        return DailyHealthInput(
            sleep: sleep,
            nightSDNNSamples: nightSDNNSamples,
            nightRMSDDSamples: nightRMSDDSamples,
            nightHeartRateBins: nightHeartRateBins,
            restWindows: restWindows,
            activeEnergy: activeEnergy,
            steps: max(steps, 0),
            workoutMinutes: workoutMinutes,
            dayWatchWearCoverage: dayWatchWearCoverage,
            nightHRCoverage: nightHRCoverage,
            sourcePurity: sourcePurity,
            qualityNotes: qualityNotes
        )
    }

    func enableBackgroundDelivery() async throws {
        let types = [
            HKQuantityType(.heartRateVariabilitySDNN),
            HKCategoryType(.sleepAnalysis),
            HKQuantityType(.activeEnergyBurned),
            HKQuantityType(.heartRate),
        ]

        var enabledAny = false
        for type in types {
            do {
                let success: Bool = try await withCheckedThrowingContinuation { continuation in
                    store.enableBackgroundDelivery(for: type, frequency: .hourly) { success, error in
                        if let error {
                            continuation.resume(throwing: error)
                            return
                        }
                        continuation.resume(returning: success)
                    }
                }
                enabledAny = enabledAny || success
            } catch {
                AppLog.error("HealthKitService.enableBackgroundDelivery.\(type.identifier)", error: error)
            }
        }

        if !enabledAny {
            throw HealthKitError.queryFailure
        }
    }

    private func queryMainSleep(for dayStart: Date) async throws -> SleepData {
        let searchStart = calendar.date(byAdding: .hour, value: -9, to: dayStart) ?? dayStart.addingTimeInterval(-32_400)
        let searchEnd = calendar.date(byAdding: .hour, value: 15, to: dayStart) ?? dayStart.addingTimeInterval(54_000)
        let sleepType = HKCategoryType(.sleepAnalysis)
        let predicate = HKQuery.predicateForSamples(withStart: searchStart, end: searchEnd)
        let sort = [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]

        let samples: [HKCategorySample] = try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: sleepType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: sort
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(returning: (samples as? [HKCategorySample]) ?? [])
            }
            store.execute(query)
        }

        let asleepValues: Set<Int> = [
            HKCategoryValueSleepAnalysis.asleepCore.rawValue,
            HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
            HKCategoryValueSleepAnalysis.asleepREM.rawValue,
            HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
        ]

        let asleepSamples = samples
            .filter { asleepValues.contains($0.value) }
            .sorted { $0.startDate < $1.startDate }
        let watchAsleepSamples = asleepSamples.filter { sourceRank(for: $0) == 3 }

        guard !watchAsleepSamples.isEmpty else {
            return emptySleepData()
        }

        let mergeGap: TimeInterval = 20 * 60
        var episodes: [TimeRange] = []
        var currentStart = watchAsleepSamples[0].startDate
        var currentEnd = watchAsleepSamples[0].endDate

        for sample in watchAsleepSamples.dropFirst() {
            if sample.startDate.timeIntervalSince(currentEnd) <= mergeGap {
                currentEnd = max(currentEnd, sample.endDate)
            } else {
                episodes.append(TimeRange(start: currentStart, end: currentEnd))
                currentStart = sample.startDate
                currentEnd = sample.endDate
            }
        }
        episodes.append(TimeRange(start: currentStart, end: currentEnd))

        let mainEpisode = episodes.max { lhs, rhs in
            lhs.end.timeIntervalSince(lhs.start) < rhs.end.timeIntervalSince(rhs.start)
        } ?? TimeRange(start: currentStart, end: currentEnd)

        let episodeSamples = samples.filter { sample in
            sample.startDate < mainEpisode.end &&
                sample.endDate > mainEpisode.start &&
                sourceRank(for: sample) == 3
        }

        var segments: [SleepSegment] = []
        var inBedStart: Date?
        var inBedEnd: Date?
        var deepMinutes = 0.0
        var remMinutes = 0.0
        var coreMinutes = 0.0
        var unspecifiedMinutes = 0.0
        var awakeMinutes = 0.0
        var interruptionsCount = 0
        var rankWeights: [Double] = []

        for sample in episodeSamples {
            let overlapStart = max(sample.startDate, mainEpisode.start)
            let overlapEnd = min(sample.endDate, mainEpisode.end)
            let durationMinutes = max(overlapEnd.timeIntervalSince(overlapStart) / 60, 0)
            guard durationMinutes > 0 else { continue }

            let stage = mapSleepStage(sample.value)
            let rank = sourceRank(for: sample)

            if sample.value == HKCategoryValueSleepAnalysis.inBed.rawValue {
                inBedStart = min(inBedStart ?? overlapStart, overlapStart)
                inBedEnd = max(inBedEnd ?? overlapEnd, overlapEnd)
                continue
            }

            segments.append(
                SleepSegment(
                    stage: stage,
                    start: overlapStart,
                    end: overlapEnd,
                    sourceRank: rank
                )
            )
            rankWeights.append(Double(rank) / 3)

            switch stage {
            case .deep:
                deepMinutes += durationMinutes
            case .rem:
                remMinutes += durationMinutes
            case .core:
                coreMinutes += durationMinutes
            case .unspecified:
                unspecifiedMinutes += durationMinutes
            case .awake:
                awakeMinutes += durationMinutes
                if durationMinutes >= 5 {
                    interruptionsCount += 1
                }
            }
        }

        let totalSleepMinutes = deepMinutes + remMinutes + coreMinutes + unspecifiedMinutes
        let resolvedInBedStart = inBedStart ?? mainEpisode.start
        let resolvedInBedEnd = inBedEnd ?? mainEpisode.end
        let inBedMinutes = max(resolvedInBedEnd.timeIntervalSince(resolvedInBedStart) / 60, 1)
        let efficiency = Statistics.clamped(totalSleepMinutes / inBedMinutes, min: 0, max: 1)
        let stageCoverage = Statistics.clamped(
            (deepMinutes + remMinutes + coreMinutes) / max(totalSleepMinutes, 1),
            min: 0,
            max: 1
        )
        let sourcePurity = rankWeights.isEmpty ? 0 : (Statistics.mean(rankWeights) ?? 0)
        let bedtime = segments.first(where: { $0.stage != .awake })?.start

        return SleepData(
            segments: segments.sorted { $0.start < $1.start },
            inBedStart: resolvedInBedStart,
            inBedEnd: resolvedInBedEnd,
            totalSleepMinutes: totalSleepMinutes,
            deepMinutes: deepMinutes,
            remMinutes: remMinutes,
            coreMinutes: coreMinutes,
            awakeMinutes: awakeMinutes,
            efficiency: efficiency,
            bedtime: bedtime,
            stageCoverage: stageCoverage,
            sourcePurity: sourcePurity,
            interruptionsCount: interruptionsCount
        )
    }

    private func queryHRVSamples(from startDate: Date, to endDate: Date) async throws -> [HRVSample] {
        let samples = try await queryQuantitySamples(
            type: HKQuantityType(.heartRateVariabilitySDNN),
            from: startDate,
            to: endDate,
            unit: HKUnit.secondUnit(with: .milli)
        )

        return samples.compactMap { sample in
            guard !isUserEntered(sample),
                  sample.quantity.doubleValue(for: HKUnit.secondUnit(with: .milli)) >= 5,
                  sample.quantity.doubleValue(for: HKUnit.secondUnit(with: .milli)) <= 300
            else {
                return nil
            }

            return HRVSample(
                value: sample.quantity.doubleValue(for: HKUnit.secondUnit(with: .milli)),
                date: sample.endDate,
                sourceRank: sourceRank(for: sample),
                algorithmVersion: sample.metadata?[HKMetadataKeyAlgorithmVersion] as? String
            )
        }
    }

    private func queryRMSDDSamples(from startDate: Date, to endDate: Date) async throws -> [HRVSample] {
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate)
        let sort = [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]

        let seriesSamples: [HKHeartbeatSeriesSample] = try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: HKSeriesType.heartbeat(),
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: sort
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(returning: (samples as? [HKHeartbeatSeriesSample]) ?? [])
            }
            store.execute(query)
        }

        var results: [HRVSample] = []
        for sample in seriesSamples {
            guard !isUserEntered(sample) else { continue }
            guard let rmssd = try await computeRMSSD(for: sample), (5 ... 300).contains(rmssd) else {
                continue
            }
            results.append(
                HRVSample(
                    value: rmssd,
                    date: sample.endDate,
                    sourceRank: sourceRank(for: sample),
                    algorithmVersion: sample.metadata?[HKMetadataKeyAlgorithmVersion] as? String
                )
            )
        }
        return results
    }

    private func computeRMSSD(for sample: HKHeartbeatSeriesSample) async throws -> Double? {
        try await withCheckedThrowingContinuation { continuation in
            var rrIntervals: [Double] = []
            var previousBeat: TimeInterval?
            var hasResumed = false

            let query = HKHeartbeatSeriesQuery(heartbeatSeries: sample) { [self] _, timeSinceSeriesStart, precededByGap, done, error in
                if let error, !hasResumed {
                    hasResumed = true
                    continuation.resume(throwing: error)
                    return
                }

                if done {
                    if !hasResumed {
                        hasResumed = true
                        continuation.resume(returning: self.rmssd(from: rrIntervals))
                    }
                    return
                }

                if let previousBeat, !precededByGap {
                    let interval = timeSinceSeriesStart - previousBeat
                    if interval >= 0.25, interval <= 2.5 {
                        rrIntervals.append(interval)
                    }
                }
                previousBeat = timeSinceSeriesStart
            }
            store.execute(query)
        }
    }

    private func rmssd(from rrIntervals: [Double]) -> Double? {
        guard rrIntervals.count >= 2 else { return nil }
        var squaredDiffs: [Double] = []
        squaredDiffs.reserveCapacity(rrIntervals.count - 1)

        for idx in 1..<rrIntervals.count {
            let diff = rrIntervals[idx] - rrIntervals[idx - 1]
            squaredDiffs.append(diff * diff)
        }

        guard let meanSquared = Statistics.mean(squaredDiffs) else { return nil }
        return sqrt(meanSquared) * 1_000
    }

    private func queryHeartRateSamples(from startDate: Date, to endDate: Date) async throws -> [RankedHeartRateSample] {
        let samples = try await queryQuantitySamples(
            type: HKQuantityType(.heartRate),
            from: startDate,
            to: endDate,
            unit: HKUnit.count().unitDivided(by: .minute())
        )

        return samples.compactMap { sample in
            guard !isUserEntered(sample) else { return nil }
            let bpm = sample.quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
            guard bpm >= 25, bpm <= 230 else { return nil }

            let motionContextRaw = sample.metadata?[HKMetadataKeyHeartRateMotionContext] as? Int
            let motionContext = motionContextRaw.flatMap(HKHeartRateMotionContext.init(rawValue:))

            return RankedHeartRateSample(
                timestamp: sample.endDate,
                bpm: bpm,
                sourceRank: sourceRank(for: sample),
                motionContext: motionContext
            )
        }
    }

    private func queryWorkouts(from startDate: Date, to endDate: Date) async throws -> [TimeRange] {
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate)
        let sort = [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]

        let workouts: [HKWorkout] = try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: HKObjectType.workoutType(),
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: sort
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(returning: (samples as? [HKWorkout]) ?? [])
            }
            store.execute(query)
        }

        return workouts.map { workout in
            TimeRange(start: workout.startDate, end: workout.endDate)
        }
    }

    private func queryQuantitySamples(
        type: HKQuantityType,
        from startDate: Date,
        to endDate: Date,
        unit: HKUnit
    ) async throws -> [HKQuantitySample] {
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate)
        let sort = [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]

        return try await withCheckedThrowingContinuation { continuation in
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

                let quantitySamples = (samples as? [HKQuantitySample]) ?? []
                let filtered = quantitySamples.filter { sample in
                    sample.quantity.doubleValue(for: unit).isFinite
                }
                continuation.resume(returning: filtered)
            }
            store.execute(query)
        }
    }

    private func queryCumulativeSamples(
        type: HKQuantityType,
        unit: HKUnit,
        from startDate: Date,
        to endDate: Date
    ) async throws -> [QuantitySampleRecord] {
        let samples = try await queryQuantitySamples(
            type: type,
            from: startDate,
            to: endDate,
            unit: unit
        )

        return samples.compactMap { sample in
            guard !isUserEntered(sample) else { return nil }
            let value = sample.quantity.doubleValue(for: unit)
            guard value.isFinite, value > 0 else { return nil }

            return QuantitySampleRecord(
                start: sample.startDate,
                end: sample.endDate,
                value: value,
                sourceRank: sourceRank(for: sample)
            )
        }
    }

    private func buildRestWindows(
        dayHeartRateSamples: [RankedHeartRateSample],
        dayHRVSamples: [HRVSample],
        workouts: [TimeRange],
        stepSamples: [QuantitySampleRecord],
        activeEnergySamples: [QuantitySampleRecord]
    ) -> [RestWindowSample] {
        let groupedByBucket = Dictionary(grouping: dayHeartRateSamples) { sample in
            startOfFiveMinuteBucket(for: sample.timestamp)
        }

        let sortedBuckets = groupedByBucket.keys.sorted()
        var windows: [RestWindowSample] = []

        for bucketStart in sortedBuckets {
            guard let candidates = groupedByBucket[bucketStart], !candidates.isEmpty else { continue }
            let bucketEnd = bucketStart.addingTimeInterval(300)
            if hasWorkoutConflict(bucketStart: bucketStart, workouts: workouts) {
                continue
            }

            let highestRank = candidates.map(\.sourceRank).max() ?? 0
            let ranked = candidates.filter { $0.sourceRank == highestRank }
            let bpm = Statistics.median(ranked.map(\.bpm)) ?? ranked[0].bpm

            let hasSedentaryContext = ranked.contains(where: { $0.motionContext == .sedentary })
            let hasActiveContext = ranked.contains(where: { $0.motionContext == .active })
            let priorSteps = cumulativeValue(
                from: stepSamples,
                in: bucketStart.addingTimeInterval(-300) ..< bucketStart
            )
            let priorEnergy = cumulativeValue(
                from: activeEnergySamples,
                in: bucketStart.addingTimeInterval(-300) ..< bucketStart
            )
            let fallbackResting = priorSteps <= 20 && priorEnergy <= 2

            if hasActiveContext {
                continue
            }
            if !hasSedentaryContext, !fallbackResting {
                continue
            }

            let nearbyHRV = nearestHRVSample(
                around: bucketStart.addingTimeInterval(150),
                samples: dayHRVSamples
            )
            let lnHRV = nearbyHRV.map { log(max($0.value, 1)) }

            windows.append(
                RestWindowSample(
                    timestamp: bucketEnd,
                    heartRate: bpm,
                    lnHRV: lnHRV,
                    sourceRank: highestRank
                )
            )
        }

        return windows
    }

    private func makeHeartRateBins(from samples: [RankedHeartRateSample]) -> [Double] {
        let groupedByBucket = Dictionary(grouping: samples) { sample in
            startOfFiveMinuteBucket(for: sample.timestamp)
        }

        return groupedByBucket.keys.sorted().compactMap { bucket in
            guard let bucketSamples = groupedByBucket[bucket], !bucketSamples.isEmpty else { return nil }
            let highestRank = bucketSamples.map(\.sourceRank).max() ?? 0
            let selected = bucketSamples.filter { $0.sourceRank == highestRank }
            return Statistics.median(selected.map(\.bpm)) ?? selected[0].bpm
        }
    }

    private func resolveCumulativeTotal(from samples: [QuantitySampleRecord]) -> Double {
        guard !samples.isEmpty else { return 0 }

        let watchSamples = samples.filter { $0.sourceRank == 3 }
        if !watchSamples.isEmpty {
            return watchSamples.reduce(0) { $0 + $1.value }
        }

        let highestRank = samples.map(\.sourceRank).max() ?? 0
        return samples
            .filter { $0.sourceRank == highestRank }
            .reduce(0) { $0 + $1.value }
    }

    private func resolveSourcePurity(
        nightHRV: [HRVSample],
        nightHeartRate: [RankedHeartRateSample],
        restWindows: [RestWindowSample],
        sleep: SleepData
    ) -> Double {
        let hrvPurity = nightHRV.map { Double($0.sourceRank) / 3 }
        let hrPurity = nightHeartRate.map { Double($0.sourceRank) / 3 }
        let restPurity = restWindows.map { Double($0.sourceRank) / 3 }
        let merged = hrvPurity + hrPurity + restPurity
        let base = Statistics.mean(merged) ?? 0
        return Statistics.clamped((base + sleep.sourcePurity) / 2, min: 0, max: 1)
    }

    private func nearestHRVSample(around timestamp: Date, samples: [HRVSample]) -> HRVSample? {
        let maxDistance: TimeInterval = 10 * 60
        let filtered = samples.filter { abs($0.date.timeIntervalSince(timestamp)) <= maxDistance }
        guard !filtered.isEmpty else { return nil }

        return filtered.sorted { lhs, rhs in
            if lhs.sourceRank != rhs.sourceRank {
                return lhs.sourceRank > rhs.sourceRank
            }
            return abs(lhs.date.timeIntervalSince(timestamp)) < abs(rhs.date.timeIntervalSince(timestamp))
        }.first
    }

    private func cumulativeValue(from samples: [QuantitySampleRecord], in interval: Range<Date>) -> Double {
        let overlapping = samples.filter { sample in
            sample.start < interval.upperBound && sample.end > interval.lowerBound
        }
        guard !overlapping.isEmpty else { return 0 }

        let highestRank = (overlapping.map(\.sourceRank).contains(3) ? 3 : (overlapping.map(\.sourceRank).max() ?? 0))
        let selected = overlapping.filter { $0.sourceRank == highestRank }

        return selected.reduce(0) { partial, sample in
            let overlapStart = max(sample.start, interval.lowerBound)
            let overlapEnd = min(sample.end, interval.upperBound)
            let overlapDuration = max(overlapEnd.timeIntervalSince(overlapStart), 0)
            let sampleDuration = max(sample.end.timeIntervalSince(sample.start), 1)
            let ratio = Statistics.clamped(overlapDuration / sampleDuration, min: 0, max: 1)
            return partial + (sample.value * ratio)
        }
    }

    private func hasWorkoutConflict(bucketStart: Date, workouts: [TimeRange]) -> Bool {
        workouts.contains { workout in
            if workout.contains(bucketStart) {
                return true
            }
            let cooldownEnd = workout.end.addingTimeInterval(30 * 60)
            return bucketStart >= workout.end && bucketStart <= cooldownEnd
        }
    }

    private func sourceRank(for sample: HKSample) -> Int {
        let productType = sample.sourceRevision.productType?.lowercased() ?? ""
        let deviceModel = sample.device?.model?.lowercased() ?? ""
        let bundle = sample.sourceRevision.source.bundleIdentifier.lowercased()
        let hasAlgorithmVersion = sample.metadata?[HKMetadataKeyAlgorithmVersion] != nil

        if productType.contains("watch") || deviceModel.contains("watch") {
            return 3
        }
        if bundle.hasPrefix("com.apple") && hasAlgorithmVersion {
            return 2
        }
        if bundle.hasPrefix("com.apple") {
            return 1
        }
        return 0
    }

    private func isUserEntered(_ sample: HKSample) -> Bool {
        (sample.metadata?[HKMetadataKeyWasUserEntered] as? Bool) == true
    }

    private func mapSleepStage(_ rawValue: Int) -> SleepStage {
        switch rawValue {
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

    private func startOfFiveMinuteBucket(for date: Date) -> Date {
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let minute = ((components.minute ?? 0) / 5) * 5
        var normalized = components
        normalized.minute = minute
        normalized.second = 0
        normalized.nanosecond = 0
        return calendar.date(from: normalized) ?? date
    }

    private func emptySleepData() -> SleepData {
        SleepData(
            segments: [],
            inBedStart: nil,
            inBedEnd: nil,
            totalSleepMinutes: 0,
            deepMinutes: 0,
            remMinutes: 0,
            coreMinutes: 0,
            awakeMinutes: 0,
            efficiency: 0,
            bedtime: nil,
            stageCoverage: 0,
            sourcePurity: 0,
            interruptionsCount: 0
        )
    }
}
