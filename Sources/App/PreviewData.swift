import Foundation

enum PreviewData {
    static func weekScores() -> [DailyScore] {
        let calendar = Calendar.current
        let today = Date().startOfDay

        let stress = [52, 44, 61, 47, 38, 40, 32]
        let sleep = [70, 85, 62, 90, 74, 88, 82]
        let energy = [80, 65, 55, 70, 85, 90, 75]

        return (0..<7).map { index in
            let date = calendar.date(byAdding: .day, value: index - 6, to: today) ?? today
            return DailyScore(
                date: date,
                stressScore: stress[index],
                sleepScore: sleep[index],
                energyScore: energy[index],
                stressLevel: stress[index] < 34 ? "low" : (stress[index] < 67 ? "moderate" : "high"),
                sleepLevel: sleep[index] > 80 ? "great" : (sleep[index] > 60 ? "good" : "fair"),
                energyLevel: energy[index] > 75 ? "charged" : (energy[index] > 50 ? "good" : "low"),
                sleepDurationMin: 420,
                sleepEfficiency: 0.9,
                deepSleepMin: 90,
                remSleepMin: 100,
                coreSleepMin: 230,
                bedtimeAt: date.addingTimeInterval(-8 * 3600),
                avgSDNN: 45,
                restingHR: 60,
                activeCalories: 420,
                steps: 8_400,
                insightText: "Your stress is low thanks to better sleep consistency."
            )
        }
    }
}
