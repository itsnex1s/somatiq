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

struct ScoreEngine {
    func calculateStress(
        currentSDNN: Double,
        currentRHR: Double,
        baselineSDNN: Double,
        baselineRHR: Double,
        baselineSDNNIQR: Double = 8,
        baselineRHRIQR: Double = 5,
        currentLoad: Double = 0,
        baselineLoad: Double = 0
    ) -> StressResult {
        let safeSDNN = max(currentSDNN, 1)
        let safeBaselineSDNN = max(baselineSDNN, 1)
        let lnCurrent = log(safeSDNN)
        let lnBaseline = log(safeBaselineSDNN)

        let sdnnIqrInLogSpace = max(baselineSDNNIQR / safeBaselineSDNN, 0.04)
        let zHRV = Statistics.robustZ(
            lnCurrent,
            median: lnBaseline,
            iqr: sdnnIqrInLogSpace,
            iqrFloor: 0.04
        )
        let zRHR = Statistics.robustZ(
            max(currentRHR, 1),
            median: max(baselineRHR, 1),
            iqr: baselineRHRIQR,
            iqrFloor: 2
        )
        let zLoad = Statistics.robustZ(
            currentLoad,
            median: baselineLoad,
            iqr: max(baselineLoad * 0.25, 2),
            iqrFloor: 2
        )

        let stressRaw = (0.55 * (-zHRV)) + (0.30 * zRHR) + (0.15 * zLoad)
        let total = Statistics.clampedInt(Statistics.sigmoid(stressRaw, k: 0.9) * 100, min: 0, max: 100)
        let level = stressLevel(for: total)
        return StressResult(score: total, level: level)
    }

    func calculateSleep(
        sleepData: SleepData,
        bedtimeHistory: [Date],
        targetHours: Double,
        currentSDNN: Double? = nil,
        currentRHR: Double? = nil,
        baselineSDNN: Double? = nil,
        baselineRHR: Double? = nil,
        baselineSleepMidpointMinutes: Double? = nil
    ) -> SleepResult {
        let durationHours = sleepData.totalSleepMinutes / 60
        let target = max(targetHours, 6)
        let durationDeltaRatio = abs(durationHours - target) / target
        let durationComponent = Statistics.clamped(100 - (durationDeltaRatio * 120), min: 0, max: 100)

        let efficiencyComponent = Statistics.clamped(
            ((sleepData.efficiency - 0.75) / (0.95 - 0.75)) * 100,
            min: 0,
            max: 100
        )

        let timingConsistency: Double
        if let baselineSleepMidpointMinutes,
           let todayMidpoint = sleepMidpointMinutes(from: sleepData),
           !bedtimeHistory.isEmpty {
            let distance = Statistics.circularMinutesDistance(todayMidpoint, baselineSleepMidpointMinutes)
            timingConsistency = Statistics.clamped(100 - (distance / 180 * 100), min: 0, max: 100)
        } else {
            timingConsistency = consistencyScore(bedtimes: bedtimeHistory) * (100 / 15)
        }

        let recoveryComponent: Double
        if let currentSDNN, let currentRHR, let baselineSDNN, let baselineRHR {
            let zHRV = Statistics.robustZ(
                log(max(currentSDNN, 1)),
                median: log(max(baselineSDNN, 1)),
                iqr: max(0.05, (max(baselineSDNN, 1) * 0.20) / max(baselineSDNN, 1)),
                iqrFloor: 0.05
            )
            let zRHR = Statistics.robustZ(
                max(currentRHR, 1),
                median: max(baselineRHR, 1),
                iqr: max(baselineRHR * 0.1, 2),
                iqrFloor: 2
            )
            recoveryComponent = Statistics.clamped(50 + (25 * zHRV) - (15 * zRHR), min: 0, max: 100)
        } else {
            let deepRatio = percentage(part: sleepData.deepMinutes, total: sleepData.totalSleepMinutes)
            let remRatio = percentage(part: sleepData.remMinutes, total: sleepData.totalSleepMinutes)
            recoveryComponent = Statistics.clamped(
                (stageScore(ratio: deepRatio, ideal: 0.2, lowBound: 0.1, maxPoints: 50) +
                    stageScore(ratio: remRatio, ideal: 0.25, lowBound: 0.1, maxPoints: 50)),
                min: 0,
                max: 100
            )
        }

        let total = Statistics.clampedInt(
            (0.35 * durationComponent) +
                (0.20 * efficiencyComponent) +
                (0.20 * timingConsistency) +
                (0.25 * recoveryComponent),
            min: 0,
            max: 100
        )
        let level = sleepLevel(for: total)
        return SleepResult(score: total, level: level)
    }

