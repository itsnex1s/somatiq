import SwiftUI

struct InsightCard: View {
    let text: String

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false
    @State private var glowOpacity: Double = 0.15

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "brain.head.profile")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [SomatiqColor.accent, SomatiqColor.energy],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                Circle()
                    .fill(SomatiqColor.accent)
                    .frame(width: 6, height: 6)
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
        .padding(SomatiqSpacing.cardPadding)
        .somatiqCardStyle(tint: SomatiqColor.accent)
        .overlay(
            RoundedRectangle(cornerRadius: SomatiqRadius.cardMedium, style: .continuous)
                .stroke(SomatiqColor.accent.opacity(glowOpacity), lineWidth: 1)
        )
        .onAppear {
            pulse = true
            if !reduceMotion {
                withAnimation(.easeInOut(duration: 2).repeatForever(autoreverses: true)) {
                    glowOpacity = 0.35
                }
            }
        }
    }
}
