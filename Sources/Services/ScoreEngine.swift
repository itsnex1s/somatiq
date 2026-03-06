import Foundation

enum StressLevel: String {
    case low
    case moderate
    case high
}

enum SleepLevel: String {
    case poor
    case fair
    case good
    case great
}

enum BatteryLevel: String {
    case depleted
    case low
    case good
    case charged
}

struct StressResult {
    let score: Int
    let level: StressLevel
}

struct SleepResult {
    let score: Int
    let level: SleepLevel
}

struct BatteryResult {
    let score: Int
    let level: BatteryLevel
    let delta: Double
}

struct EngineBaseline {
    let validNightCount: Int
    let lnHrvMedian28: Double
    let lnHrvIQR28: Double
    let lnHrvMedian60: Double
    let rhrMedian28: Double
    let rhrIQR28: Double
    let durationMedian28Hours: Double
    let durationMedian60Hours: Double
    let midpointMedian28: Double?
    let midpointSD7: Double?
    let activeEnergyMedian28: Double
    let activeEnergyIQR28: Double
    let stepsMedian28: Double
    let stepsIQR28: Double
}

struct EngineComputation {
    let stress: StressResult
    let sleep: SleepResult
    let battery: BatteryResult
    let heartScore: Int
    let publishedHRV: Double
    let nightlyRHR: Double
    let confidence: Double
    let qualityReasons: [String]
    let isCalibrating: Bool
}

struct ScoreEngine {
    func buildBaseline(from history: [DailyScore]) -> EngineBaseline {
        let sorted = history.sorted(by: { $0.date < $1.date })
        let validNights = sorted.filter { score in
            score.sleepDurationMin >= 240 && score.avgSDNN > 0 && score.restingHR > 0 && (score.scoreConfidence ?? 0) >= 0.4
        }

        let last28 = Array(validNights.suffix(28))
        let last60 = Array(validNights.suffix(60))
        let last7 = Array(validNights.suffix(7))

        let lnHrv28 = last28.map { log(max($0.avgSDNN, 1)) }
        let lnHrv60 = last60.map { log(max($0.avgSDNN, 1)) }
        let rhr28 = last28.map(\.restingHR).filter { $0 > 0 }
        let duration28 = last28.map { $0.sleepDurationMin / 60 }.filter { $0 > 0 }
        let duration60 = last60.map { $0.sleepDurationMin / 60 }.filter { $0 > 0 }
        let activeEnergy28 = last28.map(\.activeCalories).filter { $0 >= 0 }
        let steps28 = last28.map { Double($0.steps) }.filter { $0 >= 0 }

        let bedtimes28 = last28.compactMap(\.bedtimeAt).map(minutesFromMidnight(for:))
        let bedtimes7 = last7.compactMap(\.bedtimeAt).map(minutesFromMidnight(for:))

        return EngineBaseline(
            validNightCount: validNights.count,
            lnHrvMedian28: Statistics.median(lnHrv28) ?? log(35),
            lnHrvIQR28: max(Statistics.iqr(lnHrv28) ?? 0.2, 0.08),
            lnHrvMedian60: Statistics.median(lnHrv60) ?? Statistics.median(lnHrv28) ?? log(35),
            rhrMedian28: Statistics.median(rhr28) ?? 60,
            rhrIQR28: max(Statistics.iqr(rhr28) ?? 6, 3),
            durationMedian28Hours: Statistics.median(duration28) ?? 7,
            durationMedian60Hours: Statistics.median(duration60) ?? Statistics.median(duration28) ?? 7,
            midpointMedian28: Statistics.circularMedian(bedtimes28),
            midpointSD7: Statistics.standardDeviation(bedtimes7),
            activeEnergyMedian28: Statistics.median(activeEnergy28) ?? 350,
            activeEnergyIQR28: max(Statistics.iqr(activeEnergy28) ?? 120, 60),
            stepsMedian28: Statistics.median(steps28) ?? 6_500,
            stepsIQR28: max(Statistics.iqr(steps28) ?? 2_500, 1_200)
        )
    }

