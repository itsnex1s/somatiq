import SwiftUI

struct WeeklyTrendCard: View {
    let scores: [DailyScore]

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("Score History")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(SomatiqColor.textPrimary)
                    Spacer()
                    Text("This week")
                        .font(.system(size: 11))
                        .foregroundStyle(SomatiqColor.textTertiary)
                }

                SparklineRow(
                    title: "Stress",
                    color: SomatiqColor.stress,
                    values: scores.map { $0.stressScore },
                    days: scores.map(\.date)
                )

                SparklineRow(
                    title: "Sleep",
                    color: SomatiqColor.sleep,
                    values: scores.map { $0.sleepScore },
                    days: scores.map(\.date)
                )

                SparklineRow(
                    title: "Energy",
                    color: SomatiqColor.energy,
                    values: scores.map { $0.energyScore },
                    days: scores.map(\.date)
                )
            }
        }
    }
}

private struct SparklineRow: View {
    let title: String
    let color: Color
    let values: [Int]
    let days: [Date]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(color)

            HStack(alignment: .bottom, spacing: 6) {
                ForEach(Array(values.enumerated()), id: \.offset) { index, value in
                    VStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(
                                LinearGradient(
                                    colors: [color.opacity(0.35), color.opacity(0.9)],
                                    startPoint: .bottom,
                                    endPoint: .top
                                )
                            )
                            .frame(width: 18, height: barHeight(for: value))
                            .overlay(
                                RoundedRectangle(cornerRadius: 4)
                                    .stroke(index == values.count - 1 ? color.opacity(0.55) : .clear, lineWidth: 1)
                            )

                        Text(dayLabel(for: index))
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(SomatiqColor.textMuted)
                    }
                }
            }
            .frame(height: 64, alignment: .bottom)
        }
    }

    private func barHeight(for value: Int) -> CGFloat {
        CGFloat(max(8, Int(round((Double(value) / 100) * 48))))
    }

    private func dayLabel(for index: Int) -> String {
        guard days.indices.contains(index) else { return "-" }
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.dateFormat = "EEEEE"
        return formatter.string(from: days[index])
    }
}