    func calculateBodyBattery(
        sleepData: SleepData,
        currentSDNN: Double,
        baselineSDNN: Double,
        currentRHR: Double,
        baselineRHR: Double,
        activeCalories: Double,
        steps: Int,
        wakeHours: Double,
        previousBattery: Double?,
        sleepDebtHours: Double = 0,
        overnightRecoveryBonus: Bool = false,
        stressScore: Int? = nil
    ) -> BatteryResult {
        let sleepScoreApprox = calculateSleep(
            sleepData: sleepData,
            bedtimeHistory: [],
            targetHours: 8,
            currentSDNN: currentSDNN,
            currentRHR: currentRHR,
            baselineSDNN: baselineSDNN,
            baselineRHR: baselineRHR
        ).score

        let zHRV = Statistics.robustZ(
            log(max(currentSDNN, 1)),
            median: log(max(baselineSDNN, 1)),
            iqr: max((baselineSDNN * 0.20) / max(baselineSDNN, 1), 0.05),
            iqrFloor: 0.05
        )
        let zRHR = Statistics.robustZ(
            currentRHR,
            median: baselineRHR,
            iqr: max(baselineRHR * 0.1, 2),
            iqrFloor: 2
        )

        let morningAnchor = Statistics.clamped(
            35 + (0.35 * Double(sleepScoreApprox)) + (20 * Statistics.sigmoid(0.9 * (zHRV - 0.6 * zRHR))),
            min: 0,
            max: 100
        )

        let activityLoad = estimateLoad(activeCalories: activeCalories, steps: steps)
        let drainActivity = Statistics.clamped(activityLoad * 1.5, min: 0, max: 25)
        let stressSource = stressScore.map(Double.init) ?? Double(calculateStress(
            currentSDNN: currentSDNN,
            currentRHR: currentRHR,
            baselineSDNN: baselineSDNN,
            baselineRHR: baselineRHR
        ).score)
        let drainStress = Statistics.clamped((stressSource / 100) * max(wakeHours, 0) * 0.8, min: 0, max: 12)
        let drainWake = Statistics.clamped(1.5 + max(wakeHours - 14, 0), min: 0, max: 12)

        let debtPenalty = Statistics.clamped(sleepDebtHours * 1.2, min: 0, max: 12)
        let recoveryBonus: Double = overnightRecoveryBonus ? 4 : 0
        let restCharge: Double = currentSDNN > baselineSDNN ? 2 : 0

        let startLevel = previousBattery ?? morningAnchor
        let totalCharge = startLevel + restCharge + recoveryBonus
        let totalDrain = drainActivity + drainStress + drainWake + debtPenalty
        let rawUpdated = totalCharge - totalDrain
        let updated = Statistics.clamped(
            rawUpdated,
            min: 0,
            max: 100
        )

        let score = Statistics.clampedInt(updated, min: 0, max: 100)
        let level = batteryLevel(for: score)
        let delta = updated - startLevel
        return BatteryResult(score: score, level: level, delta: delta)
    }

