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
                    title: "Battery",
                    color: SomatiqColor.bodyBattery,
                    values: scores.map { $0.bodyBatteryScore },
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

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(color)

            HStack(alignment: .bottom, spacing: 6) {
                ForEach(Array(values.enumerated()), id: \.offset) { index, value in
                    let isToday = index == values.count - 1

                    VStack(spacing: 4) {
                        if isToday {
                            Text("\(value)")
                                .font(.system(size: 9, weight: .bold, design: .rounded))
                                .foregroundStyle(color)
                                .opacity(appeared ? 1 : 0)
                        }

                        RoundedRectangle(cornerRadius: 6)
                            .fill(
                                LinearGradient(
                                    colors: [color.opacity(isToday ? 0.5 : 0.35), color.opacity(isToday ? 1.0 : 0.9)],
                                    startPoint: .bottom,
                                    endPoint: .top
                                )
                            )
                            .frame(width: 18, height: appeared ? barHeight(for: value) : 0)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(isToday ? color.opacity(0.6) : .clear, lineWidth: 1)
                            )
                            .shadow(
                                color: isToday ? color.opacity(0.3) : .clear,
                                radius: 4
                            )
                            .animation(
                                reduceMotion
                                    ? .linear(duration: 0.2)
                                    : SomatiqAnimation.staggered(index: index),
                                value: appeared
                            )

                        Text(dayLabel(for: index))
                            .font(.system(size: 9, weight: isToday ? .bold : .medium))
                            .foregroundStyle(isToday ? color : SomatiqColor.textMuted)
                    }
                }
            }
            .frame(height: 80, alignment: .bottom)
        }
        .onAppear {
            appeared = true
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
