import Foundation

enum Statistics {
    static func mean(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let total = values.reduce(0, +)
        return total / Double(values.count)
    }

    static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let middle = sorted.count / 2

        if sorted.count.isMultiple(of: 2) {
            return (sorted[middle - 1] + sorted[middle]) / 2
        }
        return sorted[middle]
    }

    static func standardDeviation(_ values: [Double]) -> Double? {
        guard values.count > 1, let mean = mean(values) else { return nil }
        let variance = values
            .map { pow($0 - mean, 2) }
            .reduce(0, +) / Double(values.count - 1)  // sample variance (Bessel's correction)
        return sqrt(variance)
    }

    static func percentile(_ values: [Double], percentile: Double) -> Double? {
        guard !values.isEmpty else { return nil }
        let clampedPercentile = clamped(percentile, min: 0, max: 1)
        let sorted = values.sorted()
        guard sorted.count > 1 else { return sorted.first }

        let index = clampedPercentile * Double(sorted.count - 1)
        let lower = Int(floor(index))
        let upper = Int(ceil(index))
        if lower == upper {
            return sorted[lower]
        }
        let weight = index - Double(lower)
        return sorted[lower] + (sorted[upper] - sorted[lower]) * weight
    }

    static func iqr(_ values: [Double]) -> Double? {
        guard let p25 = percentile(values, percentile: 0.25),
              let p75 = percentile(values, percentile: 0.75) else {
            return nil
        }
        return p75 - p25
    }

    static func winsorized(
        _ values: [Double],
        lowerPercentile: Double = 0.1,
        upperPercentile: Double = 0.9
    ) -> [Double] {
        guard !values.isEmpty else { return values }
        guard let lower = percentile(values, percentile: lowerPercentile),
              let upper = percentile(values, percentile: upperPercentile) else {
            return values
        }
        return values.map { clamped($0, min: lower, max: upper) }
    }

    static func robustZ(
        _ value: Double,
        median: Double,
        iqr: Double,
        iqrFloor: Double = 1
    ) -> Double {
        let safeScale = max(abs(iqr), iqrFloor)
        return clamped((value - median) / safeScale, min: -4, max: 4)
    }

    static func sigmoid(_ value: Double, k: Double = 0.9) -> Double {
        1 / (1 + exp(-k * value))
    }

    static func circularMinutesDistance(_ lhs: Double, _ rhs: Double) -> Double {
        let minutesInDay = 1_440.0
        let a = lhs.truncatingRemainder(dividingBy: minutesInDay)
        let b = rhs.truncatingRemainder(dividingBy: minutesInDay)
        let diff = abs(a - b)
        return min(diff, minutesInDay - diff)
    }

    static func clamped(_ value: Double, min minValue: Double, max maxValue: Double) -> Double {
        min(max(value, minValue), maxValue)
    }

    static func clampedInt(_ value: Double, min minValue: Int, max maxValue: Int) -> Int {
        Int(clamped(value, min: Double(minValue), max: Double(maxValue)).rounded())
    }
}