    func calculateHeartScore(
        currentSDNN: Double,
        baselineSDNN: Double,
        baselineSDNNIQR: Double,
        recentSDNNValues: [Double]
    ) -> Int {
        let zHrv = Statistics.robustZ(
            log(max(currentSDNN, 1)),
            median: log(max(baselineSDNN, 1)),
            iqr: max((baselineSDNNIQR / max(baselineSDNN, 1)), 0.05),
            iqrFloor: 0.05
        )
        let lnRecent = recentSDNNValues.map { log(max($0, 1)) }
        let trend = Statistics.robustZ(
            Statistics.median(lnRecent) ?? log(max(currentSDNN, 1)),
            median: log(max(baselineSDNN, 1)),
            iqr: max((baselineSDNNIQR / max(baselineSDNN, 1)), 0.05),
            iqrFloor: 0.05
        )
        let volatility = Statistics.standardDeviation(lnRecent) ?? 0
        let volatilityPenalty = Statistics.clamped((volatility - 0.10) / 0.10, min: 0, max: 1)
        let heartRaw = (0.65 * zHrv) + (0.20 * trend) - (0.30 * volatilityPenalty)
        return Statistics.clampedInt(50 + (20 * heartRaw), min: 0, max: 100)
    }

    func estimateLoad(activeCalories: Double, steps: Int) -> Double {
        if activeCalories > 0 {
            return activeCalories / 10
        }
        return Double(steps) / 1_000
    }

    private func percentage(part: Double, total: Double) -> Double {
        guard total > 0 else { return 0 }
        return part / total
    }

    private func durationScore(hours: Double, targetHours: Double) -> Double {
        let target = max(targetHours, 6)
        if hours >= max(7, target - 1), hours <= min(9, target + 1) {
            return 30
        }
        if hours >= 6, hours < 7 {
            return 20 + ((hours - 6) * 10)
        }
        if hours >= 4, hours < 6 {
            return 5 + ((hours - 4) * 7.5)
        }
        if hours < 4 {
            return Statistics.clamped(hours * 1.25, min: 0, max: 5)
        }
        if hours > 9 {
            return Statistics.clamped(30 - ((hours - 9) * 5), min: 10, max: 30)
        }
        return 20
    }

    private func efficiencyScore(value: Double) -> Double {
        if value >= 0.90 { return 20 }
        if value >= 0.85 {
            return 16 + ((value - 0.85) / 0.05 * 4)
        }
        if value >= 0.70 {
            return ((value - 0.70) / 0.15 * 16)
        }
        return Statistics.clamped(value / 0.70 * 4, min: 0, max: 4)
    }

    private func stageScore(ratio: Double, ideal: Double, lowBound: Double, maxPoints: Double) -> Double {
        if ratio >= lowBound, ratio <= ideal + 0.1 {
            return maxPoints
        }
        if ratio >= lowBound * 0.5, ratio < lowBound {
            return maxPoints * 0.5 + ((ratio - (lowBound * 0.5)) / (lowBound * 0.5) * (maxPoints * 0.5))
        }
        if ratio > ideal + 0.1 {
            return Statistics.clamped(maxPoints - ((ratio - (ideal + 0.1)) * maxPoints), min: 0, max: maxPoints)
        }
        return Statistics.clamped(ratio / lowBound * (maxPoints * 0.5), min: 0, max: maxPoints * 0.5)
    }

    private func consistencyScore(bedtimes: [Date]) -> Double {
        guard bedtimes.count >= 3 else { return 8 }

        let minutesFromMidnight = bedtimes.map { date in
            let comps = Calendar.current.dateComponents([.hour, .minute], from: date)
            return Double((comps.hour ?? 0) * 60 + (comps.minute ?? 0))
        }

        guard let stdDev = Statistics.standardDeviation(minutesFromMidnight) else { return 8 }
        if stdDev <= 30 { return 15 }
        if stdDev <= 60 {
            return 10 + ((60 - stdDev) / 30 * 5)
        }
        if stdDev <= 120 {
            return ((120 - stdDev) / 60 * 10)
        }
        return 0
    }

    private func sleepMidpointMinutes(from sleepData: SleepData) -> Double? {
        guard let inBedStart = sleepData.inBedStart, let inBedEnd = sleepData.inBedEnd else {
            return nil
        }
        let midpoint = inBedStart.addingTimeInterval(inBedEnd.timeIntervalSince(inBedStart) / 2)
        let components = Calendar.current.dateComponents([.hour, .minute], from: midpoint)
        return Double((components.hour ?? 0) * 60 + (components.minute ?? 0))
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
