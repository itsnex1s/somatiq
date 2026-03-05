import SwiftUI

struct OnboardingView: View {
    let onComplete: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var step: Int = 0
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var heroGlow = false
    @State private var featuresAppeared = false
    private let healthDataProvider: any HealthDataProviding

    init(
        healthDataProvider: any HealthDataProviding = HealthKitService(),
        onComplete: @escaping () -> Void
    ) {
        self.healthDataProvider = healthDataProvider
        self.onComplete = onComplete
    }

    var body: some View {
        ZStack {
            SomatiqColor.bg.ignoresSafeArea()

            VStack(spacing: 28) {
                Spacer()

                if step == 0 {
                    welcomeContent
                        .transition(.asymmetric(
                            insertion: .move(edge: .trailing).combined(with: .opacity),
                            removal: .move(edge: .leading).combined(with: .opacity)
                        ))
                } else {
                    permissionContent
                        .transition(.asymmetric(
                            insertion: .move(edge: .trailing).combined(with: .opacity),
                            removal: .move(edge: .leading).combined(with: .opacity)
                        ))
                }

                Spacer()

                Button {
                    primaryAction()
                } label: {
                    Text(primaryButtonTitle)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
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
                .disabled(isLoading)
                .somatiqShadow(tint: SomatiqColor.accent, intensity: .prominent)
                .buttonStyle(.somatiqPressable)

                if step == 1 {
                    Button("Not now") {
                        onComplete()
                    }
                    .foregroundStyle(SomatiqColor.textSecondary)
                    .buttonStyle(.somatiqPressable)
                }
            }
            .padding(SomatiqSpacing.lg)
        }
        .errorAlert(title: "Permission", message: $errorMessage)
    }

    private var welcomeContent: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [SomatiqColor.accent.opacity(heroGlow ? 0.25 : 0.1), .clear],
                            center: .center,
                            startRadius: 20,
                            endRadius: 80
                        )
                    )
                    .frame(width: 160, height: 160)

                Image(systemName: "heart.text.square.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [SomatiqColor.accent, SomatiqColor.sleep],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 2.5).repeatForever(autoreverses: true)) {
                    heroGlow = true
                }
            }

            Text("Know your body.\nOwn your data.")
                .font(.system(size: 30, weight: .bold))
                .multilineTextAlignment(.center)
                .foregroundStyle(SomatiqColor.textPrimary)

            Text("Somatiq computes Stress, Sleep, and Energy scores fully on-device. No account. No cloud.")
                .font(.system(size: 16))
                .multilineTextAlignment(.center)
                .foregroundStyle(SomatiqColor.textSecondary)
                .padding(.horizontal, 12)
        }
    }

    private var permissionContent: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [SomatiqColor.energy.opacity(0.15), .clear],
                            center: .center,
                            startRadius: 20,
                            endRadius: 80
                        )
                    )
                    .frame(width: 160, height: 160)

                Image(systemName: "applewatch.side.right")
                    .font(.system(size: 64))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [SomatiqColor.energy, SomatiqColor.energySecondary],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }

            Text("Connect Apple Health")
                .font(.system(size: 28, weight: .bold))
                .multilineTextAlignment(.center)
                .foregroundStyle(SomatiqColor.textPrimary)

            VStack(alignment: .leading, spacing: 12) {
                featureRow(icon: "waveform.path.ecg", text: "HRV and resting heart rate", index: 0)
                featureRow(icon: "moon.stars.fill", text: "Sleep stages and duration", index: 1)
                featureRow(icon: "flame.fill", text: "Active energy and steps", index: 2)
            }
            .padding(SomatiqSpacing.cardPadding)
            .somatiqCardStyle()
            .onAppear {
                withAnimation { featuresAppeared = true }
            }
        }
    }

    private func featureRow(icon: String, text: String, index: Int) -> some View {
        Label(text, systemImage: icon)
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(SomatiqColor.textSecondary)
            .opacity(featuresAppeared ? 1 : 0)
            .offset(x: featuresAppeared ? 0 : -10)
            .animation(
                reduceMotion ? .linear(duration: 0.1) : SomatiqAnimation.staggered(index: index),
                value: featuresAppeared
            )
    }

    private var primaryButtonTitle: String {
        if step == 0 {
            return "Continue"
        }
        return isLoading ? "Connecting..." : "Allow Apple Health Access"
    }

    private func primaryAction() {
        if step == 0 {
            withAnimation(SomatiqAnimation.cardEntrance) {
                step = 1
            }
            return
        }

        isLoading = true
        Task {
            do {
                try await healthDataProvider.authorizeAndEnableBackgroundDelivery()
                onComplete()
            } catch {
                AppLog.error("OnboardingView.primaryAction", error: error)
                errorMessage = AppErrorMapper.userMessage(for: error)
            }
            isLoading = false
        }
    }
}
