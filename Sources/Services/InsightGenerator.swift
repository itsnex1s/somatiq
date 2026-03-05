import Foundation

struct InsightGenerator {
    func generateInsight(
        stress: StressResult,
        sleep: SleepResult,
        battery: BatteryResult,
        sleepHours: Double,
        hrv: Double,
        baselineHRV: Double,
        scoreConfidence: Double,
        qualityReason: String?
    ) -> String {
        if scoreConfidence < 0.7 {
            let reasonText = qualityReason ?? "limited reliable inputs today"
            return "Data confidence is limited (\(reasonText)). Keep trends in view and retake a calm morning measurement tomorrow."
        }

        if sleep.score < 45 {
            return "Sleep was limited (\(formatted(sleepHours))h), so recovery is weaker today. Prioritize an earlier bedtime."
        }

        if stress.level == .high {
            return "Stress is elevated versus your baseline. Consider a short low-intensity walk and breathing break."
        }

        if battery.level == .charged && stress.level == .low {
            return "Recovery looks strong today. Battery is charged and stress remains low."
        }

        if hrv < baselineHRV * 0.9 {
            return "HRV is below your baseline, suggesting reduced recovery. Keep workload moderate today."
        }

        if sleep.level == .great {
            return "Solid sleep quality supports stable battery and stress resilience today."
        }

        return "Your body signals are stable today. Keep hydration, movement, and sleep timing consistent."
    }

    private func formatted(_ value: Double) -> String {
        String(format: "%.1f", value)
    }
}
