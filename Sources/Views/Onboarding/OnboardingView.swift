import SwiftUI

struct OnboardingView: View {
    let onComplete: () -> Void

    @State private var step: Int = 0
    @State private var isLoading = false
    @State private var errorMessage: String?
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
                } else {
                    permissionContent
                }

                Spacer()

                Button(primaryButtonTitle) {
                    primaryAction()
                }
                .buttonStyle(.borderedProminent)
                .tint(SomatiqColor.accent)
                .controlSize(.large)
                .disabled(isLoading)

                if step == 1 {
                    Button("Not now") {
                        onComplete()
                    }
                    .foregroundStyle(SomatiqColor.textSecondary)
                }
            }
            .padding(24)
        }
        .errorAlert(title: "Permission", message: $errorMessage)
    }

    private var welcomeContent: some View {
        VStack(spacing: 14) {
            Image(systemName: "heart.text.square.fill")
                .font(.system(size: 52))
                .foregroundStyle(SomatiqColor.accent)

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
            Image(systemName: "applewatch.side.right")
                .font(.system(size: 52))
                .foregroundStyle(SomatiqColor.energy)

            Text("Connect Apple Health")
                .font(.system(size: 28, weight: .bold))
                .multilineTextAlignment(.center)
                .foregroundStyle(SomatiqColor.textPrimary)

            VStack(alignment: .leading, spacing: 8) {
                Label("HRV and resting heart rate", systemImage: "waveform.path.ecg")
                Label("Sleep stages and duration", systemImage: "moon.stars.fill")
                Label("Active energy and steps", systemImage: "flame.fill")
            }
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(SomatiqColor.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(SomatiqColor.card.opacity(0.75))
            .clipShape(RoundedRectangle(cornerRadius: SomatiqRadius.cardMedium))
        }
    }

    private var primaryButtonTitle: String {
        if step == 0 {
            return "Continue"
        }
        return isLoading ? "Connecting..." : "Allow Apple Health Access"
    }

    private func primaryAction() {
        if step == 0 {
            step = 1
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