    func compute(
        input: DailyHealthInput,
        baseline: EngineBaseline,
        previousPublished: DailyScore?
    ) -> EngineComputation {
        let nightHRVSample = resolveNightHRVSample(input: input)
        let nightHRVValue = nightHRVSample?.value ?? 0
        let lnNightHRV = nightHRVSample.map { log(max($0.value, 1)) } ?? baseline.lnHrvMedian28

        let nightlyRHR = deriveNightlyRHR(from: input.nightHeartRateBins) ?? baseline.rhrMedian28

        var qualityReasons = input.qualityNotes
        qualityReasons.append(contentsOf: physiologicalQualityReasons(nightHRV: nightHRVValue, nightlyRHR: nightlyRHR))
        qualityReasons = Array(Set(qualityReasons)).sorted()

        let gateState = evaluateGates(input: input, nightHRVSampleCount: nightHRVSample == nil ? 0 : 1, priorReasons: qualityReasons)
        qualityReasons.append(contentsOf: gateState.reasons)
        qualityReasons = Array(Set(qualityReasons)).sorted()

        let baselineMaturity = Statistics.clamped(Double(baseline.validNightCount) / 14, min: 0, max: 1)
        let coverageScore = gateState.coverageScore
        let sourcePurity = Statistics.clamped(input.sourcePurity, min: 0, max: 1)
        let contextValidity = gateState.contextValidity
        var confidence = Statistics.clamped(
            (0.35 * coverageScore) + (0.25 * sourcePurity) + (0.20 * baselineMaturity) + (0.20 * contextValidity),
            min: 0,
            max: 1
        )

        if baseline.validNightCount < 7 {
            confidence = min(confidence, 0.5)
            qualityReasons.append("calibration_mode")
        } else if baseline.validNightCount < 14 {
            confidence = min(confidence, 0.65)
            qualityReasons.append("calibration_mode")
        }
        qualityReasons = Array(Set(qualityReasons)).sorted()

        let zNightHRV = robustZ(
            lnNightHRV,
            median: baseline.lnHrvMedian28,
            iqr: baseline.lnHrvIQR28,
            floor: 0.06
        )
        let zNightRHR = robustZ(
            nightlyRHR,
            median: baseline.rhrMedian28,
            iqr: baseline.rhrIQR28,
            floor: 2
        )

        let rawHeart = 100 * ((0.65 * goodZ(zNightHRV)) + (0.35 * badZ(zNightRHR)))

        let (rawStress, stressHrvMissing) = computeStressRaw(
            restWindows: input.restWindows,
            baselineLnHrv: baseline.lnHrvMedian28,
            baselineLnHrvIQR: baseline.lnHrvIQR28,
            baselineRHR: baseline.rhrMedian28,
            baselineRHRIQR: baseline.rhrIQR28
        )
        if stressHrvMissing {
            qualityReasons.append("stress_hrv_missing")
            confidence = min(confidence, 0.65)
        }

        let currentMidpoint = bedtimeMinutes(from: input.sleep)
        let rawSleep = computeSleepRaw(
            input: input,
            heartRaw: rawHeart,
            baseline: baseline,
            currentMidpoint: currentMidpoint
        )

        let rawBattery = computeBatteryRaw(
            input: input,
            baseline: baseline,
            sleepRaw: rawSleep,
            heartRaw: rawHeart,
            stressRaw: rawStress
        )

        let previousStress = previousPublished?.stressScore
        let previousSleep = previousPublished?.sleepScore
        let previousBattery = previousPublished?.bodyBatteryScore
        let previousHeart: Int? = previousPublished.map {
            $0.heartScore > 0 ? $0.heartScore : deriveHeartProxy(from: $0)
        }

        let isCalibrating = baseline.validNightCount < 14

        let publishedStress = publishScore(raw: rawStress, previous: previousStress, confidence: confidence)
        let publishedBattery = publishScore(raw: rawBattery, previous: previousBattery, confidence: confidence)
        let publishedHeart = publishScore(raw: rawHeart, previous: previousHeart, confidence: confidence)

        let publishedSleep = publishScore(raw: rawSleep, previous: previousSleep, confidence: confidence)

        let stressResult = StressResult(score: publishedStress, level: stressLevel(for: publishedStress))
        let sleepResult = SleepResult(score: publishedSleep, level: sleepLevel(for: publishedSleep))
        let batteryResult = BatteryResult(
            score: publishedBattery,
            level: batteryLevel(for: publishedBattery),
            delta: Double(publishedBattery - (previousBattery ?? publishedBattery))
        )

        return EngineComputation(
            stress: stressResult,
            sleep: sleepResult,
            battery: batteryResult,
            heartScore: publishedHeart,
            publishedHRV: max(nightHRVValue, 0),
            nightlyRHR: max(nightlyRHR, 0),
            confidence: confidence,
            qualityReasons: qualityReasons,
            isCalibrating: isCalibrating
        )
    }

    private func resolveNightHRVSample(input: DailyHealthInput) -> HRVSample? {
        if let rmssd = medianHRVSample(from: input.nightRMSDDSamples) {
            return rmssd
        }
        return medianHRVSample(from: input.nightSDNNSamples)
    }

