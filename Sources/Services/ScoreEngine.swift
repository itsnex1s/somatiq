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

enum EnergyLevel: String {
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

struct EnergyResult {
    let score: Int
    let level: EnergyLevel
    let delta: Double
}

struct ScoreEngine {
    func calculateStress(
        currentSDNN: Double,
        currentRHR: Double,
        baselineSDNN: Double,
        baselineRHR: Double
    ) -> StressResult {
        let safeSDNN = max(currentSDNN, 1)
        let safeBaselineSDNN = max(baselineSDNN, 1)
        let safeRHR = max(currentRHR, 1)
        let safeBaselineRHR = max(baselineRHR, 1)

        let lnSDNN = log(safeSDNN)
        let lnBaselineSDNN = log(safeBaselineSDNN)
        let ratio = Statistics.clamped(lnSDNN / max(lnBaselineSDNN, 0.001), min: 0.5, max: 1.5)
        let hrvStress = (1.5 - ratio) * 100

        let deviation = Statistics.clamped(
            (safeRHR - safeBaselineRHR) / safeBaselineRHR,
            min: -0.3,
            max: 0.3
        )
        let hrStress = ((deviation + 0.3) / 0.6) * 100

        let total = Statistics.clampedInt((hrvStress * 0.7) + (hrStress * 0.3), min: 0, max: 100)
        let level = stressLevel(for: total)
        return StressResult(score: total, level: level)
    }

    func calculateSleep(
        sleepData: SleepData,
        bedtimeHistory: [Date],
        targetHours: Double
    ) -> SleepResult {
        let durationHours = sleepData.totalSleepMinutes / 60
        let duration = durationScore(hours: durationHours, targetHours: targetHours)
        let efficiency = efficiencyScore(value: sleepData.efficiency)
        let deep = stageScore(
            ratio: percentage(part: sleepData.deepMinutes, total: sleepData.totalSleepMinutes),
            ideal: 0.20,
            lowBound: 0.10,
            maxPoints: 20
        )
        let rem = stageScore(
            ratio: percentage(part: sleepData.remMinutes, total: sleepData.totalSleepMinutes),
            ideal: 0.25,
            lowBound: 0.10,
            maxPoints: 15
        )
        let consistency = consistencyScore(bedtimes: bedtimeHistory)

        let total = Statistics.clampedInt(duration + efficiency + deep + rem + consistency, min: 0, max: 100)
        let level = sleepLevel(for: total)
        return SleepResult(score: total, level: level)
    }

    func calculateEnergy(
        sleepData: SleepData,
        currentSDNN: Double,
        baselineSDNN: Double,
        currentRHR: Double,
        baselineRHR: Double,
        activeCalories: Double,
        steps: Int,
        wakeHours: Double,
        previousEnergy: Double?
    ) -> EnergyResult {
        // HRV quality factor: how well-recovered you are
        let quality = Statistics.clamped(
            currentSDNN / max(baselineSDNN, 1),
            min: 0.5,
            max: 1.5
        )

        // HR factor: lower HR during sleep = better recovery
        let hrFactor = Statistics.clamped(
            max(baselineRHR, 1) / max(currentRHR, 1),
            min: 0.7,
            max: 1.3
        )

        // CHARGE: sleep stages × quality × hrFactor
        let deepHours = sleepData.deepMinutes / 60
        let remHours = sleepData.remMinutes / 60
        let coreHours = sleepData.coreMinutes / 60
        let awakeHours = sleepData.awakeMinutes / 60

        let sleepCharge =
            (deepHours * 10 * quality * hrFactor) +
            (remHours * 6 * quality * hrFactor) +
            (coreHours * 4 * quality * hrFactor)

        // Restful wake: 2 pts/hr if HRV above baseline (relaxed wakefulness)
        let restfulWakeCharge = currentSDNN > baselineSDNN ? awakeHours * 2 : 0

        // DRAIN: activity + stress + baseline metabolic
        let calorieDrain = activeCalories / 500 * 5

        // Stress drain: 1-5 pts/hr scaled by HR elevation above baseline
        let hrElevation = Statistics.clamped(
            (currentRHR - baselineRHR) / max(baselineRHR, 1),
            min: 0,
            max: 0.3
        )
        let stressDrainRate = 1 + (hrElevation / 0.3) * 4  // 1-5 pts/hr
        let stressDrain = stressDrainRate * max(wakeHours, 0)

        let totalCharge = sleepCharge + restfulWakeCharge
        let totalDrain = calorieDrain + stressDrain

        let startLevel = previousEnergy ?? 50
        let updated = Statistics.clamped(startLevel + totalCharge - totalDrain, min: 0, max: 100)

        let score = Statistics.clampedInt(updated, min: 0, max: 100)
        let level = energyLevel(for: score)
        let delta = updated - startLevel
        return EnergyResult(score: score, level: level, delta: delta)
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

    private func energyLevel(for score: Int) -> EnergyLevel {
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
