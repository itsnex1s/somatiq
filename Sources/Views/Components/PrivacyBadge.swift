import SwiftUI

struct PrivacyBadge: View {
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "lock.fill")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(SomatiqColor.textMuted)

            Text("100% ON-DEVICE · ZERO CLOUD · OPEN SOURCE")
                .font(.system(size: 10, weight: .medium))
                .tracking(0.5)
                .foregroundStyle(SomatiqColor.textMuted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }
}
