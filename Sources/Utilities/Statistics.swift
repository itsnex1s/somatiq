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

    static func clamped(_ value: Double, min minValue: Double, max maxValue: Double) -> Double {
        min(max(value, minValue), maxValue)
    }

    static func clampedInt(_ value: Double, min minValue: Int, max maxValue: Int) -> Int {
        Int(clamped(value, min: Double(minValue), max: Double(maxValue)).rounded())
    }
}