    private func medianHRVSample(from samples: [HRVSample]) -> HRVSample? {
        guard !samples.isEmpty else { return nil }
        let values = samples.map(\.value)
        guard let medianValue = Statistics.median(values) else { return nil }
        let closest = samples.min { lhs, rhs in
            abs(lhs.value - medianValue) < abs(rhs.value - medianValue)
        }
        return closest
    }

    private func deriveNightlyRHR(from bins: [Double]) -> Double? {
        guard !bins.isEmpty else { return nil }
        let sorted = bins.sorted()
        let sampleSize = max(Int(Double(sorted.count) * 0.2), 1)
        let lowest = Array(sorted.prefix(sampleSize))
        return Statistics.median(lowest)
    }

    private func physiologicalQualityReasons(nightHRV: Double, nightlyRHR: Double) -> [String] {
        var reasons: [String] = []
        if nightHRV > 0, !(5 ... 300).contains(nightHRV) {
            reasons.append("physiologically_implausible_hrv")
        }
        if nightlyRHR > 0, !(25 ... 120).contains(nightlyRHR) {
            reasons.append("physiologically_implausible_rhr")
        }
        return reasons
    }

    private func evaluateGates(input: DailyHealthInput, nightHRVSampleCount: Int, priorReasons: [String]) -> (coverageScore: Double, contextValidity: Double, reasons: [String]) {
        var reasons: [String] = []

        let sleepHours = input.sleep.totalSleepMinutes / 60
        let stageCoverage = input.sleep.stageCoverage
        let nightCoverage = input.nightHRCoverage
        let restWindowCount = input.restWindows.count
        let wearCoverage = input.dayWatchWearCoverage

        if sleepHours < 4 { reasons.append("insufficient_sleep_duration") }
        if stageCoverage < 0.5 { reasons.append("low_stage_coverage") }
        if nightCoverage < 0.2 { reasons.append("insufficient_hr_samples") }
        if nightHRVSampleCount < 1 { reasons.append("insufficient_hrv_samples") }
        if restWindowCount < 3 { reasons.append("insufficient_rest_windows") }
        if wearCoverage < 0.5 { reasons.append("low_daytime_wear") }

        let coverageScore = Statistics.clamped(
            (
                min(sleepHours / 6, 1) +
                min(stageCoverage / 0.8, 1) +
                min(nightCoverage / 0.4, 1) +
                min(Double(max(nightHRVSampleCount, 0)) / 2, 1) +
                min(Double(restWindowCount) / 6, 1) +
                min(wearCoverage / 0.75, 1)
            ) / 6,
            min: 0,
            max: 1
        )

        let contextValidity = priorReasons.contains(where: { $0.hasPrefix("physiologically_implausible") }) ? 0.0 : 1.0
        return (coverageScore, contextValidity, reasons)
    }

    private func computeStressRaw(
        restWindows: [RestWindowSample],
        baselineLnHrv: Double,
        baselineLnHrvIQR: Double,
        baselineRHR: Double,
        baselineRHRIQR: Double
    ) -> (Double, Bool) {
        guard !restWindows.isEmpty else { return (50, true) }

        var withHRV: [Double] = []
        var withoutHRV: [Double] = []
        for window in restWindows {
            let zHR = robustZ(window.heartRate, median: baselineRHR, iqr: baselineRHRIQR, floor: 2)
            if let lnHRV = window.lnHRV {
                let zHRV = robustZ(lnHRV, median: baselineLnHrv, iqr: baselineLnHrvIQR, floor: 0.06)
                withHRV.append(100 * ((0.55 * badZ(zHRV)) + (0.45 * goodZ(zHR))))
            } else {
                withoutHRV.append(100 * goodZ(zHR))
            }
        }

        if !withHRV.isEmpty {
            return (Statistics.percentile(withHRV, percentile: 0.7) ?? 50, false)
        }
        return (Statistics.percentile(withoutHRV, percentile: 0.7) ?? 50, true)
    }

    private func computeSleepRaw(
        input: DailyHealthInput,
        heartRaw: Double,
        baseline: EngineBaseline,
        currentMidpoint: Double?
    ) -> Double {
        let durationHours = input.sleep.totalSleepMinutes / 60
        let targetDuration = Statistics.clamped(baseline.durationMedian28Hours, min: 6, max: 9)
        let durationScore = clip01(1 - abs(durationHours - targetDuration) / 3)
        let efficiencyScore = clip01((input.sleep.efficiency - 0.70) / 0.25)
        let interruptionsScore = clip01(1 - (input.sleep.awakeMinutes / 90)) * clip01(1 - (Double(input.sleep.interruptionsCount) / 6))

        let regularityScore: Double
        if let midpoint = currentMidpoint, let baselineMidpoint = baseline.midpointMedian28 {
            let midpointShift = Statistics.circularMinutesDistance(midpoint, baselineMidpoint)
            let midpointComponent = clip01(1 - midpointShift / 120)
            let stabilityBase = baseline.midpointSD7 ?? 45
            let stabilityComponent = clip01(1 - stabilityBase / 90)
            regularityScore = (0.6 * midpointComponent) + (0.4 * stabilityComponent)
        } else {
            regularityScore = 0.5
        }

        let physioScore = clip01(heartRaw / 100)
        return 100 * (
            (0.30 * durationScore) +
                (0.20 * efficiencyScore) +
                (0.10 * interruptionsScore) +
                (0.20 * regularityScore) +
                (0.20 * physioScore)
        )
    }

