import SwiftUI

struct LabsPlaceholderView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var contentAppeared = false
    @State private var iconPulse = false

    var body: some View {
        ZStack {
            SomatiqColor.bg.ignoresSafeArea()

            VStack(spacing: 16) {
                Image(systemName: "testtube.2")
                    .font(.system(size: 36))
                    .foregroundStyle(SomatiqColor.textTertiary)
                    .scaleEffect(iconPulse ? 1.05 : 1)
                    .animation(
                        reduceMotion ? .linear(duration: 0.1) : .easeInOut(duration: 2.2).repeatForever(autoreverses: true),
                        value: iconPulse
                    )

                Text("Labs are coming in v3")
                    .font(.title3.bold())
                    .foregroundStyle(SomatiqColor.textPrimary)

                Text("Photo-to-biomarker import and tracking will be added in a future release.")
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(SomatiqColor.textSecondary)
                    .padding(.horizontal, 32)

                Button(action: {}) {
                    Text("Learn more")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(
                            LinearGradient(
                                colors: [SomatiqColor.accent, SomatiqColor.sleep],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .clipShape(Capsule())
                        .overlay {
                            Capsule()
                                .stroke(
                                    LinearGradient(
                                        colors: [Color.white.opacity(0.24), SomatiqColor.accent.opacity(0.35), Color.white.opacity(0.08)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 0.95
                                )
                        }
                }
            }
            .padding(24)
            .somatiqCardStyle()
            .padding(20)
            .opacity(contentAppeared ? 1 : 0)
            .offset(y: contentAppeared ? 0 : 16)
            .animation(SomatiqAnimation.sectionReveal, value: contentAppeared)
        }
        .onAppear {
            contentAppeared = true
            guard !reduceMotion else { return }
            iconPulse = true
        }
    }
}
