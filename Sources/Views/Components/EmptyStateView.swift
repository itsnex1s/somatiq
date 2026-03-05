import SwiftUI

struct EmptyStateView: View {
    let title: String
    let message: String
    let buttonTitle: String
    let action: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [SomatiqColor.accent.opacity(0.15), .clear],
                            center: .center,
                            startRadius: 10,
                            endRadius: 50
                        )
                    )
                    .frame(width: 100, height: 100)

                Image(systemName: "applewatch.radiowaves.left.and.right")
                    .font(.system(size: 48))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [SomatiqColor.accent, SomatiqColor.sleep],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }

            Text(title)
                .font(.headline)
                .foregroundStyle(SomatiqColor.textPrimary)

            Text(message)
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(SomatiqColor.textSecondary)

            Button(action: action) {
                Text(buttonTitle)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
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
            .somatiqShadow(tint: SomatiqColor.accent, intensity: .standard)
        }
        .padding(SomatiqSpacing.xl)
        .frame(maxWidth: .infinity)
        .somatiqCardStyle()
    }
}
