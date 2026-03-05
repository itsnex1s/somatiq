import SwiftUI

struct InsightCard: View {
    let text: String

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Circle()
                    .fill(SomatiqColor.accent)
                    .frame(width: 8, height: 8)
                    .opacity(pulse ? 0.55 : 1)
                    .scaleEffect(pulse ? 0.9 : 1)
                    .animation(
                        reduceMotion ? .linear(duration: 0.1) : .easeInOut(duration: 2).repeatForever(),
                        value: pulse
                    )

                Text("Daily Insight")
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(0.5)
                    .textCase(.uppercase)
                    .foregroundStyle(Color(red: 129 / 255, green: 140 / 255, blue: 248 / 255))
            }

            Text(text)
                .font(.system(size: 14))
                .foregroundStyle(SomatiqColor.textSecondary)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .background(SomatiqColor.insightGradient)
        .overlay(
            RoundedRectangle(cornerRadius: SomatiqRadius.cardMedium)
                .stroke(SomatiqColor.accent.opacity(0.2), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: SomatiqRadius.cardMedium))
        .onAppear {
            pulse = true
        }
    }
}
