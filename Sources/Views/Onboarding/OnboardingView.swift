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

            VStack(spacing: 18) {
                onboardingHeader
                    .padding(.top, 8)

                Spacer(minLength: 4)

                Group {
                    if step == 0 {
                        welcomeContent
                    } else {
                        permissionContent
                    }
                }

                Spacer(minLength: 8)

                primaryButton

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

    private var onboardingHeader: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Somatiq")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(SomatiqColor.textPrimary)
                Text("Private body intelligence")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(SomatiqColor.textTertiary)
            }

            Spacer()

            HStack(spacing: 6) {
                ForEach(0..<2, id: \.self) { index in
                    Capsule(style: .continuous)
                        .fill(index == step ? SomatiqColor.accent.opacity(0.95) : Color.white.opacity(0.14))
                        .frame(width: index == step ? 20 : 8, height: 8)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                LinearGradient(
                    colors: [Color(hex: "#1B1D2A"), Color(hex: "#10111A")],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: Capsule(style: .continuous)
            )
            .overlay {
                Capsule(style: .continuous)
                    .stroke(Color.white.opacity(0.1), lineWidth: 0.7)
            }
        }
    }

    private var welcomeContent: some View {
        VStack(spacing: 14) {
            heroSymbol(
                icon: "waveform.path.ecg",
                title: "Know your body.\nOwn your data.",
                subtitle: "Somatiq computes core scores fully on-device. No account. No cloud."
            )

            GlassCard(tint: SomatiqColor.accent) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("What you’ll see on Today")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(SomatiqColor.textPrimary)

                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                        previewTile(icon: "battery.100", label: "Battery", tint: SomatiqColor.bodyBattery)
                        previewTile(icon: "brain.head.profile", label: "Stress", tint: SomatiqColor.stress)
                        previewTile(icon: "moon.stars.fill", label: "Sleep", tint: SomatiqColor.sleep)
                        previewTile(icon: "heart.fill", label: "Heart", tint: SomatiqColor.heart)
                    }
                }
            }
        }
    }

    private var permissionContent: some View {
        VStack(spacing: 14) {
            heroSymbol(
                icon: "applewatch.side.right",
                title: "Connect Apple Health",
                subtitle: "Somatiq reads only the metrics needed for recovery insights."
            )

            VStack(alignment: .leading, spacing: 12) {
                featureRow(icon: "waveform.path.ecg", text: "HRV and resting heart rate", tint: SomatiqColor.heart)
                featureRow(icon: "moon.stars.fill", text: "Sleep stages and duration", tint: SomatiqColor.sleep)
                featureRow(icon: "flame.fill", text: "Active energy and steps", tint: SomatiqColor.bodyBattery)
            }
            .padding(SomatiqSpacing.cardPadding)
            .somatiqCardStyle(tint: SomatiqColor.energy)
        }
    }

    private func previewTile(icon: String, label: String, tint: Color) -> some View {
        HStack(spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 22, height: 22)
                .background(tint.opacity(0.16), in: Circle())

            Text(label)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(SomatiqColor.textSecondary)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func featureRow(icon: String, text: String, tint: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 24, height: 24)
                .background(tint.opacity(0.16), in: Circle())

            Text(text)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(SomatiqColor.textSecondary)

            Spacer(minLength: 0)
        }
    }

    private func heroSymbol(icon: String, title: String, subtitle: String) -> some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [SomatiqColor.accent.opacity(0.18), .clear],
                            center: .center,
                            startRadius: 20,
                            endRadius: 84
                        )
                    )
                    .frame(width: 156, height: 156)

                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color(hex: "#171929"), Color(hex: "#0C0D15")],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 86, height: 86)
                    .overlay {
                        Circle()
                            .stroke(Color.white.opacity(0.15), lineWidth: 0.8)
                    }

                Image(systemName: icon)
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [SomatiqColor.accent, SomatiqColor.sleep],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }

            VStack(spacing: 8) {
                Text(title)
                    .font(.system(size: 29, weight: .bold))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(SomatiqColor.textPrimary)

                Text(subtitle)
                    .font(.system(size: 15))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(SomatiqColor.textSecondary)
                    .padding(.horizontal, 10)
            }
        }
    }

    private var primaryButton: some View {
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
