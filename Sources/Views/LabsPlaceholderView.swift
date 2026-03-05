import SwiftUI

struct LabsPlaceholderView: View {
    var body: some View {
        ZStack {
            SomatiqColor.bg.ignoresSafeArea()

            VStack(spacing: 16) {
                Image(systemName: "testtube.2")
                    .font(.system(size: 36))
                    .foregroundStyle(SomatiqColor.textTertiary)

                Text("Labs are coming in v3")
                    .font(.title3.bold())
                    .foregroundStyle(SomatiqColor.textPrimary)

                Text("Photo-to-biomarker import and tracking will be added in a future release.")
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(SomatiqColor.textSecondary)
                    .padding(.horizontal, 32)

                Button("Learn more") {
                }
                .buttonStyle(.bordered)
                .tint(SomatiqColor.accent)
            }
            .padding(24)
            .background(SomatiqColor.card.opacity(0.75))
            .overlay(
                RoundedRectangle(cornerRadius: SomatiqRadius.cardMedium)
                    .stroke(SomatiqColor.border, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: SomatiqRadius.cardMedium))
            .padding(20)
        }
    }
}
