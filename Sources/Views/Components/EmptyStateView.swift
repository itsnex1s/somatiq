import SwiftUI

struct EmptyStateView: View {
    let title: String
    let message: String
    let buttonTitle: String
    let action: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "applewatch.radiowaves.left.and.right")
                .font(.system(size: 30))
                .foregroundStyle(SomatiqColor.textTertiary)

            Text(title)
                .font(.headline)
                .foregroundStyle(SomatiqColor.textPrimary)

            Text(message)
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(SomatiqColor.textSecondary)

            Button(buttonTitle, action: action)
                .buttonStyle(.borderedProminent)
                .tint(SomatiqColor.accent)
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(SomatiqColor.card.opacity(0.7))
        .overlay(
            RoundedRectangle(cornerRadius: SomatiqRadius.cardMedium)
                .stroke(SomatiqColor.softBorder, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: SomatiqRadius.cardMedium))
    }
}
