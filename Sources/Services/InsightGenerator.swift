import Foundation

struct InsightGenerator {
    func generateInsight(
        stress: StressResult,
        sleep: SleepResult,
        energy: EnergyResult,
        sleepHours: Double,
        hrv: Double,
        baselineHRV: Double
    ) -> String {
        if sleep.score < 45 {
            return "Sleep was limited (\(formatted(sleepHours))h), so recovery is weaker today. Prioritize an earlier bedtime."
        }

        if stress.level == .high {
            return "Stress is elevated versus your baseline. Consider a short low-intensity walk and breathing break."
        }

        if energy.level == .charged && stress.level == .low {
            return "Recovery looks strong today. Energy is high and stress remains low."
        }

        if hrv < baselineHRV * 0.9 {
            return "HRV is below your baseline, suggesting reduced recovery. Keep workload moderate today."
        }

        if sleep.level == .great {
            return "Solid sleep quality supports stable energy and stress resilience today."
        }

        return "Your body signals are stable today. Keep hydration, movement, and sleep timing consistent."
    }

    private func formatted(_ value: Double) -> String {
        String(format: "%.1f", value)
    }
}