    private func computeBatteryRaw(
        input: DailyHealthInput,
        baseline: EngineBaseline,
        sleepRaw: Double,
        heartRaw: Double,
        stressRaw: Double
    ) -> Double {
        let batteryAM = (0.55 * sleepRaw) + (0.45 * heartRaw)

        let zActiveEnergy = robustZ(
            input.activeEnergy,
            median: baseline.activeEnergyMedian28,
            iqr: baseline.activeEnergyIQR28,
            floor: 40
        )
        let zSteps = robustZ(
            Double(input.steps),
            median: baseline.stepsMedian28,
            iqr: baseline.stepsIQR28,
            floor: 800
        )

        let activityDrain = clip01((0.7 * posZ(zActiveEnergy)) + (0.3 * posZ(zSteps)))
        let stressDrain = clip01(max(0, stressRaw - 50) / 40)
        let workoutDrain = clip01(input.workoutMinutes / 120)

        return Statistics.clamped(
            batteryAM - 100 * ((0.45 * activityDrain) + (0.35 * stressDrain) + (0.20 * workoutDrain)),
            min: 0,
            max: 100
        )
    }

    private func publishScore(raw: Double, previous: Int?, confidence: Double) -> Int {
        let rawInt = Statistics.clampedInt(raw, min: 0, max: 100)
        guard let previous else { return rawInt }

        if confidence < 0.4 {
            return clampDelta(raw: rawInt, previous: previous, limit: 2)
        }
        if confidence < 0.7 {
            return clampDelta(raw: rawInt, previous: previous, limit: 5)
        }
        return clampDelta(raw: rawInt, previous: previous, limit: 10)
    }

    private func clampDelta(raw: Int, previous: Int, limit: Int) -> Int {
        let delta = raw - previous
        if delta > limit { return previous + limit }
        if delta < -limit { return previous - limit }
        return raw
    }

    private func deriveHeartProxy(from score: DailyScore) -> Int {
        let inferred = (Double(score.sleepScore) * 0.45) + (Double(score.bodyBatteryScore) * 0.55)
        return Statistics.clampedInt(inferred, min: 0, max: 100)
    }

    private func bedtimeMinutes(from sleep: SleepData) -> Double? {
        guard let bedtime = sleep.bedtime else { return nil }
        return minutesFromMidnight(for: bedtime)
    }

    private func minutesFromMidnight(for date: Date) -> Double {
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        return Double((components.hour ?? 0) * 60 + (components.minute ?? 0))
    }

    private func robustZ(_ value: Double, median: Double, iqr: Double, floor: Double) -> Double {
        let scale = max((iqr / 1.349), floor, 0.0001)
        let z = (value - median) / scale
        return Statistics.clamped(z, min: -3, max: 3)
    }

    private func goodZ(_ z: Double) -> Double {
        clip01(0.5 + (Statistics.clamped(z, min: -3, max: 3) / 6))
    }

    private func badZ(_ z: Double) -> Double {
        1 - goodZ(z)
    }

    private func posZ(_ z: Double) -> Double {
        clip01(max(z, 0) / 3)
    }

    private func clip01(_ value: Double) -> Double {
        Statistics.clamped(value, min: 0, max: 1)
    }

    private func stressLevel(for score: Int) -> StressLevel {
        switch score {
        case 0 ... 33:
            return .low
        case 34 ... 66:
            return .moderate
        default:
            return .high
        }
    }

    private func sleepLevel(for score: Int) -> SleepLevel {
        switch score {
        case 0 ... 40:
            return .poor
        case 41 ... 60:
            return .fair
        case 61 ... 80:
            return .good
        default:
            return .great
        }
    }

    private func batteryLevel(for score: Int) -> BatteryLevel {
        switch score {
        case 0 ... 25:
            return .depleted
        case 26 ... 50:
            return .low
        case 51 ... 75:
            return .good
        default:
            return .charged
        }
    }
}
